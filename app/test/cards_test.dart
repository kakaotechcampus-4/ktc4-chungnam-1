// 홈과 대화 카드 화면의 규칙을 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/cards/cards_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('대화 카드 규칙', () {
    test('12장 중 앞 9장만 선택 화면에 올린다', () async {
      final container = makeContainer();
      final all = await container.read(conversationCardsProvider.future);
      final state = await container.read(cardsControllerProvider.future);

      expect(all, hasLength(12), reason: '한 회차에 12장을 만든다');
      expect(state.cards, hasLength(CardRules.selectableCount));
      expect(
        state.cards.map((c) => c.cardId),
        all.take(9).map((c) => c.cardId),
        reason: '배열의 앞 9장이 선택 화면 대상이다',
      );
    });

    test('처음에는 3장만 보여주고 밀 때마다 3장씩 늘어난다', () async {
      final container = makeContainer();
      await container.read(cardsControllerProvider.future);
      final controller = container.read(cardsControllerProvider.notifier);

      expect(container.read(cardsControllerProvider).value!.visibleCards,
          hasLength(3));

      controller.showMore();
      expect(container.read(cardsControllerProvider).value!.visibleCards,
          hasLength(6));

      controller.showMore();
      final state = container.read(cardsControllerProvider).value!;
      expect(state.visibleCards, hasLength(9));
      expect(state.hasMore, isFalse, reason: '9장을 넘지 않는다');

      controller.showMore();
      expect(container.read(cardsControllerProvider).value!.visibleCards,
          hasLength(9));
    });

    test('아무것도 고르지 않은 상태로 시작한다', () async {
      final container = makeContainer();
      final initial = await container.read(cardsControllerProvider.future);

      expect(initial.selectedIds, isEmpty);
      expect(initial.canStart, isFalse, reason: '한 장도 없으면 시작할 수 없다');
    });

    test('선택을 껐다 켤 수 있다', () async {
      final container = makeContainer();
      final initial = await container.read(cardsControllerProvider.future);
      final controller = container.read(cardsControllerProvider.notifier);
      final first = initial.cards.first.cardId;

      controller.toggleSelected(first);
      var state = container.read(cardsControllerProvider).value!;
      expect(state.selectedIds, {first});
      expect(state.canStart, isTrue);

      controller.toggleSelected(first);
      state = container.read(cardsControllerProvider).value!;
      expect(state.selectedIds, isEmpty);
      expect(state.canStart, isFalse);
    });

    test('카드는 한 번에 하나만 펼친다', () async {
      final container = makeContainer();
      final state = await container.read(cardsControllerProvider.future);
      final controller = container.read(cardsControllerProvider.notifier);
      final first = state.cards[0].cardId;
      final second = state.cards[1].cardId;

      expect(state.expandedId, isNull);

      controller.toggleExpanded(first);
      expect(container.read(cardsControllerProvider).value!.expandedId, first);

      controller.toggleExpanded(second);
      expect(container.read(cardsControllerProvider).value!.expandedId, second);

      controller.toggleExpanded(second);
      expect(container.read(cardsControllerProvider).value!.expandedId, isNull);
    });
  });

  group('홈 알림', () {
    test('처음에는 알림이 있고 확인하면 사라진다', () {
      final container = makeContainer();

      expect(container.read(reportNoticeProvider), isTrue);

      container.read(reportNoticeProvider.notifier).dismiss();
      expect(container.read(reportNoticeProvider), isFalse);
    });
  });
}
