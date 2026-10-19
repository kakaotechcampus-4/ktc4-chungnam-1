import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/visit_api.dart';
import '../cards/cards_controller.dart';
import 'pending_uploads.dart';
import 'visit_camera.dart';
import 'visit_photos.dart';
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

  /// 서버에 회차를 만들지 못했다(API 5-1). 녹음을 시작하지 않는다.
  sessionFailed,
}

/// 면회 전에 찍은 사진을 회차에 올린 상태다(API 5-2).
///
/// 사진은 녹음을 막지 않는다. 회차를 만든 뒤 녹음과 따로 올린다.
enum VisitPhotoUpload {
  /// 찍은 사진이 없거나 아직 회차가 없다.
  none,
  uploading,
  uploaded,

  /// 올리지 못했다. 다시 올리면 될 수 있다.
  failed,

  /// 올리지 못했고 다시 올려도 받지 않는다. 형식과 크기 거절, 평가가 끝난
  /// 회차 등이다. 리포트에는 사진 없이 담긴다.
  rejected,

  /// 찍은 사진 파일을 찾거나 읽지 못했다. 다시 올려도 같아 리포트에는 사진
  /// 없이 담긴다. 녹음은 그대로 이어진다.
  missing,
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
    this.sessionId,
    this.recordingPath,
    this.problem,
    this.participantCount,
    this.photoUpload = VisitPhotoUpload.none,
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

  /// 서버가 만든 회차(API 5-1). 녹음을 처음 시작할 때 생긴다.
  ///
  /// 앱이 켜져 있는 동안만 들고 있다. 소감 저장과 녹음 제출이 이 값을 쓴다.
  final String? sessionId;

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

  final VisitPhotoUpload photoUpload;

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
    String? sessionId,
    String? recordingPath,
    VisitRecordingProblem? problem,
    int? participantCount,
    VisitPhotoUpload? photoUpload,

    /// [problem] 을 지운다. `null` 은 "그대로 두기" 라서 따로 둔다.
    bool clearProblem = false,
  }) => VisitState(
    cards: cards ?? this.cards,
    currentIndex: currentIndex ?? this.currentIndex,
    followUpIndex: followUpIndex ?? this.followUpIndex,
    started: started ?? this.started,
    recording: recording ?? this.recording,
    elapsed: elapsed ?? this.elapsed,
    sessionId: sessionId ?? this.sessionId,
    recordingPath: recordingPath ?? this.recordingPath,
    problem: clearProblem ? null : (problem ?? this.problem),
    participantCount: participantCount ?? this.participantCount,
    photoUpload: photoUpload ?? this.photoUpload,
  );
}

class VisitController extends AsyncNotifier<VisitState> {
  Timer? _ticker;

  /// 녹음 파일이 열려 있는지. 잠시 멈춤 중에도 파일은 열려 있다.
  ///
  /// 닫아야 할 파일이 있는지를 이 값으로 가른다. [VisitState.started] 로 가르면
  /// 이미 닫은 뒤에 한 번 더 닫으려 들어 실패로 잘못 표시된다.
  bool _fileOpen = false;

  /// 회차를 만드는 중인지. 두 번 눌러 회차가 둘 생기지 않게 막는다.
  bool _creatingSession = false;

  /// 사진 올리기를 차례로 잇는다([_uploadPhoto]).
  Future<void> _photoQueue = Future.value();

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
    _creatingSession = false;
    _photoQueue = Future.value();
    ref.onDispose(() => _ticker?.cancel());

    // 회차를 만든 뒤 사진을 다시 찍었으면 새 사진을 올린다. 5-2 는 다시 올리면
    // 앞 사진을 바꿔 끼운다.
    ref.listen(visitPhotoProvider, (previous, next) {
      if (next == null || next == previous) return;
      if (state.value?.sessionId == null) return;
      unawaited(_uploadPhoto(retryOnce: true));
    });

