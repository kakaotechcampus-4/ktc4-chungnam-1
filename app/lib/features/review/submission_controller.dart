import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/visit_api.dart';
import '../visit/visit_controller.dart';
import 'review_controller.dart';

/// 소감 화면의 `리포트 만들기` 가 실패한 까닭. 화면은 이 값으로 문구를 고른다.
enum SubmissionFailure {
  /// 서버에 닿지 못했다.
  network,

  /// 서버가 거절했거나 응답이 계약과 달랐다.
  server,

  /// 서버에 회차가 없다. 녹음을 시작하지 못한 채 소감까지 온 경우다.
  noSession,
}

class SubmissionState {
  const SubmissionState({
    this.evaluationSaved = false,
    this.sending = false,
    this.failure,
  });

  /// 평가(API 6-1)를 저장했는지. 저장했으면 다시 보내지 않는다.
  final bool evaluationSaved;

  /// 보내는 중인지. 그동안 버튼을 막는다.
  final bool sending;

  /// 마지막 시도가 실패했으면 그 까닭이다.
  final SubmissionFailure? failure;
}

/// 면회를 마치고 서버에 남기는 일. API 6절의 순서를 따른다.
///
/// 평가(6-1)를 먼저 저장한다. 저장한 뒤 실패하면 평가는 다시 보내지 않는다.
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

    final sessionId = ref.read(visitControllerProvider).value?.sessionId;
    if (sessionId == null) {
      state = SubmissionState(
        evaluationSaved: state.evaluationSaved,
        failure: SubmissionFailure.noSession,
      );
      return false;
    }

    state = SubmissionState(
      evaluationSaved: state.evaluationSaved,
      sending: true,
    );
    try {
      if (!state.evaluationSaved) {
        final cards = await ref.read(reviewCardsProvider.future);
        final evaluation = ref
            .read(reviewControllerProvider.notifier)
            .toSubmission(cards: cards);
        // 필수 답이 없으면 버튼이 눌리지 않는다. 여기 오면 화면이 어긋난 것이다.
        if (evaluation == null) throw StateError('필수 답이 없다');

        await ref
            .read(visitApiProvider)
            .submitEvaluation(sessionId, evaluation);
        if (!ref.mounted) return false;
        state = const SubmissionState(evaluationSaved: true, sending: true);
      }
    } on ApiNetworkFailure {
      _fail(SubmissionFailure.network);
      return false;
    } on ApiFailure {
      _fail(SubmissionFailure.server);
      return false;
    }

    if (!ref.mounted) return false;
    state = SubmissionState(evaluationSaved: state.evaluationSaved);
    return true;
  }

  void _fail(SubmissionFailure failure) {
    if (!ref.mounted) return;
    state = SubmissionState(
      evaluationSaved: state.evaluationSaved,
      failure: failure,
    );
  }
}

final submissionProvider =
    NotifierProvider<SubmissionController, SubmissionState>(
      SubmissionController.new,
    );
