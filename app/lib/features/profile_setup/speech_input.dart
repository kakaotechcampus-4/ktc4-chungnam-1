import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import 'setup_steps.dart';

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

/// 음성 입력의 대역이다.
///
/// **실제 녹음과 음성 인식은 AI 영역이 소유한다**(`app/CLAUDE.md`). FE 는 화면과
/// 상태만 다루며, AI 가 입력 인터페이스를 확정하면 이 자리를 그 구현이 대신한다.
/// 녹음 라이브러리와 음성 형식을 FE 가 정하지 않는다.
///
/// **임시 형태다. AI 확정이 필요하다.** 화면이 듣는 중과 글로 옮기는 중을 나눠
/// 보여주도록 녹음 시작([start])과 녹음 끝([SpeechRecording.finish])을 갈랐다.
/// 예전에는 한 번의 호출이 둘을 함께 끝내서 변환을 기다리는 자리를 보여줄 수
/// 없었다.
abstract interface class SpeechInput {
  /// 녹음을 시작한다.
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  });
}

/// 진행 중인 녹음 한 번이다.
abstract interface class SpeechRecording {
  /// 녹음을 끝내고 글로 옮긴 결과를 기다린다.
  Future<SpeechOutcome> finish();

  /// 결과 없이 녹음을 버린다. 화면을 벗어날 때 부른다.
  Future<void> cancel();
}

/// 목 데이터의 `LifeFactCollectionState` 를 따라 결과를 돌려준다.
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

    final fact = _bundle.factOf(category);
    if (fact != null) return SpeechHeard(fact.text);

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
  Future<SpeechOutcome> finish() async {
    await Future<void>.delayed(MockSpeechInput._delay);
    return _outcome();
  }

  @override
  Future<void> cancel() async {}
}

final speechInputProvider = FutureProvider<SpeechInput>((ref) async {
  final bundle = await ref.watch(profileSampleProvider.future);
  return MockSpeechInput(bundle);
});
