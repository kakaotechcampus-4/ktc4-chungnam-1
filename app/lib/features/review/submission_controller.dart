import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/visit_api.dart';
import '../visit/visit_controller.dart';
import 'recording_files.dart';
import 'review_controller.dart';

/// 소감 화면의 `리포트 만들기` 가 실패한 까닭. 화면은 이 값으로 문구를 고른다.
enum SubmissionFailure {
  /// 서버에 닿지 못했다.
  network,

  /// 서버가 거절했거나 응답이 계약과 달랐다.
  server,

  /// 서버에 회차가 없다. 녹음을 시작하지 못한 채 소감까지 온 경우다.
  noSession,

  /// 보낼 녹음 파일이나 참여자 수가 없다. 파일을 저장하지 못했거나, 끝내기
  /// 확인 창을 거치지 않고 녹음 화면을 떠난 경우다.
  noRecording,
}

class SubmissionState {
  const SubmissionState({
    this.evaluationSaved = false,
    this.sending = false,
    this.failure,
    this.analysisId,
  });

  /// 평가(API 6-1)를 저장했는지. 저장했으면 다시 보내지 않는다.
  final bool evaluationSaved;

  /// 보내는 중인지. 그동안 버튼을 막는다.
  final bool sending;

  /// 마지막 시도가 실패했으면 그 까닭이다.
  final SubmissionFailure? failure;

  /// 녹음을 받은 서버가 준 음성 분석 작업(API 6-2). 받기 전에는 `null` 이다.
  ///
  /// 분석 상태 조회(6-3)와 리포트 알림이 이 값을 쓴다.
  final String? analysisId;

  SubmissionState copyWith({
    bool? evaluationSaved,
    bool? sending,
    String? analysisId,
  }) => SubmissionState(
    evaluationSaved: evaluationSaved ?? this.evaluationSaved,
    sending: sending ?? this.sending,
    analysisId: analysisId ?? this.analysisId,
  );
}

/// 면회를 마치고 서버에 남기는 일. API 6절의 순서를 따른다.
///
/// 평가(6-1)를 저장한 뒤 녹음(6-2)을 보낸다. 평가를 저장한 뒤 녹음만 실패하면
/// 다시 누를 때 녹음만 보낸다. 서버가 녹음을 받으면 기기의 파일을 지운다.
/// 회차가 바뀌면 처음부터 다시 시작한다.
class SubmissionController extends Notifier<SubmissionState> {
  @override
  SubmissionState build() {
    ref.watch(visitControllerProvider.select((v) => v.value?.sessionId));
    return const SubmissionState();
  }

  /// 보낼 것을 모두 보냈으면 `true` 다. 실패하면 [SubmissionState.failure] 를
  /// 남기고 `false` 다.
  Future<bool> submit() async {
    if (state.sending) return false;

    final visit = ref.read(visitControllerProvider).value;
    final sessionId = visit?.sessionId;
    if (visit == null || sessionId == null) {
      _fail(SubmissionFailure.noSession);
      return false;
    }

    state = state.copyWith(sending: true);
    try {
      if (!state.evaluationSaved) {
        await _saveEvaluation(sessionId);
        if (!ref.mounted) return false;
        state = state.copyWith(evaluationSaved: true);
      }

      final audioPath = visit.recordingPath;
      final participantCount = visit.participantCount;
      if (audioPath == null || participantCount == null) {
        _fail(SubmissionFailure.noRecording);
        return false;
      }
      final analysisId = await _sendAudio(
        sessionId,
        audioPath: audioPath,
        participantCount: participantCount,
      );
      if (!ref.mounted) return false;

      // 서버가 받았으니 기기에 둘 까닭이 없다. 지우다 실패해도 제출은 끝났다.
      try {
        await ref.read(recordingFilesProvider).delete(audioPath);
      } on FileSystemException {
        // 다음에 다시 지울 길은 아직 없다. 남은 파일은 앱 전용 공간에 있다.
      }
      if (!ref.mounted) return false;
      state = SubmissionState(evaluationSaved: true, analysisId: analysisId);
      return true;
    } on FileSystemException {
      _fail(SubmissionFailure.noRecording);
      return false;
    } on ApiNetworkFailure {
      _fail(SubmissionFailure.network);
      return false;
    } on ApiFailure {
      _fail(SubmissionFailure.server);
      return false;
    }
  }

  Future<void> _saveEvaluation(String sessionId) async {
    final cards = await ref.read(reviewCardsProvider.future);
    final evaluation = ref
        .read(reviewControllerProvider.notifier)
        .toSubmission(cards: cards);
    // 필수 답이 없으면 버튼이 눌리지 않는다. 여기 오면 화면이 어긋난 것이다.
    if (evaluation == null) throw StateError('필수 답이 없다');

    await ref.read(visitApiProvider).submitEvaluation(sessionId, evaluation);
  }

  /// 녹음을 보내고 분석 작업 ID 를 받는다.
  ///
  /// 이미 끝났거나 실패로 끝난 회차라는 거절은 다시 보내도 받지 않는다. 그때는
  /// 분석 작업 ID 없이 끝낸 것으로 보고 파일을 지운다. 결과는 홈의 회차 상태가
  /// 알린다.
  Future<String?> _sendAudio(
    String sessionId, {
    required String audioPath,
    required int participantCount,
  }) async {
    try {
      return await ref
          .read(visitApiProvider)
          .submitAudio(
            sessionId,
            audioPath: audioPath,
            participantCount: participantCount,
          );
    } on ApiServerFailure catch (failure) {
      if (failure.statusCode == 409 &&
          (failure.errorCode == 'ANALYSIS_ALREADY_COMPLETED' ||
              failure.errorCode == 'ANALYSIS_ALREADY_FAILED')) {
        return null;
      }
      rethrow;
    }
  }

  void _fail(SubmissionFailure failure) {
    if (!ref.mounted) return;
    state = SubmissionState(
      evaluationSaved: state.evaluationSaved,
      analysisId: state.analysisId,
      failure: failure,
    );
  }
}

final submissionProvider =
    NotifierProvider<SubmissionController, SubmissionState>(
      SubmissionController.new,
    );
