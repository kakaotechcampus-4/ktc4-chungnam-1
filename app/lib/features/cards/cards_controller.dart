import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// 대화 카드 선택 화면의 규칙.
///
/// 계약(`docs/architecture/data-contracts.md`)을 따른다.
/// - 한 회차에 12장을 만들고 선택 화면에서는 앞 9장만 보여준다.
/// - 뒤 3장은 면회 중 보충용으로 남긴다.
/// - 처음 3장을 보여주고 아래로 밀면 3장씩 더 보여준다.
/// - 선택하지 않은 카드도 지우지 않는다.
abstract final class CardRules {
  /// 선택 화면에 보여주는 최대 장수.
  static const selectableCount = 9;

  /// 한 번에 더 보여주는 장수.
  static const pageSize = 3;
}

class CardsState {
  const CardsState({
    required this.cards,
    required this.visibleCount,
    required this.selectedIds,
    required this.expandedId,
  });

  /// 선택 화면 대상인 앞 9장.
  final List<ConversationCard> cards;

  /// 지금 보여주는 장수.
  final int visibleCount;

  final Set<String> selectedIds;

  /// 펼쳐서 꼬리 질문을 보여주는 카드. 한 번에 하나만 펼친다.
  final String? expandedId;

  List<ConversationCard> get visibleCards =>
      cards.take(visibleCount).toList();

  bool get hasMore => visibleCount < cards.length;

  int get remaining => cards.length - visibleCount;

  bool get canStart => selectedIds.isNotEmpty;

  CardsState copyWith({
    int? visibleCount,
    Set<String>? selectedIds,
    String? expandedId,
    bool clearExpanded = false,
  }) => CardsState(
    cards: cards,
    visibleCount: visibleCount ?? this.visibleCount,
    selectedIds: selectedIds ?? this.selectedIds,
    expandedId: clearExpanded ? null : (expandedId ?? this.expandedId),
  );
}

class CardsController extends AsyncNotifier<CardsState> {
  @override
  Future<CardsState> build() async {
    final all = await ref.watch(conversationCardsProvider.future);
    // 배열의 앞 9장이 선택 화면 대상이다.
    final selectable = all.take(CardRules.selectableCount).toList();

    return CardsState(
      cards: selectable,
      visibleCount: CardRules.pageSize,
      // 아무것도 고르지 않은 상태에서 시작한다. 목 데이터의 selectionStatus 는
      // 면회를 마친 회차의 기록이라 선택 화면의 시작 상태가 아니다.
      selectedIds: const {},
      expandedId: null,
    );
  }

  void toggleSelected(String cardId) {
    final current = state.value;
    if (current == null) return;

    final next = Set<String>.from(current.selectedIds);
    next.contains(cardId) ? next.remove(cardId) : next.add(cardId);
    state = AsyncData(current.copyWith(selectedIds: next));
  }

  /// 카드를 눌러 꼬리 질문을 펼치거나 접는다.
  void toggleExpanded(String cardId) {
    final current = state.value;
    if (current == null) return;

    if (current.expandedId == cardId) {
      state = AsyncData(current.copyWith(clearExpanded: true));
    } else {
      state = AsyncData(current.copyWith(expandedId: cardId));
    }
  }

  void showMore() {
    final current = state.value;
    if (current == null || !current.hasMore) return;

    final next = (current.visibleCount + CardRules.pageSize)
        .clamp(0, current.cards.length);
    state = AsyncData(current.copyWith(visibleCount: next));
  }
}

final cardsControllerProvider =
    AsyncNotifierProvider<CardsController, CardsState>(CardsController.new);
