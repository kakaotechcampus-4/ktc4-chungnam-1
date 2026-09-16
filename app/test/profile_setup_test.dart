// B 화면(온보딩과 환자 정보 입력)의 규칙을 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/profile_setup/setup_steps.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('단계 정의', () {
    test('생애 정보 항목은 계약의 category 를 쓴다', () async {
      final bundle = await const MockRepository().loadProfile();
      final contractCategories =
          bundle.collectionStates.map((s) => s.category).toSet();
      final screenCategories = lifeFactSteps.map((s) => s.category).toSet();

      expect(screenCategories, contractCategories);
    });

    test('현재 상태 선택지는 계약의 세 값뿐이다', () {
      expect(ConditionStage.values, hasLength(3));
      expect(
        ConditionStage.values.map((v) => v.name),
        ['mildCognitiveImpairment', 'mildDementia', 'unknown'],
      );
    });
  });

  group('입력 흐름', () {
    ProviderContainer makeContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('기본 정보를 다 채워야 다음으로 넘어갈 수 있다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      expect(container.read(setupControllerProvider).draft.basicInfoFilled, isFalse);

      controller.updateDraft(
        const SetupDraft(
          name: '김○○',
          gender: 'female',
          birthYear: 1943,
          birthMonth: 3,
          birthDay: 12,
          stage: ConditionStage.mildCognitiveImpairment,
        ),
      );

      expect(container.read(setupControllerProvider).draft.basicInfoFilled, isTrue);
    });

    test('사진을 올리지 않으면 태그 단계를 건너뛴다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      // 기본 정보 + 생애 정보 4개를 지나 사진 단계까지 간다.
      for (var i = 0; i < 1 + lifeFactStepCount; i++) {
        controller.next();
      }
      expect(container.read(setupControllerProvider).isPhoto, isTrue);

      controller.next();
      final state = container.read(setupControllerProvider);
      expect(state.isPhotoTags, isFalse, reason: '사진이 없으면 태그를 고를 수 없다');
      expect(state.isLast, isTrue);
    });

    test('사진을 올리면 태그 단계로 간다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      for (var i = 0; i < 1 + lifeFactStepCount; i++) {
        controller.next();
      }
      controller.updateDraft(
        container.read(setupControllerProvider).draft.copyWith(hasPhoto: true),
      );
      controller.next();

      expect(container.read(setupControllerProvider).isPhotoTags, isTrue);
    });

    test('음성 항목은 값이 담기기 전까지 건너뛸 수 있고 담기면 다음이 된다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      controller.next(); // 첫 생애 정보 항목으로
      final step = container.read(setupControllerProvider).lifeFactStep!;
      expect(
        container.read(setupControllerProvider).draft.facts.containsKey(step.category),
        isFalse,
        reason: '아직 값이 없으니 건너뛰기가 보인다',
      );

      controller.recordFact(step.category, '재봉 일을 오래 하셨어요.');
      expect(
        container.read(setupControllerProvider).draft.facts.containsKey(step.category),
        isTrue,
        reason: '값이 담기면 다음으로 바뀐다',
      );

      controller.skipFact(step.category);
      expect(
        container.read(setupControllerProvider).draft.facts.containsKey(step.category),
        isFalse,
      );
    });

    test('뒤로 가면 이전 단계로 돌아가고 첫 단계에서는 화면을 벗어난다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      controller.next();
      expect(controller.back(), isTrue);
      expect(container.read(setupControllerProvider).stepIndex, 0);
      expect(controller.back(), isFalse, reason: '첫 단계에서는 흐름을 벗어난다');
    });
  });

  group('음성 입력 대역', () {
    test('목 데이터가 직접 입력으로 끝난 항목은 2회 알아듣지 못한다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      // profile.json 에서 hobby 는 manualFallback, attemptCount 2 다.
      expect(bundle.stateOf('hobby')?.status, CollectionStatus.manualFallback);

      expect(
        await input.listen(category: 'hobby', attempt: 1),
        isA<SpeechNotHeard>(),
      );
      expect(
        await input.listen(category: 'hobby', attempt: 2),
        isA<SpeechNotHeard>(),
      );
    });

    test('실패하는 항목은 hobby 뿐이다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      for (final step in lifeFactSteps.where((s) => s.category != 'hobby')) {
        expect(
          await input.listen(category: step.category, attempt: 1),
          isA<SpeechHeard>(),
          reason: '${step.category} 는 한 번에 인식되어야 한다',
        );
      }
    });

    test('목 데이터에 문장이 없는 항목은 화면의 예시를 결과로 쓴다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      // profile.json 에 hometown LifeFact 는 없다.
      expect(bundle.factOf('hometown'), isNull);

      final outcome = await input.listen(category: 'hometown', attempt: 1);
      final example = lifeFactSteps
          .firstWhere((s) => s.category == 'hometown')
          .examples
          .first;

      expect(outcome, isA<SpeechHeard>());
      expect((outcome as SpeechHeard).text, example.replaceAll('"', ''));
    });

    test('수집된 항목은 목 데이터의 문장을 돌려준다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      final outcome = await input.listen(category: 'occupation', attempt: 1);

      expect(outcome, isA<SpeechHeard>());
      expect(
        (outcome as SpeechHeard).text,
        bundle.factOf('occupation')?.text,
      );
    });
  });
}