    return VisitState(
      cards: chosen,
      currentIndex: 0,
      followUpIndex: 0,
      started: false,
      recording: false,
      elapsed: Duration.zero,
    );
  }

  /// 녹음을 시작하거나, 잠시 멈춘 녹음을 이어 간다.
  ///
  /// 처음이면 마이크 권한 → 회차 만들기(API 5-1) → 새 파일 열기 순서다.
  /// 권한을 먼저 보는 것은, 회차를 만든 뒤 권한을 거부하면 녹음 없는 회차가
  /// 남고 카드 묶음이 면회 중으로 묶이기 때문이다.
  ///
  /// 권한이 없거나 회차를 만들지 못했거나 장치가 열리지 않으면 상태만 바꾸고
  /// 조용히 돌아간다. 화면이 [VisitState.problem] 을 보고 안내한다. 회차를
  /// 만든 뒤 장치가 열리지 않았으면 회차는 그대로 두고, 다시 누를 때 같은
  /// 회차로 녹음만 다시 시작한다.
  Future<void> startRecording() async {
    final current = state.value;
    if (current == null || current.recording || _creatingSession) return;

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

    if (current.sessionId == null && !await _createSession()) return;

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

  /// 고른 카드로 회차를 만든다. 성공하면 `true` 다.
  ///
  /// 5-1 은 선택 화면의 카드(`position` 1~9)만 받는다. 녹음 전에 보충 카드를
  /// 더했다면 회차를 만든 뒤 5-3 으로 따로 더한다.
  Future<bool> _createSession() async {
    _creatingSession = true;
    try {
      final cards = state.value?.cards ?? const <ConversationCard>[];
      final set = await ref.read(currentCardSetProvider.future);
      final api = ref.read(visitApiProvider);
      bool chosen(ConversationCard c) =>
          c.position <= CardRules.selectableCount;

      final session = await api.createSession(
        setId: set.setId,
        selectedCardIds: [
          for (final c in cards)
            if (chosen(c)) c.cardId,
        ],
      );
      final supplements = [
        for (final c in cards)
          if (!chosen(c)) c.cardId,
      ];
      if (supplements.isNotEmpty) {
        await api.addCards(session.sessionId, supplements);
      }

      _update((now) => now.copyWith(sessionId: session.sessionId));
      // 녹음은 사진을 기다리지 않는다.
      unawaited(_uploadPhoto(retryOnce: true));
      return true;
    } on ApiFailure {
      _fail(VisitRecordingProblem.sessionFailed);
      return false;
    } finally {
      _creatingSession = false;
    }
  }

  /// 올리지 못한 면회 사진을 다시 올린다. 녹음 화면의 버튼이 부른다.
  ///
  /// 소감을 저장하면(6-1) 서버가 받지 않으므로 녹음 화면에서만 부른다.
  Future<void> retryPhotoUpload() async {
    if (state.value?.photoUpload != VisitPhotoUpload.failed) return;
    await _uploadPhoto(retryOnce: false);
  }

  /// 찍어 둔 사진을 회차에 올린다(API 5-2). 사진이 없으면 아무것도 하지 않는다.
  ///
  /// 올리기는 차례로 한다. 앞 사진을 올리는 중에 다시 찍었으면 앞 요청이 끝난
  /// 뒤 새 사진을 올려, 늦게 닿은 앞 사진이 서버에서 새 사진을 덮지 않게 한다.
  Future<void> _uploadPhoto({required bool retryOnce}) =>
      _photoQueue = _photoQueue.then((_) => _sendPhoto(retryOnce: retryOnce));

  /// 지금 사진을 올린다. 올려도 기기의 사진 파일은 남기고 올린 회차만 적는다
  /// ([VisitPhotos]).
  ///
  /// 올리는 사이 사진을 다시 찍었으면 결과를 화면 상태에 쓰지 않는다. 앞 사진의
  /// 결과이고, 새 사진은 [_photoQueue] 에서 뒤이어 올린다.
  Future<void> _sendPhoto({required bool retryOnce}) async {
    if (!ref.mounted) return;
    final sessionId = state.value?.sessionId;
    final photoPath = ref.read(visitPhotoProvider);
    if (sessionId == null || photoPath == null) return;

    final photos = ref.read(visitPhotosProvider);
    final photo = ref.read(visitPhotoProvider.notifier)..sending(photoPath);
    _update((now) => now.copyWith(photoUpload: VisitPhotoUpload.uploading));

    final result = await _sendPhotoFile(
      sessionId,
      photoPath,
      retryOnce: retryOnce,
    );
    if (result == VisitPhotoUpload.uploaded) {
      try {
        await photos.markUploaded(photoPath, sessionId);
      } on FileSystemException {
        // 기록을 못 적어도 사진은 올라갔다. 탈퇴 때는 기록 없는 파일로 지운다.
      }
    }
    await photo.sent(photoPath);

    if (!ref.mounted) return;
    if (ref.read(visitPhotoProvider) != photoPath) return;
    _update((now) => now.copyWith(photoUpload: result));
  }

  /// [retryOnce] 면 다시 시도해도 되는 실패(연결 실패, 서버가 `retryable`
  /// 로 알린 실패)에 한 번만 더 올린다.
  Future<VisitPhotoUpload> _sendPhotoFile(
    String sessionId,
    String photoPath, {
    required bool retryOnce,
  }) async {
    final api = ref.read(visitApiProvider);
    var attemptsLeft = retryOnce ? 2 : 1;
    while (true) {
      attemptsLeft--;
      try {
        await api.uploadPhoto(sessionId, photoPath: photoPath);
        return VisitPhotoUpload.uploaded;
      } on ApiFailure catch (failure) {
        final retryable = _isRetryable(failure);
        if (retryable && attemptsLeft > 0) continue;
        return retryable ? VisitPhotoUpload.failed : VisitPhotoUpload.rejected;
      } on FileSystemException {
        // 사진 파일이 없거나 읽지 못했다. 다시 올려도 같다.
        return VisitPhotoUpload.missing;
      }
    }
  }

  static bool _isRetryable(ApiFailure failure) => switch (failure) {
    ApiNetworkFailure() => true,
    ApiServerFailure(:final retryable) => retryable,
    _ => false,
  };

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
      await _rememberUpload();
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
    await _rememberUpload();
  }

  /// 보낼 녹음을 회차 ID 로 기기에 적어 둔다. 앱을 다시 켜도 다시 보낼 수
  /// 있게 하려는 것이다. 회차, 파일, 참여자 수가 모두 있을 때만 적는다.
  ///
  /// 적지 못해도 면회는 막지 않는다. 앱이 켜져 있는 동안은 이 상태가 파일과
  /// 참여자 수를 들고 있다.
  Future<void> _rememberUpload() async {
    final now = state.value;
    final sessionId = now?.sessionId;
    final path = now?.recordingPath;
    final count = now?.participantCount;
    if (sessionId == null || path == null || count == null) return;

    try {
      await ref
          .read(pendingUploadsProvider)
          .save(
            PendingUpload(
              sessionId: sessionId,
              audioPath: path,
              participantCount: count,
            ),
          );
    } on Exception {
      // 기록이 없으면 앱을 다시 켠 뒤 다시 보내기만 못 한다.
    }
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

  /// 면회 중 보충 카드를 더한다. 더했으면 `true` 다.
  ///
  /// 계약대로 고른 카드만 회차에 추가한다. 회차가 있으면 서버(API 5-3)에 먼저
  /// 알리고, 받아들여진 뒤에 화면에 더한다. 서버에 없는 카드를 면회 기록처럼
  /// 보여주지 않으려는 것이다. 회차가 아직 없으면 회차를 만들 때 함께 보낸다.
  Future<bool> addCards(Iterable<ConversationCard> cards) async {
    final current = state.value;
    if (current == null) return false;

    final existing = current.cards.map((c) => c.cardId).toSet();
    final added = cards.where((c) => !existing.contains(c.cardId)).toList();
    if (added.isEmpty) return true;

    final sessionId = current.sessionId;
    if (sessionId != null) {
      try {
        await ref.read(visitApiProvider).addCards(sessionId, [
          for (final c in added) c.cardId,
        ]);
      } on ApiFailure {
        return false;
      }
    }

    _update((now) {
      final have = now.cards.map((c) => c.cardId).toSet();
      return now.copyWith(
        cards: [...now.cards, ...added.where((c) => !have.contains(c.cardId))],
      );
    });
    return true;
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
