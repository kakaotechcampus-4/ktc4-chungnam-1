/// 기기에 남은 면회 녹음 파일을 다른 앱으로 보낸다(2026-11-09 PM 결정).
///
/// 녹음 파일은 앱 전용 공간의 `visit_recordings/` 에 있어 다른 앱이나 파일
/// 관리자로 꺼낼 수 없다([VisitRecording]). 리포트 화면의 `녹음 파일 공유` 가
/// 안드로이드 공유 창을 열어 보호자가 보낼 곳을 고르게 한다. 파일은 회차 ID 로
/// 녹음 기록([PendingUploads])에서 찾으며, 지금 로그인한 계정의 녹음만 찾는다.
///
/// 리포트를 만들지 못한 회차도 녹음이 남았으면 공유할 수 있다(2026-11-10 PM
/// 결정). 홈과 알림의 실패 알림을 누르면 고르는 시트(`failed_report_sheet.dart`)와
/// 분석을 다시 요청하지 못한 화면(`upload_retry_screen.dart`)이 여기의
/// [shareVisitRecording] 과 [RecordingShareButton] 을 함께 쓴다.
///
/// 공유 창은 `share_plus` 가 연다. 안드로이드에서는 파일을 앱 캐시의
/// `share_plus/` 에 복사한 뒤 받는 앱에 읽기 권한을 준다. 그 사본은 다음에
/// 공유할 때 지워지고, 그 전에는 캐시를 비울 때 지워진다. 탈퇴하면 이 사본도
/// 지운다([RecordingShare.forgetCopies]). 테스트는 [recordingShareProvider] 를
/// override 해 기기 없이 확인한다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
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
Future<String?> findVisitRecordingPath(
  PendingUploads uploads,
  String sessionId,
) async {
  try {
    final upload = await uploads.find(sessionId, includeUploaded: true);
    return upload?.audioPath;
  } on Exception {
    return null;
  }
}

/// 화면이 보는 [findVisitRecordingPath].
final visitRecordingPathProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, sessionId) =>
          findVisitRecordingPath(ref.watch(pendingUploadsProvider), sessionId),
    );

/// 회차([sessionId])의 녹음 파일([path])로 공유 창을 연다.
///
/// 그 사이 파일이 사라졌으면 `녹음 파일을 찾지 못했어요.` 를 알리고 녹음을 다시
/// 찾게 해 공유 버튼을 거둔다. 공유 창을 열지 못하면 `녹음 파일을 공유하지
/// 못했어요.` 를 알린다. 기다리는 사이 [context] 가 사라졌으면 알리지 않는다.
Future<void> shareVisitRecording(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String path,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(recordingShareProvider).share(path);
  if (!context.mounted) return;
  final message = switch (result) {
    RecordingShareResult.opened => null,
    RecordingShareResult.missing => '녹음 파일을 찾지 못했어요.',
    RecordingShareResult.failed => '녹음 파일을 공유하지 못했어요.',
  };
  if (result == RecordingShareResult.missing) {
    ref.invalidate(visitRecordingPathProvider(sessionId));
  }
  if (message == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 이 기기에 남은 면회 녹음 파일([path])을 다른 앱으로 보내는 버튼.
///
/// 안내 문구 없이 버튼만 둔다(2026-11-09 PM 결정). 보낼 곳은 공유 창에서
/// 보호자가 고른다. 공유 창을 여는 동안에는 두 번 열지 않도록 막는다.
class RecordingShareButton extends ConsumerStatefulWidget {
  const RecordingShareButton({
    required this.sessionId,
    required this.path,
    super.key,
  });

  final String sessionId;
  final String path;

  @override
  ConsumerState<RecordingShareButton> createState() =>
      _RecordingShareButtonState();
}

class _RecordingShareButtonState extends ConsumerState<RecordingShareButton> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    await shareVisitRecording(
      context,
      ref,
      sessionId: widget.sessionId,
      path: widget.path,
    );
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      borderColor: HomeColors.outline,
      icon: Icons.share_outlined,
      label: '녹음 파일 공유',
      onPressed: _sharing ? null : _share,
    );
  }
}
