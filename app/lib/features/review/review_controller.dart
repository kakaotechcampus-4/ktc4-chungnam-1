import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../visit/visit_controller.dart';

/// 보호자가 면회를 마치고 남기는 평가다.
///
/// 계약의 `CaregiverEvaluation` 을 그대로 따른다. 계약에 없는 항목을 묻지 않고,
/// 대화 품질 점수나 의료적 해석을 만들지 않는다.
class ReviewDraft {
  const ReviewDraft({
    this.satisfaction,
    this.reaction,
    this.cardReactions = const {},
    this.freeNote = '',
  });

  /// 1 이상 5 이하. 고르기 전에는 `null` 이다.
  final int? satisfaction;

  final CareRecipientReaction? reaction;

  /// 카드별 평가. 다루지 않은 카드는 담기지 않는다.
  final Map<String, CaregiverReaction> cardReactions;

  final String freeNote;

  /// 네 물음 중 앞의 둘은 반드시 답해야 한다. 카드 평가와 남길 말은 선택이다.
  bool get canSubmit => satisfaction != null && reaction != null;

  /// 보호자 감정은 따로 묻지 않고 대화 만족도에서 계산한다.
  VisitMood? get mood => satisfaction == null
      ? null
      : VisitMood.fromSatisfaction(satisfaction!);

  ReviewDraft copyWith({
    int? satisfaction,
    CareRecipientReaction? reaction,
    Map<String, CaregiverReaction>? cardReactions,
    String? freeNote,
  }) => ReviewDraft(
    satisfaction: satisfaction ?? this.satisfaction,
    reaction: reaction ?? this.reaction,
    cardReactions: cardReactions ?? this.cardReactions,
    freeNote: freeNote ?? this.freeNote,
  );
}

class ReviewController extends Notifier<ReviewDraft> {
  @override
  ReviewDraft build() => const ReviewDraft();

  void setSatisfaction(int value) =>
      state = state.copyWith(satisfaction: value);

  void setReaction(CareRecipientReaction value) =>
      state = state.copyWith(reaction: value);

  void setFreeNote(String value) => state = state.copyWith(freeNote: value);

  void setCardReaction(String cardId, CaregiverReaction reaction) {
    final next = Map<String, CaregiverReaction>.from(state.cardReactions)
      ..[cardId] = reaction;
    state = state.copyWith(cardReactions: next);
  }

  /// 화면에서 모은 값을 계약 객체로 바꾼다.
  ///
  /// 카드를 다루지 않았으면 `wasUsed` 가 `false` 이고 평가는 `neutral` 이다.
  CaregiverEvaluation? toEvaluation({
    required String reviewId,
    required String sessionId,
    required List<ConversationCard> cards,
  }) {
    if (!state.canSubmit) return null;

    return CaregiverEvaluation(
      reviewId: reviewId,
      sessionId: sessionId,
      conversationSatisfaction: state.satisfaction!,
      careRecipientReaction: state.reaction!,
      cardReviews: [
        for (final card in cards)
          CardReview(
            cardId: card.cardId,
            wasUsed: state.cardReactions.containsKey(card.cardId),
            caregiverReaction:
                state.cardReactions[card.cardId] ?? CaregiverReaction.neutral,
          ),
      ],
      freeNote: state.freeNote.trim().isEmpty ? null : state.freeNote.trim(),
    );
  }
}

final reviewControllerProvider = NotifierProvider<ReviewController, ReviewDraft>(
  ReviewController.new,
);

/// 소감 화면에서 평가할 카드. 면회에서 다룬 카드를 그대로 쓴다.
final reviewCardsProvider = FutureProvider<List<ConversationCard>>((ref) async {
  final visit = await ref.watch(visitControllerProvider.future);
  return visit.cards;
});
