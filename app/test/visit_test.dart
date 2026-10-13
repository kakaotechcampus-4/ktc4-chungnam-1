// D, E 화면(면회 전 사진과 녹음, 면회 중 대화 카드)의 규칙을 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_visit_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 실제 마이크는 테스트에서 열 수 없다. 장치 부르는 순서는
  // `visit_recording_test.dart` 에서 따로 본다.
  ProviderContainer makeContainer({
    FakeVisitApi? visitApi,
    FakeVisitRecorder? recorder,
  }) {
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(
          recorder ?? FakeVisitRecorder(),
        ),
        ...mockCardsWith(visitApi: visitApi),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 선택 화면에서 카드 두 장을 고른 상태를 만든다.
  Future<ProviderContainer> withSelection(
    int count, {
    FakeVisitApi? visitApi,
    FakeVisitRecorder? recorder,
  }) async {
    final container = makeContainer(visitApi: visitApi, recorder: recorder);
    final cards = await container.read(cardsControllerProvider.future);
    final controller = container.read(cardsControllerProvider.notifier);
    for (final card in cards.cards.take(count)) {
      controller.toggleSelected(card.cardId);
    }
    return container;
  }

  group('면회 카드 구성', () {
    test('선택 화면에서 고른 카드만 면회로 넘어온다', () async {
      final container = await withSelection(2);
      final visit = await container.read(visitControllerProvider.future);

      expect(visit.cards, hasLength(2));
      expect(visit.currentIndex, 0);
      expect(visit.progress, 0.5);
    });

    test('보충용 카드는 뒤 3장이다', () async {
      final container = makeContainer();
      final all = await container.read(conversationCardsProvider.future);
      final supplements =
          await container.read(supplementCardsProvider.future);

      expect(supplements, hasLength(3));
      expect(
        supplements.map((c) => c.cardId),
        all.skip(CardRules.selectableCount).map((c) => c.cardId),
      );
    });

    test('보충 카드를 더하면 회차 카드가 늘어난다', () async {
      final container = await withSelection(2);
      await container.read(visitControllerProvider.future);
      final supplements =
          await container.read(supplementCardsProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      await controller.addCards(supplements.take(1));
      expect(container.read(visitControllerProvider).value!.cards, hasLength(3));

      // 같은 카드를 두 번 더하지 않는다.
      await controller.addCards(supplements.take(1));
      expect(container.read(visitControllerProvider).value!.cards, hasLength(3));
    });
  });

  group('면회 진행', () {
    test('마지막 카드에서는 다음으로 넘어가지 않는다', () async {
      final container = await withSelection(2);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      controller.nextCard();
      var state = container.read(visitControllerProvider).value!;
      expect(state.currentIndex, 1);
      expect(state.isLastCard, isTrue);
      expect(state.progress, 1.0);

      controller.nextCard();
      expect(container.read(visitControllerProvider).value!.currentIndex, 1);
    });

    test('꼬리 질문은 3개를 돌아가며 보여준다', () async {
      final container = await withSelection(1);
      final state = await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);
      final questions = state.currentCard!.followUpQuestions;

      expect(questions, hasLength(3));
      expect(state.currentFollowUp, questions[0]);

      controller.nextFollowUp();
      expect(
        container.read(visitControllerProvider).value!.currentFollowUp,
        questions[1],
      );

      controller.nextFollowUp();
      controller.nextFollowUp();
      expect(
        container.read(visitControllerProvider).value!.currentFollowUp,
        questions[0],
        reason: '마지막 다음에는 처음으로 돌아간다',
      );
    });

    test('카드를 넘기면 꼬리 질문도 처음부터 시작한다', () async {
      final container = await withSelection(2);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      controller.nextFollowUp();
      controller.nextCard();

      expect(container.read(visitControllerProvider).value!.followUpIndex, 0);
    });
  });

  group('녹음', () {
    test('잠시 멈춰도 시작 전으로 돌아가지 않는다', () async {
      final container = await withSelection(1);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      await controller.startRecording();
      var state = container.read(visitControllerProvider).value!;
      expect(state.started, isTrue);
      expect(state.recording, isTrue);

      await controller.pauseRecording();
      state = container.read(visitControllerProvider).value!;
      expect(state.recording, isFalse);
      expect(state.started, isTrue, reason: '녹음 화면에 그대로 머문다');

      await controller.startRecording();
      expect(container.read(visitControllerProvider).value!.recording, isTrue);
    });

    test('새 회차를 시작하면 지난 회차의 상태가 남지 않는다', () async {
      final container = await withSelection(1);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      await controller.startRecording();
      controller.nextFollowUp();
      expect(container.read(visitControllerProvider).value!.started, isTrue);

      // 대화 시작하기를 누를 때 화면이 하는 일과 같다.
      container.invalidate(visitControllerProvider);
      final fresh = await container.read(visitControllerProvider.future);

      expect(fresh.started, isFalse);
      expect(fresh.recording, isFalse);
      expect(fresh.elapsed, Duration.zero);
      expect(fresh.followUpIndex, 0);
      expect(fresh.recordingPath, isNull, reason: '지난 회차의 녹음 파일을 물려받지 않는다');
      expect(fresh.problem, isNull);
    });

    test('시간 표시는 시분초 형태다', () async {
      final container = await withSelection(1);
      final state = await container.read(visitControllerProvider.future);

      expect(state.elapsedLabel, '00:00:00');
      expect(
        state.copyWith(elapsed: const Duration(minutes: 5, seconds: 38))
            .elapsedLabel,
        '00:05:38',
      );
    });
  });

  group('서버 회차', () {
    test('녹음을 처음 시작할 때 고른 카드와 묶음으로 회차를 만든다', () async {
      final api = FakeVisitApi();
      final container = await withSelection(2, visitApi: api);
      final visit = await container.read(visitControllerProvider.future);
      final set = await container.read(currentCardSetProvider.future);

      await container.read(visitControllerProvider.notifier).startRecording();

      expect(api.created?.setId, set.setId);
      expect(
        api.created?.selectedCardIds,
        visit.cards.map((c) => c.cardId).toList(),
      );
      final state = container.read(visitControllerProvider).value!;
      expect(state.sessionId, FakeVisitApi.sessionId);
      expect(state.recording, isTrue);
    });

    test('잠시 멈췄다 이어 녹음해도 회차를 또 만들지 않는다', () async {
      final api = FakeVisitApi();
      final container = await withSelection(1, visitApi: api);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      await controller.startRecording();
      await controller.pauseRecording();
      await controller.startRecording();

      expect(api.calls.where((c) => c == 'create'), hasLength(1));
    });

    test('마이크 권한이 없으면 회차를 만들지 않는다', () async {
      final api = FakeVisitApi();
      final container = await withSelection(
        1,
        visitApi: api,
        recorder: FakeVisitRecorder(permitted: false),
      );
      await container.read(visitControllerProvider.future);

      await container.read(visitControllerProvider.notifier).startRecording();

      expect(api.calls, isEmpty);
      expect(
        container.read(visitControllerProvider).value!.problem,
        VisitRecordingProblem.permissionDenied,
      );
    });

    test('회차를 만들지 못하면 녹음을 시작하지 않는다', () async {
      final api = FakeVisitApi(failCreate: true);
      final container = await withSelection(1, visitApi: api);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      await controller.startRecording();

      var state = container.read(visitControllerProvider).value!;
      expect(state.problem, VisitRecordingProblem.sessionFailed);
      expect(state.started, isFalse);
      expect(state.sessionId, isNull);

      // 다시 누르면 처음부터 시도한다.
      api.failCreate = false;
      await controller.startRecording();
      state = container.read(visitControllerProvider).value!;
      expect(state.recording, isTrue);
      expect(state.problem, isNull);
    });

    test('회차가 있으면 보충 카드를 서버에 먼저 알린다', () async {
      final api = FakeVisitApi();
      final container = await withSelection(1, visitApi: api);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);
      final supplements = await container.read(supplementCardsProvider.future);
      await controller.startRecording();

      final added = await controller.addCards(supplements.take(1));

      expect(added, isTrue);
      expect(api.added, [supplements.first.cardId]);
      expect(container.read(visitControllerProvider).value!.cards, hasLength(2));
    });

    test('보충 카드를 서버에 알리지 못하면 화면에도 더하지 않는다', () async {
      final api = FakeVisitApi(failAdd: true);
      final container = await withSelection(1, visitApi: api);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);
      final supplements = await container.read(supplementCardsProvider.future);
      await controller.startRecording();

      final added = await controller.addCards(supplements.take(1));

      expect(added, isFalse);
      expect(container.read(visitControllerProvider).value!.cards, hasLength(1));
    });

    test('녹음 전에 더한 보충 카드는 회차를 만든 뒤 따로 더한다', () async {
      final api = FakeVisitApi();
      final container = await withSelection(1, visitApi: api);
      final visit = await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);
      final supplements = await container.read(supplementCardsProvider.future);

      await controller.addCards(supplements.take(1));
      expect(api.calls, isEmpty, reason: '회차가 없으니 아직 보내지 않는다');

      await controller.startRecording();

      expect(api.created?.selectedCardIds, [visit.cards.first.cardId]);
      expect(api.added, [supplements.first.cardId]);
    });
  });
}
