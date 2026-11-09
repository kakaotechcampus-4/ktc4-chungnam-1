/// 기기에 남은 면회 녹음 파일을 다른 앱으로 보낸다(2026-11-09 PM 결정).
///
/// 녹음 파일은 앱 전용 공간의 `visit_recordings/` 에 있어 다른 앱이나 파일
/// 관리자로 꺼낼 수 없다([VisitRecording]). 리포트 화면의 `녹음 파일 공유` 가
/// 안드로이드 공유 창을 열어 보호자가 보낼 곳을 고르게 한다. 파일은 회차 ID 로
/// 녹음 기록([PendingUploads])에서 찾으며, 지금 로그인한 계정의 녹음만 찾는다.
///
/// 공유 창은 `share_plus` 가 연다. 안드로이드에서는 파일을 앱 캐시의
/// `share_plus/` 에 복사한 뒤 받는 앱에 읽기 권한을 준다. 그 사본은 다음에
/// 공유할 때 지워지고, 그 전에는 캐시를 비울 때 지워진다. 탈퇴하면 이 사본도
/// 지운다([RecordingShare.forgetCopies]). 테스트는 [recordingShareProvider] 를
/// override 해 기기 없이 확인한다.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'pending_uploads.dart';
import 'visit_recorder.dart';

/// 공유를 시도한 결과.
enum RecordingShareResult {
  /// 공유 창을 열었다. 보호자가 보냈는지 닫았는지는 가르지 않는다.
  opened,

  /// 그 사이 파일이 사라졌다.
  missing,

  /// 공유 창을 열지 못했다.
  failed,
}

abstract interface class RecordingShare {
  /// [path] 의 녹음 파일로 공유 창을 연다.
  Future<RecordingShareResult> share(String path);

  /// 공유하며 남긴 녹음 사본을 모두 지운다. 탈퇴할 때 부른다.
  ///
  /// 사본은 계정을 가리지 않고 한 폴더에 있어 통째로 지운다. 공유할 때마다
  /// 다시 만들어지므로 다른 계정의 공유에는 지장이 없다.
  Future<void> forgetCopies();
}

/// `share_plus` 로 안드로이드 공유 창을 연다.
class DeviceRecordingShare implements RecordingShare {
  const DeviceRecordingShare();

  @override
  Future<RecordingShareResult> share(String path) async {
    if (!await File(path).exists()) return RecordingShareResult.missing;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: '면회 녹음 파일',
          files: [XFile(path, mimeType: 'audio/wav')],
        ),
      );
      return RecordingShareResult.opened;
    } on Exception {
      // 플러그인이 없거나(테스트, 지원하지 않는 기기) 채널이 실패했다.
      return RecordingShareResult.failed;
    }
  }

  /// `share_plus` 가 사본을 두는 앱 캐시의 `share_plus/` 를 지운다.
  /// 안드로이드에서 [getTemporaryDirectory] 는 그 앱 캐시다.
  @override
  Future<void> forgetCopies() async {
    final cache = await getTemporaryDirectory();
    final copies = Directory('${cache.path}/share_plus');
    try {
      if (await copies.exists()) await copies.delete(recursive: true);
    } on FileSystemException {
      // 남은 사본은 다음 공유나 캐시 정리 때 지워진다.
    }
  }
}

final recordingShareProvider = Provider<RecordingShare>(
  (ref) => const DeviceRecordingShare(),
);

/// 회차([sessionId])의 녹음 파일 경로. 기기에 없으면 `null` 이다.
///
/// 서버에 보낸 녹음도 찾는다. 다른 계정의 녹음, 기록이 없는 녹음과 사라진
/// 파일은 찾지 않는다. 기록을 읽지 못해도 `null` 로 두어 리포트를 막지 않는다.
final visitRecordingPathProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, sessionId) async {
      final uploads = ref.watch(pendingUploadsProvider);
      try {
        final upload = await uploads.find(sessionId, includeUploaded: true);
        return upload?.audioPath;
      } on Exception {
        return null;
      }
    });
