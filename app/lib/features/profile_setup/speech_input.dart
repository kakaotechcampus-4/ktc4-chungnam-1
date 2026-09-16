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
abstract interface class SpeechInput {
  Future<SpeechOutcome> listen({required String category, required int attempt});
}

/// 목 데이터의 `LifeFactCollectionState` 를 따라 결과를 돌려준다.
///
/// 어떤 항목이 몇 번 만에 성공하고 어떤 항목이 직접 입력으로 넘어가는지는
/// `assets/mock/profile.json` 에 이미 적혀 있다. 시연용 동작을 따로 지어내지
/// 않고 그 값을 그대로 쓴다.
class MockSpeechInput implements SpeechInput {
  const MockSpeechInput(this._bundle);

  final ProfileBundle _bundle;

  static const _delay = Duration(milliseconds: 1200);

  @override
  Future<SpeechOutcome> listen({
    required String category,
    required int attempt,
  }) async {
    await Future<void>.delayed(_delay);

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

final speechInputProvider = FutureProvider<SpeechInput>((ref) async {
  final bundle = await ref.watch(profileProvider.future);
  return MockSpeechInput(bundle);
});
