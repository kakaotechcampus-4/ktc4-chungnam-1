import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/speech_api.dart';
import '../auth/auth_providers.dart';
import 'setup_steps.dart';
import 'speech_recorder.dart';

/// 음성 입력 한 번의 결과다.
sealed class SpeechOutcome {
  const SpeechOutcome();
}

/// 말씀을 알아들었다.
class SpeechHeard extends SpeechOutcome {
  const SpeechHeard(this.text);

  final String text;
}

/// 알아듣지 못했다. 2회까지는 다시 시도하고 그 다음에는 직접 입력으로 넘어간다.
class SpeechNotHeard extends SpeechOutcome {
  const SpeechNotHeard();
}

/// 글로 옮기지 못했다. 서버에 닿지 못했거나 서버가 처리하지 못한 경우다.
///
/// 보호자가 잘못 말한 것이 아니므로 알아듣지 못한 횟수에 세지 않는다.
class SpeechFailed extends SpeechOutcome {
  const SpeechFailed({required this.canResend});

  /// 녹음이 남아 있어 [SpeechRecording.resend] 로 같은 녹음을 다시 보낼 수
  /// 있다. 연결 실패, 시간 초과처럼 서버가 다시 시도해도 된다고 한 경우다.
  /// 아니면 녹음은 이미 지웠다.
  final bool canResend;
}

/// 녹음을 시작하지 못한 이유.
enum SpeechStartProblem {
  /// 마이크 권한을 받지 못했다.
  micDenied,

  /// 녹음 장치를 열지 못했다.
  unavailable,
}

/// 녹음을 시작하지 못했다. [SpeechInput.start] 가 던진다.
class SpeechStartFailure implements Exception {
  const SpeechStartFailure(this.problem);

  final SpeechStartProblem problem;

  @override
  String toString() => 'SpeechStartFailure($problem)';
}

/// 세부 정보 음성 입력이다.
///
/// 앱이 WAV 로 녹음해 BE 의 짧은 음성 전사 API 로 보내고 글자를 받는다. 녹음
/// 형식과 API 는 이슈 #138 의 BE 답변대로다. 화면이 듣는 중과 글로 옮기는 중을
/// 나눠 보여주도록 녹음 시작([start])과 녹음 끝([SpeechRecording.finish])을
/// 갈랐다.
abstract interface class SpeechInput {
  /// 녹음을 시작한다. 시작하지 못하면 [SpeechStartFailure] 를 던진다.
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  });
}

/// 진행 중인 녹음 한 번이다.
///
/// 결과를 받으면 녹음 파일을 지운다. 다시 보낼 수 있는 실패
/// (`SpeechFailed(canResend: true)`)일 때만 남기며, 그때는 [resend] 나
/// [cancel] 을 부를 때까지 남는다.
abstract interface class SpeechRecording {
  /// 녹음이 최대 길이([speechMaxDuration])에 닿으면 끝난다. 화면은 이때
  /// [finish] 를 부른다.
  Future<void> get limitReached;

  /// 녹음을 끝내고 글로 옮긴 결과를 기다린다.
  Future<SpeechOutcome> finish();

  /// 남아 있는 녹음을 다시 보낸다. 다시 말하지 않아도 된다.
  Future<SpeechOutcome> resend();

  /// 결과 없이 녹음을 버리고 파일을 지운다. 화면을 벗어나거나 다른 방법으로
  /// 바꿀 때 부른다. 여러 번 불러도 된다.
  Future<void> cancel();
}

/// 실제 마이크로 녹음하고 서버에서 글로 옮긴다. 로그인했을 때 쓴다.
class ServerSpeechInput implements SpeechInput {
  const ServerSpeechInput({
    required this.recorder,
    required this.api,
    this.maxDuration = speechMaxDuration,
  });

  final SpeechRecorder recorder;
  final SpeechApi api;

  /// 녹음 최대 길이. 테스트에서 줄인다.
  final Duration maxDuration;

  @override
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  }) async {
    final bool allowed;
    try {
      allowed = await recorder.hasPermission();
    } on Exception {
      throw const SpeechStartFailure(SpeechStartProblem.micDenied);
    }
    if (!allowed) throw const SpeechStartFailure(SpeechStartProblem.micDenied);

    try {
      await recorder.start();
    } on Exception {
      await recorder.discard();
      throw const SpeechStartFailure(SpeechStartProblem.unavailable);
    }
    return _ServerRecording(recorder, api, maxDuration);
  }
}

class _ServerRecording implements SpeechRecording {
  _ServerRecording(this._recorder, this._api, Duration maxDuration) {
    _timer = Timer(maxDuration, () {
      if (!_limit.isCompleted) _limit.complete();
    });
  }

  final SpeechRecorder _recorder;
  final SpeechApi _api;
  final _limit = Completer<void>();
  late final Timer _timer;

