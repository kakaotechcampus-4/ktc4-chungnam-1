// B 화면(온보딩과 환자 정보 입력)의 규칙을 확인한다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/speech_api.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/profile_setup/setup_steps.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';
import 'package:saerok/features/profile_setup/speech_recorder.dart';

/// 앨범을 열면 사진 한 장을 고른 것으로 친다.
class _OnePhotoPicker implements PhotoPicker {
  const _OnePhotoPicker();

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async => const [
    PickedPhoto('photo_1.jpg'),
  ];
}

/// 녹음 중인지만 기억하는 가짜 녹음 장치다. 여러 항목이 함께 쓴다.
class _SharedRecorder implements SpeechRecorder {
  bool recording = false;
  int _count = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {
    _count += 1;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    return '/fake/speech_inputs/speech-$_count.wav';
  }

  @override
  Future<void> discard() async => recording = false;

  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> dispose() async {}
}

/// 보낸 순서대로 [replies] 를 완료해야 결과가 오는 가짜 전사 API 다.
class _HeldSpeechApi implements SpeechApi {
  final List<Completer<String>> replies = [];

  @override
  Future<String> transcribe(String audioPath) {
    final reply = Completer<String>();
    replies.add(reply);
    return reply.future;
  }
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

    test('이름이 50자를 넘으면 다 채운 것으로 치지 않는다', () {
      SetupDraft draftNamed(String name) => SetupDraft(
        name: name,
        gender: 'female',
        birthYear: 1943,
        birthMonth: 3,
        birthDay: 12,
        stage: ConditionStage.mildCognitiveImpairment,
      );

      expect(draftNamed('가' * 50).basicInfoFilled, isTrue);
      expect(draftNamed('가' * 51).basicInfoFilled, isFalse);
      expect(draftNamed('가' * 51).nameTooLong, isTrue);
    });

