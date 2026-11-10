import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/visit_api.dart';
import '../auth/session_refresher.dart';
import '../cards/card_generation_controller.dart';
import '../cards/cards_controller.dart';
import 'pending_uploads.dart';
import 'recording_service.dart';
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

  /// 보호자가 멈추지 않았는데 장치가 녹음을 잠시 멈췄다. 다른 앱이 소리를 내거나
  /// 전화가 와서 오디오 포커스를 잃은 경우다(`record` 의 `audioInterruption: pause`).
  /// 저절로 잇지 않으므로 `이어서 녹음` 을 눌러야 한다. 파일은 열려 있다.
  interrupted,

  /// 보호자가 끝내지 않았는데 장치가 녹음을 끝냈다. 같은 파일에 이어 쓸 수 없어
  /// `만남 끝내기` 로 지금까지의 녹음을 저장하게 한다.
  recorderStopped,

  /// 서버에 회차를 만들지 못했다(API 5-1). 녹음을 시작하지 않는다.
  sessionFailed,

  /// 카드를 받은 뒤 프로필이나 일대기를 고쳐 5-1 이 그 묶음을 받지 않았다
  /// (`CARD_SET_NEEDS_REFRESH`). 다시 눌러도 같으므로 카드를 다시 준비해야 한다.
  cardsOutdated,
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
    this.addedCardIds = const {},
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

  /// 면회 중에 보충해 더한 카드. 카드 번호 칩을 다른 색으로 그리는 데 쓴다.
  final Set<String> addedCardIds;

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

  bool get isFirstCard => currentIndex <= 0;

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
    Set<String>? addedCardIds,

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
    addedCardIds: addedCardIds ?? this.addedCardIds,
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

  /// 녹음 파일을 연 뒤 세션을 붙잡아 두었는지([sessionHoldProvider]). 파일을
  /// 닫고 기록을 마치거나 이 provider 가 정리되면 놓는다.
  bool _holdingSession = false;

  /// 사진 올리기를 차례로 잇는다([_uploadPhoto]).
  Future<void> _photoQueue = Future.value();

  /// 녹음 파일이 열려 있는 동안 장치의 상태 알림을 듣는다([_onDeviceState]).
  ///
  /// 보호자가 누르지 않았는데 장치가 멈추면 알아채려는 것이다. 앱이 뒤로 가거나
  /// 화면이 꺼지는 것만으로는 멈추지 않는다(2026-11-10 PM 결정). 녹음은 마이크
  /// 포그라운드 서비스로 이어지고, 앱 생명주기에 따라 멈추는 처리는 두지 않는다.
  StreamSubscription<VisitRecorderState>? _deviceState;

  void _stopListeningDevice() {
    unawaited(_deviceState?.cancel());
    _deviceState = null;
  }

  VisitRecorder get _recorder => ref.read(visitRecorderProvider);

  /// 녹음 파일이 열려 있는 동안 띄우는 포그라운드 서비스와 알림이다.
  RecordingService get _service => ref.read(recordingServiceProvider);

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
    _holdingSession = false;
    final sessionHold = ref.read(sessionHoldProvider.notifier);
    final recordingService = ref.read(recordingServiceProvider);
    ref.onDispose(() {
      _ticker?.cancel();
      _stopListeningDevice();
      // 녹음을 마무리하지 못한 채 정리됐다. 세션을 계속 붙잡아 두지 않는다.
      // 정리하는 중에는 다른 provider 를 바꾸지 않도록 미룬다.
      if (_holdingSession) Future.microtask(sessionHold.release);
      // 면회가 끝났다. 녹음 알림을 남기지 않는다. 파일을 닫는 중이면 닫은 뒤
      // [_stop] 이 내린다.
      if (_fileOpen) recordingService.hide();
    });

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
    // 장치가 파일을 닫았다. 이어서 녹음하면 소리 없이 시간만 흐르므로 받지 않는다.
    // 화면은 `만남 끝내기` 만 보인다.
    if (current.problem == VisitRecordingProblem.recorderStopped) return;

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
    _stopListeningDevice();
    _deviceState = _recorder.stateChanges.listen(
      _onDeviceState,
      // 약속은 오류 대신 멈춤을 보내는 것이지만, 오류가 와도 멈춘 것으로 본다.
      onError: (Object _) => _onDeviceState(VisitRecorderState.stopped),
    );
    // 녹음하는 동안 세션을 잃어도 로그인 화면으로 보내지 않는다. 화면이 바뀌면
    // 녹음 화면이 닫히며 녹음이 멈춘다. 파일을 닫으면 놓는다([_stop]).
    _holdingSession = true;
    ref.read(sessionHoldProvider.notifier).hold();
    _update(
      (now) => now.copyWith(
        started: true,
        recording: true,
        recordingPath: recording.path,
        clearProblem: true,
      ),
    );
    _startTicker();
    // 화면을 끄거나 다른 앱으로 옮겨도 녹음이 이어지게 마이크 포그라운드 서비스를
    // 알림과 함께 띄운다. 안드로이드는 앱이 앞에 있을 때만 띄우게 하므로 녹음
    // 버튼을 누른 지금 띄운다. 파일을 닫으면 내린다([_stop]).
    _service.show(recording: true);
    // 녹음 중에 앱이 죽어도 다시 켰을 때 이 회차의 파일을 찾도록 바로 적어 둔다.
    // 끝내지 못한 파일의 머리글은 보내기 전에 고친다(repairUnfinishedRecording).
    unawaited(_rememberUpload());
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
      _announceVisit(session);
      // 녹음은 사진을 기다리지 않는다.
      unawaited(_uploadPhoto(retryOnce: true));
      return true;
    } on ApiFailure catch (failure) {
      if (failure case ApiServerFailure(errorCode: 'CARD_SET_NEEDS_REFRESH')) {
        _fail(VisitRecordingProblem.cardsOutdated);
        // 뒤에 있는 카드 화면이 다시 확인해 옛 카드를 감추고 홈으로 돌려보내게
        // 한다. 받아 둔 묶음은 버리지 않는다. 이 회차가 그 묶음을 보고 있다.
        // 지우면 시작하지 않은 상태로 남아 카드 화면이 기다리기만 하므로
        // 다시 확인하게 한다.
        final profileId = ref.read(serverProfileIdProvider).value;
        if (profileId != null) {
          unawaited(
            ref.read(cardGenerationProvider(profileId).notifier).start(),
          );
        }
      } else {
        _fail(VisitRecordingProblem.sessionFailed);
      }
      return false;
    } finally {
      _creatingSession = false;
    }
  }

  /// 회차가 생겨 서버가 이 카드 묶음을 면회 중(`inVisit`)으로, 이 회차를 평가
  /// 전으로 본다. 카드 화면과 홈이 서버에 다시 묻지 않아도 그 상태를 보게 한다.
  ///
  /// 그러지 않으면 녹음 화면에서 뒤로 나왔을 때 카드 화면은 고르기와
  /// `대화 시작하기` 를 그대로 보여주고(다시 누르면 `CARD_SET_ALREADY_USED`),
  /// 홈은 앱을 다시 켜기 전까지 `평가 이어서 하기` 를 띄우지 않는다(#234).
  void _announceVisit(VisitSession session) {
    final profileId = ref.read(serverProfileIdProvider).value;
    if (profileId != null) {
      ref.read(cardGenerationProvider(profileId).notifier).visitStarted();
    }
    ref
        .read(reportNoticeProvider.notifier)
        .visitStarted(
          sessionId: session.sessionId,
          startedAt: session.startedAt,
        );
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

  /// 지금 사진을 올린다. 올리면 갤러리에 원본이 있는 사본은 지우고, 없으면
  /// 남긴 채 올린 회차만 적는다([VisitPhotos]).
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
      // 녹음이 멈춘 채다. 알림도 멈췄다고 크게 알린다.
      if (_fileOpen) _service.interrupted();
      return;
    }

    _update((now) => now.copyWith(recording: true, clearProblem: true));
    _startTicker();
    // 열린 파일에 이어 쓸 때만 알림을 녹음 중으로 되돌린다.
    if (_fileOpen) _service.show(recording: true);
  }

  /// 녹음과 시간을 함께 멈춘다. 파일은 닫지 않고 이어서 쓴다.
  Future<void> pauseRecording() async {
    _stopTicker();
    final current = state.value;
    if (current == null) return;

    state = AsyncData(current.copyWith(recording: false));
    if (!_fileOpen) return;

    // 파일은 열려 있으므로 서비스는 그대로 두고 알림 문구만 바꾼다.
    _service.show(recording: false);
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
  ///
  /// 녹음 화면의 `dispose` 에서는 [stopRecordingOnLeave] 를 쓴다.
  Future<void> stopRecording({int? participantCount}) =>
      _stop(participantCount: participantCount, deferStateChange: false);

  /// 녹음 화면이 사라질 때(`State.dispose`) 부른다.
  ///
  /// 열린 파일은 [stopRecording] 처럼 이 호출 안에서 바로 닫기 시작한다. 닫을
  /// 파일이 없을 때의 상태 변경만 다음 microtask 로 미룬다. `dispose` 는 위젯
  /// 트리를 정리하는 중에 불리므로, 거기서 상태를 바로 바꾸면 디버그 빌드의
  /// Riverpod 이 `Tried to modify a provider while the widget tree was
  /// building` 을 던진다. 파일을 닫은 뒤의 상태 변경은 `await` 다음이라 이미
  /// 정리가 끝난 뒤다.
  Future<void> stopRecordingOnLeave() =>
      _stop(participantCount: null, deferStateChange: true);

  Future<void> _stop({
    required int? participantCount,
    required bool deferStateChange,
  }) async {
    _stopTicker();
    if (state.value == null) return;

    if (!_fileOpen) {
      if (deferStateChange) {
        await Future<void>.microtask(() {});
        if (!ref.mounted) return;
      }
      _update(
        (now) =>
            now.copyWith(recording: false, participantCount: participantCount),
      );
      // 화면을 떠날 때는 새로 적을 것이 없다. 파일은 닫을 때 이미 적었고, 그
      // 사이 제출이 끝나 보냈다고 적었을 수 있다. 다시 적으면 보낸 녹음이
      // 보낼 녹음으로 돌아가 앱을 다시 켰을 때 또 보내려 든다.
      if (deferStateChange) return;
      await _rememberUpload();
      return;
    }
    final current = state.value!;
    _fileOpen = false;
    _stopListeningDevice();
    // 파일을 닫는 사이 provider 가 정리돼도 내릴 수 있게 미리 받아 둔다.
    final service = _service;

    try {
      VisitRecording? saved;
      // 녹음 중에 장치가 멈췄던 일은 파일을 닫으면 지나간 일이다. 저장에 성공하면
      // 남기지 않는다.
      final carried = switch (current.problem) {
        VisitRecordingProblem.interrupted ||
        VisitRecordingProblem.recorderStopped => null,
        final other => other,
      };
      var problem = carried;
      try {
        saved = await _recorder.stop();
        if (saved == null) problem = VisitRecordingProblem.saveFailed;
      } on Exception {
        problem = VisitRecordingProblem.saveFailed;
      }
      // 파일을 닫지 못해도 소리가 남아 있으면 머리글을 다시 채워 살린다. 장치가
      // 먼저 멈춰 이미 닫힌 파일이면 그대로 쓴다.
      final startedPath = current.recordingPath;
      if (saved == null && startedPath != null) {
        try {
          if (isFinishedRecording(startedPath) ||
              repairUnfinishedRecording(startedPath)) {
            saved = VisitRecording(path: startedPath);
            problem = carried;
          }
        } on FileSystemException {
          // 고치지 못했다. 저장 실패로 둔다.
        }
      }
      // 파일을 닫는 사이 provider 가 정리됐으면 상태와 기기 기록을 쓰지 않는다.
      // 정리된 ref 를 쓰면 Riverpod 이 던진다. 파일은 닫혔고 남아 있다.
      if (!ref.mounted) return;

      _update(
        (now) => now.copyWith(
          recording: false,
          recordingPath: saved?.path,
          participantCount: participantCount,
          problem: problem,
          clearProblem: problem == null,
        ),
      );
      if (saved == null && startedPath != null) {
        // 시작할 때 적어 둔 기록을 다시 보낼 목록에서 뺀다. 살리지 못한 파일을
        // 앱을 다시 켰을 때 보내려 들지 않게 한다.
        await _dropUpload(startedPath);
        return;
      }
      await _rememberUpload();
    } finally {
      // 파일을 닫았다. 마지막 소리까지 파일에 쓴 뒤 녹음 알림과 서비스를 내린다.
      service.hide();
      // 녹음이 끝났다. 그 사이 잃은 세션이 있으면 이제 로그인 화면으로 보낸다.
      // 파일을 닫은 뒤 기기 기록까지 마친 다음이다.
      if (ref.mounted && _holdingSession) {
        _holdingSession = false;
        ref.read(sessionHoldProvider.notifier).release();
      }
    }
  }

  /// 살리지 못한 녹음을 다시 보낼 목록에서 뺀다. 파일과 회차 연결은 남긴다.
  Future<void> _dropUpload(String path) async {
    final sessionId = state.value?.sessionId;
    if (sessionId == null) return;
    try {
      await ref
          .read(pendingUploadsProvider)
          .markUploaded(
            PendingUpload(
              sessionId: sessionId,
              audioPath: path,
              participantCount: state.value?.participantCount,
            ),
          );
    } on Exception {
      // 적지 못하면 다시 보내기에서 서버가 거절할 때 정리된다.
    }
  }

  /// 보낼 녹음을 회차 ID 로 기기에 적어 둔다. 앱을 다시 켜도 다시 보낼 수
  /// 있게 하려는 것이다. 참여자 수를 아직 확인하지 않았어도 파일 연결은 남긴다.
  ///
  /// 적지 못해도 면회는 막지 않는다. 앱이 켜져 있는 동안은 이 상태가 파일과
  /// 참여자 수를 들고 있다.
  Future<void> _rememberUpload() async {
    final now = state.value;
    final sessionId = now?.sessionId;
    final path = now?.recordingPath;
    final count = now?.participantCount;
    if (sessionId == null ||
        path == null ||
        now?.problem == VisitRecordingProblem.saveFailed) {
      return;
    }

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

  /// 녹음 장치의 상태가 바뀌었다. 앱이 부르지 않은 멈춤만 본다.
  ///
  /// 앱이 멈출 때는 [pauseRecording] 이 장치를 부르기 전에 [VisitState.recording]
  /// 을 내리고, 끝낼 때는 [_stop] 이 [_fileOpen] 을 먼저 내린다. 그래서 그 뒤에 오는
  /// 알림은 여기서 걸러진다. 장치의 알림은 부른 순서대로 오므로, 멈춘 뒤 바로
  /// 이어서 녹음해도 앞 멈춤 알림이 이어 간 뒤에 닿지 않는다.
  void _onDeviceState(VisitRecorderState device) {
    if (!_fileOpen || !ref.mounted) return;
    final now = state.value;
    if (now == null) return;
    switch (device) {
      case VisitRecorderState.recording:
        return;
      case VisitRecorderState.paused:
        if (!now.recording) return;
        _interrupt(VisitRecordingProblem.interrupted);
      case VisitRecorderState.stopped:
        if (now.problem == VisitRecordingProblem.recorderStopped) return;
        _interrupt(VisitRecordingProblem.recorderStopped);
    }
  }

  /// 보호자가 모르는 사이 녹음이 멈췄다. 시간을 멈추고, 화면이 크게 알리게
  /// [VisitState.problem] 을 두고, 알림도 멈췄다고 바꾼다. 파일은 닫지 않는다.
  /// 이어서 녹음하거나 만남을 끝내 저장하는 것은 보호자가 고른다.
  void _interrupt(VisitRecordingProblem problem) {
    _stopTicker();
    _fail(problem);
    _service.interrupted();
  }

  /// 기다리는 사이에 상태가 바뀌었을 수 있으므로 그때의 값에 얹는다.
  void _update(VisitState Function(VisitState now) change) {
    final now = state.value;
    if (now == null) return;
    state = AsyncData(change(now));
  }

  /// 다음 카드로 넘어간다. 마지막 카드면 첫 카드로 돌아간다.
  void nextCard() {
    final current = state.value;
    if (current == null || current.cards.isEmpty) return;
    goToCard((current.currentIndex + 1) % current.cards.length);
  }

  /// 앞 카드로 돌아간다. 첫 카드면 마지막 카드로 간다.
  void previousCard() {
    final current = state.value;
    if (current == null || current.cards.isEmpty) return;
    final count = current.cards.length;
    goToCard((current.currentIndex - 1 + count) % count);
  }

  /// [index] 번째 카드로 옮긴다. 범위 밖이거나 지금 카드면 그대로 둔다.
  ///
  /// 화면에 보이는 카드만 바꾼다. 서버에 알리는 것은 없다. 꼬리 질문은 그
  /// 카드의 첫 질문부터 다시 보여준다.
  void goToCard(int index) {
    final current = state.value;
    if (current == null) return;
    if (index < 0 || index >= current.cards.length) return;
    if (index == current.currentIndex) return;
    state = AsyncData(current.copyWith(currentIndex: index, followUpIndex: 0));
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
      final fresh = added.where((c) => !have.contains(c.cardId)).toList();
      return now.copyWith(
        cards: [...now.cards, ...fresh],
        addedCardIds: {...now.addedCardIds, for (final c in fresh) c.cardId},
      );
    });
    return true;
  }
}

final visitControllerProvider =
    AsyncNotifierProvider<VisitController, VisitState>(VisitController.new);

/// 이번 실행에서 녹음을 시작해 회차를 만든 면회다. 녹음 화면을 떠나도 남는다.
///
/// [visit] 은 [visitControllerProvider] 의 값이다. 부르는 쪽이 면회 상태를 새로
/// 만들지 않도록 있을 때만 읽어 넘긴다. 다시 만드는 중이면 앞 값이 남아 있을
/// 수 있어(다른 어르신으로 바꾼 경우 등) 믿지 않는다. 회차가 없으면 `null` 이다.
VisitState? startedVisitOf(AsyncValue<VisitState>? visit) {
  if (visit == null || visit.isLoading) return null;
  final state = visit.value;
  return state?.sessionId == null ? null : state;
}

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
