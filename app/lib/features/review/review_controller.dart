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
    this.cardAnswers = const {},
    this.freeNote = '',
  });

  /// 1 이상 5 이하. 고르기 전에는 `null` 이다.
  final int? satisfaction;

  final CareRecipientReaction? reaction;

  /// 카드 한 장에 남긴 답이다.
  ///
  /// 세 경우를 구분한다. 계약의 `cardReviews` 와 그대로 맞물린다.
  /// - 표에 없다 — 답하지 않고 넘어갔다(미응답). `cardReviews` 에서도 뺀다.
  /// - 값이 `null` 이다 — 쓰지 않았다고 답했다(미사용). `wasUsed` 가 `false` 다.
  /// - 값이 있다 — 쓰고 평가했다. `wasUsed` 가 `true` 다.
  final Map<String, CaregiverReaction?> cardAnswers;

  final String freeNote;

  /// 네 물음 중 앞의 둘은 반드시 답해야 한다. 카드 평가와 남길 말은 선택이다.
  bool get canSubmit => satisfaction != null && reaction != null;

  /// 보호자 감정은 따로 묻지 않고 대화 만족도에서 계산한다.
  VisitMood? get mood =>
      satisfaction == null ? null : VisitMood.fromSatisfaction(satisfaction!);

  ReviewDraft copyWith({
    int? satisfaction,
    CareRecipientReaction? reaction,
    Map<String, CaregiverReaction?>? cardAnswers,
    String? freeNote,
  }) => ReviewDraft(
    satisfaction: satisfaction ?? this.satisfaction,
    reaction: reaction ?? this.reaction,
    cardAnswers: cardAnswers ?? this.cardAnswers,
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

  /// 카드를 쓰고 평가했다.
  void setCardReaction(String cardId, CaregiverReaction reaction) =>
      _answer(cardId, reaction);

  /// 카드를 쓰지 않았다고 답했다. 평가는 담지 않는다.
  void setCardNotUsed(String cardId) => _answer(cardId, null);

  void _answer(String cardId, CaregiverReaction? reaction) {
    final next = Map<String, CaregiverReaction?>.from(state.cardAnswers)
      ..[cardId] = reaction;
    state = state.copyWith(cardAnswers: next);
  }

  /// 화면에서 모은 값을 계약 객체로 바꾼다.
  ///
  /// 답하지 않은 카드는 `cardReviews` 에 담지 않는다. 담지 않는 것이 미응답이고,
  /// `wasUsed` 가 `false` 인 것이 미사용이다. 둘을 뭉개면 보호자가 하지 않은
  /// 판단을 대신 만들게 된다.
  ///
  /// **아직 화면에서 부르지 않는다.** 지금은 테스트가 계약 형태를 확인하는 데만
  /// 쓰고, 소감 화면의 제출 버튼은 처리 중 화면으로 이동만 한다. 저장 인터페이스가
  /// 정해지면 그 버튼에서 이 메서드를 부른다.
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
          if (state.cardAnswers.containsKey(card.cardId))
            CardReview(
              cardId: card.cardId,
              wasUsed: state.cardAnswers[card.cardId] != null,
              caregiverReaction: state.cardAnswers[card.cardId],
            ),
      ],
      freeNote: state.freeNote.trim().isEmpty ? null : state.freeNote.trim(),
    );
  }
}

final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewDraft>(ReviewController.new);

/// 소감 화면에서 평가할 카드. 면회에서 다룬 카드를 그대로 쓴다.
final reviewCardsProvider = FutureProvider<List<ConversationCard>>((ref) async {
  final visit = await ref.watch(visitControllerProvider.future);
  return visit.cards;
});