    test('마치면 세부 정보도 그 어르신에게 남긴다', () {
      final container = makeContainer();
      final controller = container.read(setupControllerProvider.notifier);

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
      controller.recordFact('occupation', '  재봉 일을 오래 하셨어요.  ');
      controller.recordFact('hobby', '노래 부르기를 좋아하셨어요.');
      // 고향은 건너뛰었고, 가족은 공백만 남았다.
      controller.recordFact('family', '   ');

      controller.finish();

      final details = container.read(careProfilesProvider).selected!.details;
      expect(details.occupation, '재봉 일을 오래 하셨어요.');
      expect(details.hobby, '노래 부르기를 좋아하셨어요.');
      expect(details.hometown, isNull, reason: '건너뛴 항목은 null 이다');
      expect(details.family, isNull, reason: '계약은 빈 문자열을 받지 않는다');
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

      // profile.json 의 hometown 은 비어 있다.
      expect(bundle.profile.hometown, isNull);

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
      expect((outcome as SpeechHeard).text, bundle.profile.occupation);
    });
  });

  group('이어서 입력', () {
    // 합성 문장이다. 실제 어르신의 생애 정보가 아니다.
    const savedText = '합성 예시 답입니다';

    Future<ProviderContainer> openAt(
      WidgetTester tester,
      SetupState saved,
    ) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(setupControllerProvider.notifier).restore(saved);

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
      return container;
    }

    // 기본 정보를 채운 합성 저장본이다.
    const filled = SetupDraft(
      name: '김○○',
      gender: 'female',
      birthYear: 1943,
      birthMonth: 3,
      birthDay: 12,
      stage: ConditionStage.mildCognitiveImpairment,
    );

    test('뒤로 가기로 나와도 가 본 가장 먼 단계를 기억한다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(setupControllerProvider.notifier)
        ..updateDraft(filled);

      // 셋째 항목까지 갔다가 화면을 나가려고 기본 정보까지 돌아온다.
      for (var i = 0; i < 3; i++) {
        controller.next();
      }
      while (controller.back()) {}
      final saved = container.read(setupControllerProvider);
      expect(saved.stepIndex, 0);

      controller.restore(saved);

      expect(container.read(setupControllerProvider).stepIndex, 3);
    });

    test('기본 정보를 비웠으면 기본 정보부터 연다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(setupControllerProvider.notifier)
          .restore(const SetupState(reachedIndex: 3));

      expect(
        container.read(setupControllerProvider).stepIndex,
        0,
        reason: '그대로 끝까지 가면 마칠 수 없다',
      );
    });

    test('사진을 빼 태그 단계가 없으면 사진 단계에서 연다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(setupControllerProvider.notifier)
          .restore(const SetupState(draft: filled, reachedIndex: 6));

      expect(container.read(setupControllerProvider).isPhoto, isTrue);
    });

    testWidgets('가 본 가장 먼 항목에서 열고 앞 항목의 답도 채워 둔다', (tester) async {
      final first = lifeFactSteps[0];
      final third = lifeFactSteps[2];
      final container = await openAt(
        tester,
        SetupState(
          reachedIndex: 3,
          draft: filled.copyWith(facts: {first.category: savedText}),
        ),
      );

      expect(find.text(third.question), findsOneWidget);
      expect(find.text('말로 답하기'), findsOneWidget, reason: '셋째 항목은 아직 답이 없다');

      container.read(setupControllerProvider.notifier)
        ..back()
        ..back();
      await tester.pumpAndSettle();

      expect(find.text(first.question), findsOneWidget);
      expect(find.widgetWithText(TextField, savedText), findsOneWidget);
      expect(find.text('말로 답하기'), findsNothing, reason: '빈 처음 화면이 아니다');
    });

    // 폰에서 키보드를 올리면 입력칸 아래 버튼이 고정된 `다음` 과 겹쳐 보였다.
    // 키보드 높이는 기준 화면에서 한글 자판이 차지하는 정도로 잡았다.
    testWidgets('글로 쓰는 중 키보드가 올라와도 입력칸이 다음 버튼과 겹치지 않는다', (tester) async {
      final first = lifeFactSteps[0];
      await openAt(
        tester,
        SetupState(
          reachedIndex: 1,
          draft: filled.copyWith(facts: {first.category: savedText}),
        ),
      );

      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 3);
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextField));
      final next = tester.getRect(find.text('다음'));
      expect(field.bottom, lessThan(next.top));
      expect(find.text('말로 답할게요'), findsNothing);
    });
  });

  // PM 확인(PR #146): 하시던 일을 말한 뒤 전사 중에 건너뛰고 고향에서 다시
  // 녹음하면, 앞 전사가 끝날 때 고향 녹음까지 멈췄다.
  testWidgets('전사 중에 건너뛰고 다음 항목에서 녹음해도 앞 전사가 끝날 때 끊기지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final recorder = _SharedRecorder();
    final api = _HeldSpeechApi();
    final container = ProviderContainer(
      overrides: [
        speechInputProvider.overrideWith(
          (ref) async => ServerSpeechInput(recorder: recorder, api: api),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(setupControllerProvider.notifier)
        .restore(
          const SetupState(
            reachedIndex: 1,
            draft: SetupDraft(
              name: '김○○',
              gender: 'female',
              birthYear: 1943,
              birthMonth: 3,
              birthDay: 12,
              stage: ConditionStage.mildCognitiveImpairment,
            ),
          ),
        );
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

    // 옮기는 중에는 진행 표시가 계속 돌아 pumpAndSettle 이 끝나지 않는다.
    Future<void> settle() => tester.pump(const Duration(seconds: 1));

    Future<void> startListening() async {
      await tester.tap(find.text('말로 답하기'));
      await settle();
      await tester.tap(find.byIcon(Icons.mic));
      await settle();
    }

    // 하시던 일을 말로 답하고, 전사가 끝나기 전에 건너뛴다.
    expect(find.text(lifeFactSteps[0].question), findsOneWidget);
    await startListening();
    await tester.tap(find.text('다 말했어요'));
    await settle();
    expect(find.text('말씀을 글로 옮기고 있어요'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '건너뛰기'));
    await settle();

    // 고향에서 다시 녹음을 시작한다.
    expect(find.text(lifeFactSteps[1].question), findsOneWidget);
    await startListening();
    expect(find.text('듣고 있어요'), findsOneWidget);

    // 앞 답변의 전사가 끝난다.
    api.replies.single.complete('합성 하시던 일 문장입니다');
    await settle();

    expect(recorder.recording, isTrue, reason: '고향 녹음은 계속된다');
    expect(find.text('듣고 있어요'), findsOneWidget);

    // 고향 답변도 끝까지 받는다.
    await tester.tap(find.text('다 말했어요'));
    await settle();
    api.replies.last.complete('합성 고향 문장입니다');
    await settle();

    expect(find.text('합성 고향 문장입니다'), findsOneWidget);
    expect(
      container.read(setupControllerProvider).draft.facts,
      {lifeFactSteps[1].category: '합성 고향 문장입니다'},
      reason: '건너뛴 하시던 일에는 늦게 온 결과를 넣지 않는다',
    );
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