  /// 다 녹음한 파일. 녹음 중이거나 지운 뒤에는 없다.
  String? _path;

  /// [finish] 로 녹음을 끝냈다. 그 뒤로는 장치를 다른 녹음이 쓸 수 있다.
  bool _stopped = false;

  @override
  Future<void> get limitReached => _limit.future;

  @override
  Future<SpeechOutcome> finish() async {
    _timer.cancel();
    _stopped = true;
    String? path;
    try {
      path = await _recorder.stop();
    } on Exception {
      path = null;
    }
    if (path == null) {
      await _recorder.discard();
      return const SpeechFailed(canResend: false);
    }
    _path = path;
    return _send(path);
  }

  @override
  Future<SpeechOutcome> resend() async {
    final path = _path;
    if (path == null) return const SpeechFailed(canResend: false);
    return _send(path);
  }

  @override
  Future<void> cancel() async {
    _timer.cancel();
    final path = _path;
    _path = null;
    // 끝낸 녹음은 자기 파일만 지운다. 장치를 멈추면 그사이 다음 항목에서
    // 시작한 녹음까지 끊긴다.
    if (_stopped) {
      if (path != null) await _recorder.delete(path);
    } else {
      _stopped = true;
      await _recorder.discard();
    }
  }

  Future<SpeechOutcome> _send(String path) async {
    final String text;
    try {
      text = await _api.transcribe(path);
    } on ApiFailure catch (failure) {
      // 다시 보낼지는 오류 코드로 정하지 않고 서버가 준 `retryable` 을 따른다.
      final canResend = switch (failure) {
        ApiNetworkFailure() => true,
        ApiServerFailure(:final retryable) => retryable,
        _ => false,
      };
      if (!canResend) await cancel();
      return SpeechFailed(canResend: canResend);
    } on Exception {
      await cancel();
      return const SpeechFailed(canResend: false);
    }

    await cancel();
    final trimmed = text.trim();
    return trimmed.isEmpty ? const SpeechNotHeard() : SpeechHeard(trimmed);
  }
}

/// 목 데이터의 `LifeFactCollectionState` 를 따라 결과를 돌려준다. 로그인하지
/// 않았을 때(구글 설정이 없는 디버그 빌드) 쓴다.
///
/// 어떤 항목이 몇 번 만에 성공하고 어떤 항목이 직접 입력으로 넘어가는지는
/// `assets/mock/profile.json` 에 이미 적혀 있다. 시연용 동작을 따로 지어내지
/// 않고 그 값을 그대로 쓴다.
class MockSpeechInput implements SpeechInput {
  const MockSpeechInput(this._bundle);

  final ProfileBundle _bundle;

  /// 글로 옮기는 데 걸리는 시간을 흉내 낸다.
  static const _delay = Duration(milliseconds: 1200);

  @override
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  }) async => _MockRecording(() => _outcomeOf(category, attempt));

  SpeechOutcome _outcomeOf(String category, int attempt) {
    final state = _bundle.stateOf(category);
    // 직접 입력으로 끝난 항목은 기록된 시도 횟수만큼 알아듣지 못한다.
    if (state != null &&
        state.status == CollectionStatus.manualFallback &&
        attempt <= state.attemptCount) {
      return const SpeechNotHeard();
    }

    final detail = _bundle.profile.detailOf(category);
    if (detail != null) return SpeechHeard(detail);

    // 목 데이터에 문장이 없는 항목은 화면에 보여준 예시를 결과로 쓴다.
    // 없는 생애 정보를 지어내지 않기 위해서다.
    final step = lifeFactSteps
        .where((s) => s.category == category)
        .firstOrNull;
    final example = step?.examples.firstOrNull;
    if (example == null) return const SpeechNotHeard();
    return SpeechHeard(example.replaceAll('"', ''));
  }
}

/// 실제로 녹음하지 않는다. 끝내면 정해진 결과를 잠시 뒤에 돌려준다.
class _MockRecording implements SpeechRecording {
  _MockRecording(this._outcome);

  final SpeechOutcome Function() _outcome;

  @override
  Future<void> get limitReached => Completer<void>().future;

  @override
  Future<SpeechOutcome> finish() async {
    await Future<void>.delayed(MockSpeechInput._delay);
    return _outcome();
  }

  @override
  Future<SpeechOutcome> resend() => finish();

  @override
  Future<void> cancel() async {}
}

/// 로그인했으면 실제 녹음과 서버 전사를, 아니면 목을 쓴다.
final speechInputProvider = FutureProvider<SpeechInput>((ref) async {
  if (ref.watch(sessionProvider.select((s) => s != null))) {
    return ServerSpeechInput(
      recorder: ref.watch(speechRecorderProvider),
      api: ref.watch(speechApiProvider),
    );
  }
  final bundle = await ref.watch(profileSampleProvider.future);
  return MockSpeechInput(bundle);
});
