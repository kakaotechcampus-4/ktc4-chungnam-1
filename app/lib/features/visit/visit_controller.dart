import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../cards/cards_controller.dart';

/// 면회 한 회차의 진행 상태다.
///
/// 녹음 자체는 만들지 않는다. 녹음 라이브러리와 음성 형식은 AI 영역이
/// 소유한다(`app/CLAUDE.md`). 여기서는 화면이 필요로 하는 상태와 시간만 다룬다.
class VisitState {
  const VisitState({
    required this.cards,
    required this.currentIndex,
    required this.followUpIndex,
    required this.started,
    required this.recording,
    required this.elapsed,
    required this.careRecipientConfirmed,
  });

  /// 면회에서 다룰 카드. 선택 화면에서 고른 것에 보충한 카드가 뒤에 붙는다.
  final List<ConversationCard> cards;

  final int currentIndex;

  /// 지금 보여주는 꼬리 질문의 자리.
  final int followUpIndex;

  /// 한 번이라도 녹음을 시작했는지. 잠시 멈춤과 시작 전을 가른다.
  final bool started;

  final bool recording;
  final Duration elapsed;

  /// 피보호자에게 안내하고 동의를 확인했는지.
  /// 계약의 `VisitSession.consent.careRecipientConfirmation` 에 해당한다.
  final bool careRecipientConfirmed;

  ConversationCard? get currentCard =>
      currentIndex < cards.length ? cards[currentIndex] : null;

  String? get currentFollowUp {
    final card = currentCard;
    if (card == null || card.followUpQuestions.isEmpty) return null;
    return card.followUpQuestions[followUpIndex %
        card.followUpQuestions.length];
  }

  int get followUpCount => currentCard?.followUpQuestions.length ?? 0;

  bool get isLastCard => currentIndex >= cards.length - 1;

  /// 진행률. 화면의 `1/3`, `33%` 표시에 쓴다.
  double get progress => cards.isEmpty ? 0 : (currentIndex + 1) / cards.length;

  /// `00:05:38` 형태로 보여준다.
  String get elapsedLabel {
    final h = elapsed.inHours.toString().padLeft(2, '0');
    final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  VisitState copyWith({
    List<ConversationCard>? cards,
    int? currentIndex,
    int? followUpIndex,
    bool? started,
    bool? recording,
    Duration? elapsed,
    bool? careRecipientConfirmed,
  }) => VisitState(
    cards: cards ?? this.cards,
    currentIndex: currentIndex ?? this.currentIndex,
    followUpIndex: followUpIndex ?? this.followUpIndex,
    started: started ?? this.started,
    recording: recording ?? this.recording,
    elapsed: elapsed ?? this.elapsed,
    careRecipientConfirmed:
        careRecipientConfirmed ?? this.careRecipientConfirmed,
  );
}

class VisitController extends AsyncNotifier<VisitState> {
  Timer? _ticker;

  @override
  Future<VisitState> build() async {
    final all = await ref.watch(conversationCardsProvider.future);
    final selection = await ref.watch(cardsControllerProvider.future);

    // 선택 화면에서 고른 카드를 배열 순서 그대로 가져온다.
    final chosen = all
        .where((card) => selection.selectedIds.contains(card.cardId))
        .toList();

    ref.onDispose(() => _ticker?.cancel());

    return VisitState(
      cards: chosen,
      currentIndex: 0,
      followUpIndex: 0,
      started: false,
      recording: false,
      elapsed: Duration.zero,
      careRecipientConfirmed: false,
    );
  }

  void confirmCareRecipient({required bool confirmed}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(careRecipientConfirmed: confirmed));
  }

  void startRecording() {
    final current = state.value;
    if (current == null || current.recording) return;

    state = AsyncData(current.copyWith(started: true, recording: true));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = state.value;
      if (now == null || !now.recording) return;
      state = AsyncData(
        now.copyWith(elapsed: now.elapsed + const Duration(seconds: 1)),
      );
    });
  }

  void pauseRecording() {
    final current = state.value;
    if (current == null) return;
    _ticker?.cancel();
    _ticker = null;
    state = AsyncData(current.copyWith(recording: false));
  }

  void stopRecording() {
    _ticker?.cancel();
    _ticker = null;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(recording: false));
  }

  /// 다음 카드로 넘어간다. 마지막 카드면 아무것도 하지 않는다.
  void nextCard() {
    final current = state.value;
    if (current == null || current.isLastCard) return;
    state = AsyncData(
      current.copyWith(
        currentIndex: current.currentIndex + 1,
        followUpIndex: 0,
      ),
    );
  }

  /// 꼬리 질문을 다음 것으로 넘긴다. 마지막이면 처음으로 돌아간다.
  void nextFollowUp() {
    final current = state.value;
    if (current == null || current.followUpCount == 0) return;
    state = AsyncData(
      current.copyWith(followUpIndex: current.followUpIndex + 1),
    );
  }

  /// 면회 중 보충 카드를 더한다.
  ///
  /// 계약대로 고른 카드만 회차에 추가한다.
  void addCards(Iterable<ConversationCard> cards) {
    final current = state.value;
    if (current == null) return;

    final existing = current.cards.map((c) => c.cardId).toSet();
    final added = cards.where((c) => !existing.contains(c.cardId));
    state = AsyncData(current.copyWith(cards: [...current.cards, ...added]));
  }
}

final visitControllerProvider =
    AsyncNotifierProvider<VisitController, VisitState>(VisitController.new);

/// 면회 중 보충용으로 남겨 둔 카드다.
///
/// 계약상 한 회차에 12장을 만들고 앞 9장은 선택 화면에서 쓴다. 뒤 3장이 여기에
/// 해당한다.
final supplementCardsProvider = FutureProvider<List<ConversationCard>>((
  ref,
) async {
  final all = await ref.watch(conversationCardsProvider.future);
  return all.skip(CardRules.selectableCount).toList();
});
