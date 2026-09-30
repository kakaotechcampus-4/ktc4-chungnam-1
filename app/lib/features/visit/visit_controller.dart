import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../cards/cards_controller.dart';
import 'visit_recorder.dart';

/// 녹음이 뜻대로 되지 않은 경우다. 화면은 이 값으로 안내 문구를 고른다.
///
/// `app/CLAUDE.md` 대로 권한 거부와 실패를 성공 화면과 함께 다룬다.
enum VisitRecordingProblem {
  /// 마이크 권한을 받지 못했다.
  permissionDenied,

  /// 권한은 있는데 녹음을 시작하지 못했다.
  startFailed,

  /// 녹음은 했는데 파일을 마무리하지 못했다.
  saveFailed,
}

/// 면회 한 회차의 진행 상태다.
///
/// 녹음 장치는 [VisitRecorder] 가 맡는다. 여기서는 화면이 필요로 하는 상태와
/// 시간, 그리고 만들어진 녹음 파일의 자리만 들고 있다. 음성 형식과 저장 위치는
/// [VisitRecorder] 쪽에 있다.
class VisitState {
  const VisitState({
    required this.cards,
    required this.currentIndex,
    required this.followUpIndex,
    required this.started,
    required this.recording,
    required this.elapsed,
    required this.careRecipientConfirmed,
    this.recordingPath,
    this.problem,
    this.participantCount,
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

  /// 이 회차의 녹음이 쌓이는 기기 안의 파일이다.
  ///
  /// 녹음을 시작한 순간부터 값이 있다. 서버 업로드는 아직 없다.
  final String? recordingPath;

  /// 녹음이 실패했으면 그 이유다. 성공하면 `null` 이다.
  final VisitRecordingProblem? problem;

  /// 대화에 함께한 사람 수. 계약의 `VisitSession.participantCount` 에 해당한다.
  ///
  /// 녹음을 끝낼 때 보호자가 종료 모달에서 확인해 준 값이다. 앱이 목소리를
  /// 세어 짐작하지 않는다. 확인 전에는 `null` 이다.
  final int? participantCount;

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
    String? recordingPath,
    VisitRecordingProblem? problem,
    int? participantCount,

    /// [problem] 을 지운다. `null` 은 "그대로 두기" 라서 따로 둔다.
    bool clearProblem = false,
  }) => VisitState(
    cards: cards ?? this.cards,
    currentIndex: currentIndex ?? this.currentIndex,
    followUpIndex: followUpIndex ?? this.followUpIndex,
    started: started ?? this.started,
    recording: recording ?? this.recording,
    elapsed: elapsed ?? this.elapsed,
    careRecipientConfirmed:
        careRecipientConfirmed ?? this.careRecipientConfirmed,
    recordingPath: recordingPath ?? this.recordingPath,
    problem: clearProblem ? null : (problem ?? this.problem),
    participantCount: participantCount ?? this.participantCount,
  );
}

class VisitController extends AsyncNotifier<VisitState> {
  Timer? _ticker;

  /// 녹음 파일이 열려 있는지. 잠시 멈춤 중에도 파일은 열려 있다.
  ///
  /// 닫아야 할 파일이 있는지를 이 값으로 가른다. [VisitState.started] 로 가르면
  /// 이미 닫은 뒤에 한 번 더 닫으려 들어 실패로 잘못 표시된다.
  bool _fileOpen = false;

  VisitRecorder get _recorder => ref.read(visitRecorderProvider);

  @override
  Future<VisitState> build() async {
    final all = await ref.watch(conversationCardsProvider.future);
    final selection = await ref.watch(cardsControllerProvider.future);

    // 선택 화면에서 고른 카드를 배열 순서 그대로 가져온다.
    final chosen = all
        .where((card) => selection.selectedIds.contains(card.cardId))
        .toList();

    _fileOpen = false;
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

  /// 녹음을 시작하거나, 잠시 멈춘 녹음을 이어 간다.
  ///
  /// 처음이면 마이크 권한을 먼저 확인하고 새 파일을 연다. 권한이 없거나 장치가
  /// 열리지 않으면 상태만 바꾸고 조용히 돌아간다. 화면이 [VisitState.problem]
  /// 을 보고 안내한다.
  Future<void> startRecording() async {
    final current = state.value;
    if (current == null || current.recording) return;

    if (current.started) {
      return _resumeRecording();
    }

    final bool allowed;
    try {
      allowed = await _recorder.hasPermission();
    } on Exception {
      _fail(VisitRecordingProblem.permissionDenied);
      return;
    }
    if (!allowed) {
      _fail(VisitRecordingProblem.permissionDenied);
      return;
    }

    final VisitRecording recording;
    try {
      recording = await _recorder.start();
    } on Exception {
      _fail(VisitRecordingProblem.startFailed);
      return;
    }

    _fileOpen = true;
    _update(
      (now) => now.copyWith(
        started: true,
        recording: true,
        recordingPath: recording.path,
        clearProblem: true,
      ),
    );
    _startTicker();
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorder.resume();
    } on Exception {
      _fail(VisitRecordingProblem.startFailed);
      return;
    }

    _update((now) => now.copyWith(recording: true, clearProblem: true));
    _startTicker();
  }

  /// 녹음과 시간을 함께 멈춘다. 파일은 닫지 않고 이어서 쓴다.
  Future<void> pauseRecording() async {
    _stopTicker();
    final current = state.value;
    if (current == null) return;

    state = AsyncData(current.copyWith(recording: false));
    if (!_fileOpen) return;

    try {
      await _recorder.pause();
    } on Exception {
      // 이미 멈춰 있는 경우다. 화면은 멈춘 상태 그대로 두면 된다.
    }
  }

  /// 녹음을 끝내고 파일을 닫는다.
  ///
  /// 끝내기 버튼뿐 아니라 녹음 화면을 떠날 때도 부른다. 닫지 않으면 WAV 헤더가
  /// 쓰이지 않아 소리는 들어 있는데 열 수 없는 파일이 남는다. 닫을 파일이
  /// 없으면 장치를 건드리지 않는다.
  ///
  /// [participantCount] 는 종료 모달에서 보호자가 확인해 준 사람 수다. 모달을
  /// 거치지 않고 화면을 떠난 경우에는 넘기지 않는다. 확인받지 않은 수를 대신
  /// 지어내지 않는다.
  Future<void> stopRecording({int? participantCount}) async {
    _stopTicker();
    final current = state.value;
    if (current == null) return;

    if (!_fileOpen) {
      state = AsyncData(
        current.copyWith(
          recording: false,
          participantCount: participantCount,
        ),
      );
      return;
    }
    _fileOpen = false;

    VisitRecording? saved;
    var problem = current.problem;
    try {
      saved = await _recorder.stop();
      if (saved == null) problem = VisitRecordingProblem.saveFailed;
    } on Exception {
      problem = VisitRecordingProblem.saveFailed;
    }

    _update(
      (now) => now.copyWith(
        recording: false,
        recordingPath: saved?.path,
        participantCount: participantCount,
        problem: problem,
        clearProblem: problem == null,
      ),
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = state.value;
      if (now == null || !now.recording) return;
      state = AsyncData(
        now.copyWith(elapsed: now.elapsed + const Duration(seconds: 1)),
      );
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _fail(VisitRecordingProblem problem) {
    _update((now) => now.copyWith(recording: false, problem: problem));
  }

  /// 기다리는 사이에 상태가 바뀌었을 수 있으므로 그때의 값에 얹는다.
  void _update(VisitState Function(VisitState now) change) {
    final now = state.value;
    if (now == null) return;
    state = AsyncData(change(now));
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
