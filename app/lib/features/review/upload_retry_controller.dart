import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/providers.dart';
import '../../data/visit_api.dart';
import '../visit/pending_uploads.dart';

/// `음성 다시 보내기` 의 결과. 연결 실패와 서버 거절은 오류로 남는다.
enum UploadRetryOutcome {
  /// 서버가 녹음을 받았다.
  sent,

  /// 이 기기에 그 회차의 녹음 기록이나 파일이 없다.
  notFound,

  /// 서버가 이미 끝났거나 실패로 끝난 회차라고 했다. 다시 보내도 받지 않는다.
  alreadyClosed,
}

/// 앱을 다시 켠 뒤 홈 배너에서 들어와, 보내지 못한 녹음을 다시 보낸다.
///
/// 평가(API 6-1)는 이미 저장한 회차(`audioPending`)다. 기기에 남긴 기록
/// ([PendingUploads])에서 녹음 파일과 참여자 수를 찾아 6-2 로 보낸다. 들어오자마자
/// 보낸다. 보호자가 배너에서 이미 다시 보내기를 골랐기 때문이다.
class UploadRetryController extends AsyncNotifier<UploadRetryOutcome> {
  UploadRetryController(this.sessionId);

  /// 홈 배너가 넘긴 회차. 주소에 없으면 `null` 이다.
  final String? sessionId;

  @override
  Future<UploadRetryOutcome> build() async {
    final sessionId = this.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return UploadRetryOutcome.notFound;
    }

    final uploads = ref.read(pendingUploadsProvider);
    final pending = await uploads.find(sessionId);
    if (pending == null) return UploadRetryOutcome.notFound;

    try {
      await ref
          .read(visitApiProvider)
          .submitAudio(
            sessionId,
            audioPath: pending.audioPath,
            participantCount: pending.participantCount,
          );
    } on ApiServerFailure catch (failure) {
      if (!isClosedAnalysis(failure)) rethrow;
      await _forget(uploads, sessionId);
      return UploadRetryOutcome.alreadyClosed;
    } on FileSystemException {
      return UploadRetryOutcome.notFound;
    }

    await _forget(uploads, sessionId);
    if (ref.mounted) ref.read(reportNoticeProvider.notifier).startGenerating();
    return UploadRetryOutcome.sent;
  }

  /// 서버가 받았거나 다시 받지 않는 회차다. 지우다 실패해도 결과는 같다.
  Future<void> _forget(PendingUploads uploads, String sessionId) async {
    try {
      await uploads.remove(sessionId);
    } on Exception {
      // 남은 파일은 앱 전용 공간에 있다.
    }
  }

  /// 실패 화면의 다시 보내기.
  void retry() => ref.invalidateSelf();
}

/// 자동 재시도는 끈다. 다시 보내기는 화면의 버튼으로만 한다.
final uploadRetryProvider = AsyncNotifierProvider.autoDispose
    .family<UploadRetryController, UploadRetryOutcome, String?>(
      UploadRetryController.new,
      retry: (_, _) => null,
    );
