import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../visit/pending_uploads.dart';
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

  /// 화면에서 모은 값을 API 6-1 요청으로 바꾼다. 필수 답이 없으면 `null` 이다.
  ///
  /// 답하지 않은 카드는 `cardReviews` 에 담지 않는다. 담지 않는 것이 미응답이고,
  /// `wasUsed` 가 `false` 인 것이 미사용이다. 둘을 뭉개면 보호자가 하지 않은
  /// 판단을 대신 만들게 된다.
  EvaluationSubmission? toSubmission({required List<ConversationCard> cards}) {
    if (!state.canSubmit) return null;

    return EvaluationSubmission(
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

/// 소감을 남길 회차와 그 회차에서 다룬 카드, 보낼 녹음.
class ReviewTarget {
  const ReviewTarget({
    required this.sessionId,
    required this.cards,
    this.audioPath,
    this.participantCount,
  });

  /// 서버의 회차. 녹음을 시작하지 못해 회차가 없으면 `null` 이다.
  final String? sessionId;

  /// 평가할 카드. 면회에서 다룬 카드다.
  final List<ConversationCard> cards;

  /// 보낼 녹음 파일. 없으면 녹음을 보내지 못한다.
  final String? audioPath;

  /// 녹음을 끝낼 때 보호자가 확인한 1~8. 없으면 녹음을 보내지 못한다.
  final int? participantCount;
}

/// 소감 화면이 볼 회차.
///
/// 인자가 `null` 이면 지금 막 마친 면회다. 앱이 켜져 있는 동안 면회 상태가
/// 들고 있는 값을 쓴다.
///
/// 인자가 회차 ID 면 앱을 다시 켠 뒤 홈 배너의 `평가 이어서 하기` 로 들어온
/// 경우다(`/visit/review?session=<회차 ID>`). 카드는 지금 쓰는 묶음(API 4-3)에서
/// 이 회차가 고른 카드를, 녹음은 기기 기록([PendingUploads])에서 찾는다. 묶음이
/// 이 회차의 것이 아니면 이어서 할 수 없으므로 `null` 이다.
final reviewTargetProvider = FutureProvider.family<ReviewTarget?, String?>((
  ref,
  sessionId,
) async {
  if (sessionId == null) {
    final visit = await ref.watch(visitControllerProvider.future);
    return ReviewTarget(
      sessionId: visit.sessionId,
      cards: visit.cards,
      audioPath: visit.recordingPath,
      participantCount: visit.participantCount,
    );
  }

  final CardSet set;
  try {
    set = await ref.watch(currentCardSetProvider.future);
  } on ApiServerFailure catch (failure) {
    // 쓸 묶음이 없다. 평가를 마쳤거나 다른 회차로 넘어간 경우다.
    if (failure.statusCode == 404) return null;
    rethrow;
  }
  if (set.usedBySessionId != sessionId) return null;

  // 기록을 읽지 못해도 소감은 받는다. 녹음은 보내지 못한다고 알린다.
  PendingUpload? pending;
  try {
    pending = await ref.read(pendingUploadsProvider).find(sessionId);
  } on Exception {
    pending = null;
  }
  return ReviewTarget(
    sessionId: sessionId,
    cards: [
      for (final card in set.cards)
        if (card.selected) card,
    ],
    audioPath: pending?.audioPath,
    participantCount: pending?.participantCount,
  );
}, retry: (_, _) => null);
