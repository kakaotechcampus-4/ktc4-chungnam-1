// 소감 화면의 `리포트 만들기` 가 서버에 남기는 순서를 확인한다.
//
// `lib/features/review/submission_controller.dart`. 서버 대신 `FakeVisitApi`
// 를 쓰고 값은 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/review/review_controller.dart';
import 'package:saerok/features/review/submission_controller.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_visit_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 두 장을 고르고 소감 앞까지 온 상태를 만든다.
  Future<ProviderContainer> afterVisit(
    FakeVisitApi api, {
    bool startRecording = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ...mockCardsWith(visitApi: api),
      ],
    );
    addTearDown(container.dispose);

    final cards = await container.read(cardsControllerProvider.future);
    for (final card in cards.cards.take(2)) {
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(card.cardId);
    }
    await container.read(visitControllerProvider.future);
    final visit = container.read(visitControllerProvider.notifier);
    if (startRecording) {
      await visit.startRecording();
      await visit.stopRecording(participantCount: 2);
    }

    final review = container.read(reviewControllerProvider.notifier);
    review.setSatisfaction(4);
    review.setReaction(CareRecipientReaction.pleased);
    return container;
  }

  test('회차에 평가를 저장한다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final cards = container.read(visitControllerProvider).value!.cards;
    container
        .read(reviewControllerProvider.notifier)
        .setCardReaction(cards.first.cardId, CaregiverReaction.positive);

    final sent = await container.read(submissionProvider.notifier).submit();

    expect(sent, isTrue);
    expect(api.evaluated?.sessionId, FakeVisitApi.sessionId);
    final body = api.evaluated!.evaluation.toJson();
    expect(body, {
      'conversationSatisfaction': 4,
      'careRecipientReaction': 'pleased',
      'cardReviews': [
        {
          'cardId': cards.first.cardId,
          'wasUsed': true,
          'caregiverReaction': 'positive',
        },
      ],
      'freeNote': null,
    });
    final state = container.read(submissionProvider);
    expect(state.evaluationSaved, isTrue);
    expect(state.failure, isNull);
  });

  test('쓰지 않은 카드는 평가 없이 보낸다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final cards = container.read(visitControllerProvider).value!.cards;
    container
        .read(reviewControllerProvider.notifier)
        .setCardNotUsed(cards.first.cardId);

    await container.read(submissionProvider.notifier).submit();

    expect(api.evaluated!.evaluation.toJson()['cardReviews'], [
      {
        'cardId': cards.first.cardId,
        'wasUsed': false,
        'caregiverReaction': null,
      },
    ]);
  });

  test('보내지 못하면 실패를 남기고 다시 누르면 다시 보낸다', () async {
    final api = FakeVisitApi(failEvaluation: true);
    final container = await afterVisit(api);
    final controller = container.read(submissionProvider.notifier);

    expect(await controller.submit(), isFalse);
    var state = container.read(submissionProvider);
    expect(state.failure, SubmissionFailure.network);
    expect(state.evaluationSaved, isFalse);
    expect(state.sending, isFalse);

    api.failEvaluation = false;
    expect(await controller.submit(), isTrue);
    state = container.read(submissionProvider);
    expect(state.evaluationSaved, isTrue);
    expect(state.failure, isNull);
  });

  test('저장한 평가는 다시 보내지 않는다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api);
    final controller = container.read(submissionProvider.notifier);

    await controller.submit();
    await controller.submit();

    expect(api.calls.where((c) => c == 'evaluation'), hasLength(1));
  });

  test('서버에 회차가 없으면 보내지 않는다', () async {
    final api = FakeVisitApi();
    final container = await afterVisit(api, startRecording: false);

    final sent = await container.read(submissionProvider.notifier).submit();

    expect(sent, isFalse);
    expect(api.calls, isEmpty);
    expect(
      container.read(submissionProvider).failure,
      SubmissionFailure.noSession,
    );
  });
}
