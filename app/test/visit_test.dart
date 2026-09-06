// D, E 화면(면회 전 사진과 녹음, 면회 중 대화 카드)의 규칙을 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/visit_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  /// 선택 화면에서 카드 두 장을 고른 상태를 만든다.
  Future<ProviderContainer> withSelection(int count) async {
    final container = makeContainer();
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

      controller.addCards(supplements.take(1));
      expect(container.read(visitControllerProvider).value!.cards, hasLength(3));

      // 같은 카드를 두 번 더하지 않는다.
      controller.addCards(supplements.take(1));
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
    test('피보호자 동의를 확인해야 시작할 수 있다', () async {
      final container = await withSelection(1);
      final initial = await container.read(visitControllerProvider.future);

      // 계약의 VisitSession.consent.careRecipientConfirmation 에 해당한다.
      expect(initial.careRecipientConfirmed, isFalse);

      container
          .read(visitControllerProvider.notifier)
          .confirmCareRecipient(confirmed: true);
      expect(
        container.read(visitControllerProvider).value!.careRecipientConfirmed,
        isTrue,
      );
    });

    test('잠시 멈춰도 시작 전으로 돌아가지 않는다', () async {
      final container = await withSelection(1);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);

      controller.startRecording();
      var state = container.read(visitControllerProvider).value!;
      expect(state.started, isTrue);
      expect(state.recording, isTrue);

      controller.pauseRecording();
      state = container.read(visitControllerProvider).value!;
      expect(state.recording, isFalse);
      expect(state.started, isTrue, reason: '녹음 화면에 그대로 머문다');

      controller.startRecording();
      expect(container.read(visitControllerProvider).value!.recording, isTrue);
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
}
