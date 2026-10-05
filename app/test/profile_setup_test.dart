// B 화면(온보딩과 환자 정보 입력)의 규칙을 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/profile_setup/setup_steps.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';

/// 앨범을 열면 사진 한 장을 고른 것으로 친다.
class _OnePhotoPicker implements PhotoPicker {
  const _OnePhotoPicker();

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async => const [
    PickedPhoto('photo_1.jpg'),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('단계 정의', () {
    test('생애 정보 항목은 계약의 category 를 쓴다', () async {
      final bundle = await const MockRepository().loadProfile();
      final contractCategories = bundle.collectionStates
          .map((s) => s.category)
          .toSet();
      final screenCategories = lifeFactSteps.map((s) => s.category).toSet();

      expect(screenCategories, contractCategories);
    });

    test('현재 상태 선택지는 계약의 세 값뿐이다', () {
      expect(ConditionStage.values, hasLength(3));
      expect(ConditionStage.values.map((v) => v.name), [
        'mildCognitiveImpairment',
        'mildDementia',
        'unknown',
      ]);
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

      expect(
        container.read(setupControllerProvider).draft.basicInfoFilled,
        isFalse,
      );

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

      expect(
        container.read(setupControllerProvider).draft.basicInfoFilled,
        isTrue,
      );
    });

    test('사진 단계가 마지막이고 태그 단계는 없다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      // 기본 정보 + 생애 정보 4개를 지나 사진 단계까지 간다.
      for (var i = 0; i < 1 + lifeFactStepCount; i++) {
        controller.next();
      }
      var state = container.read(setupControllerProvider);
      expect(state.isPhoto, isTrue);
      expect(state.isLast, isTrue);
      expect(state.progress, 1.0);

      // 사진을 올려도 더 갈 단계가 없다.
      controller.addPhotos(const [PickedPhoto('photo_1.jpg')]);
      controller.next();
      state = container.read(setupControllerProvider);
      expect(state.isPhoto, isTrue, reason: '마지막 단계에서는 화면이 흐름을 끝낸다');
    });

    test('음성 항목은 값이 담기기 전까지 건너뛸 수 있고 담기면 다음이 된다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

      controller.next(); // 첫 생애 정보 항목으로
      final step = container.read(setupControllerProvider).lifeFactStep!;
      expect(
        container
            .read(setupControllerProvider)
            .draft
            .facts
            .containsKey(step.category),
        isFalse,
        reason: '아직 값이 없으니 건너뛰기가 보인다',
      );

      controller.recordFact(step.category, '재봉 일을 오래 하셨어요.');
      expect(
        container
            .read(setupControllerProvider)
            .draft
            .facts
            .containsKey(step.category),
        isTrue,
        reason: '값이 담기면 다음으로 바뀐다',
      );

      controller.skipFact(step.category);
      expect(
        container
            .read(setupControllerProvider)
            .draft
            .facts
            .containsKey(step.category),
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
    /// 녹음을 시작하고 곧바로 끝내 결과를 받는다.
    Future<SpeechOutcome> listen(
      MockSpeechInput input, {
      required String category,
      required int attempt,
    }) async =>
        (await input.start(category: category, attempt: attempt)).finish();

    test('목 데이터가 직접 입력으로 끝난 항목은 2회 알아듣지 못한다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      // profile.json 에서 hobby 는 manualFallback, attemptCount 2 다.
      expect(bundle.stateOf('hobby')?.status, CollectionStatus.manualFallback);

      expect(
        await listen(input, category: 'hobby', attempt: 1),
        isA<SpeechNotHeard>(),
      );
      expect(
        await listen(input, category: 'hobby', attempt: 2),
        isA<SpeechNotHeard>(),
      );
    });

    test('실패하는 항목은 hobby 뿐이다', () async {
      final bundle = await const MockRepository().loadProfile();
      final input = MockSpeechInput(bundle);

      for (final step in lifeFactSteps.where((s) => s.category != 'hobby')) {
        expect(
          await listen(input, category: step.category, attempt: 1),
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

      final outcome = await listen(input, category: 'hometown', attempt: 1);
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

      final outcome = await listen(input, category: 'occupation', attempt: 1);

      expect(outcome, isA<SpeechHeard>());
      expect((outcome as SpeechHeard).text, bundle.factOf('occupation')?.text);
    });
  });

  group('다음 버튼 자리', () {
    /// 화면을 띄우고 지금 보이는 행동 버튼의 사각형과 스크롤 영역을 돌려준다.
    Future<(Rect button, Rect viewport)> openSetup(
      WidgetTester tester, {
      int advance = 0,
      List<Override> overrides = const [],
    }) async {
      const dpr = 3.0;
      tester.view.physicalSize = const Size(411 * dpr, 891 * dpr);
      tester.view.devicePixelRatio = dpr;
      tester.view.padding = const FakeViewPadding(
        top: 24 * dpr,
        bottom: 24 * dpr,
      );
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ProfileSetupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < advance; i++) {
        container.read(setupControllerProvider.notifier).next();
        await tester.pumpAndSettle();
      }

      var button = find.widgetWithText(FilledButton, '다음');
      if (button.evaluate().isEmpty) {
        button = find.widgetWithText(OutlinedButton, '건너뛰기');
      }
      return (
        tester.getRect(button.first),
        tester.getRect(find.byType(SingleChildScrollView).first),
      );
    }

    testWidgets('기본 정보는 입력란이 많아 버튼이 본문과 함께 흐른다', (tester) async {
      final (button, viewport) = await openSetup(tester);

      expect(
        button.top,
        lessThan(viewport.bottom),
        reason: '아래에 고정하면 그만큼 입력란이 보이는 높이를 가져간다',
      );
    });

    testWidgets('생애 정보는 한 화면에 들어가므로 버튼을 고정한다', (tester) async {
      final (button, viewport) = await openSetup(tester, advance: 1);

      expect(
        button.top,
        greaterThanOrEqualTo(viewport.bottom),
        reason: '스크롤 영역 밖에 있어야 고정이다',
      );
    });

    testWidgets('사진 단계에서 흐름을 마치고 태그를 고르러 가지 않는다', (tester) async {
      await openSetup(
        tester,
        advance: 1 + lifeFactStepCount,
        overrides: [
          photoPickerProvider.overrideWithValue(const _OnePhotoPicker()),
        ],
      );

      expect(find.widgetWithText(OutlinedButton, '건너뛰기'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '다음'), findsNothing);

      await tester.tap(find.text('사진 추가하기'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '마치기'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, '다음'),
        findsNothing,
        reason: '사진 다음에 태그 단계가 없다',
      );
    });
  });
}
