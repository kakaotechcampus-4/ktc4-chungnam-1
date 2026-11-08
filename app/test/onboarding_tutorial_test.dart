// 가입 직후 처음 오셨네요에서 새록 소개를 띄우고 홈으로 보내는지 확인한다.
//
// 정보는 여기서 묻지 않는다. 홈의 `오늘의 대화카드 받기` 를 누를 때 묻는다
// (`no_profile_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/onboarding_screen.dart';
import 'package:saerok/features/profile_setup/onboarding_tutorial.dart';

void main() {
  Future<void> openOnboarding(
    WidgetTester tester, {
    double width = 412,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 917 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('홈 화면'))),
        ),
        GoRoute(
          path: AppRoutes.profileCreate,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('환자 정보 입력 화면'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  String titleOf(int index) => tutorialPages[index].title;

  testWidgets('화면이 뜨면 소개 첫 장을 띄운다', (tester) async {
    await openOnboarding(tester);

    expect(find.text('새록에\n처음 오셨네요!'), findsOneWidget);
    expect(find.byType(OnboardingTutorial), findsOneWidget);
    expect(find.text(titleOf(0)), findsOneWidget);
    expect(find.text('이전'), findsOneWidget, reason: '자리는 남긴다');
    expect(
      find.bySemanticsLabel('${tutorialPages.length}장 중 1장'),
      findsOneWidget,
    );
  });

  test('소개는 네다섯 장이고 의료 효과를 말하지 않는다', () {
    expect(tutorialPages.length, inInclusiveRange(4, 5));
    for (final page in tutorialPages) {
      final text = '${page.title} ${page.body}';
      for (final banned in ['치료', '진단', '회복', '예방', '개선 효과']) {
        expect(text.contains(banned), isFalse, reason: '$banned: $text');
      }
    }
  });

  testWidgets('다음으로 끝까지 넘기고 시작하기를 누르면 홈으로 간다', (tester) async {
    await openOnboarding(tester);

    for (var i = 1; i < tutorialPages.length; i++) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text(titleOf(i)), findsOneWidget);
    }
    expect(find.text('다음'), findsNothing);
    // 마지막 장에서 설정의 도움말에서 다시 볼 수 있다고 알린다. 화면 아래의
    // 같은 안내와 소개의 것 중 소개 것을 찾는다.
    expect(
      find.descendant(
        of: find.byType(OnboardingTutorial),
        matching: find.text(tutorialHelpHint),
      ),
      findsOneWidget,
    );
    // 화면 아래의 시작하기와 소개의 시작하기 중 소개 것을 누른다.
    await tester.tap(
      find.descendant(
        of: find.byType(OnboardingTutorial),
        matching: find.text('시작하기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈 화면'), findsOneWidget);
    expect(find.text('환자 정보 입력 화면'), findsNothing, reason: '정보는 묻지 않는다');
  });

  testWidgets('이전으로 앞 장에 돌아간다', (tester) async {
    await openOnboarding(tester);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전'));
    await tester.pumpAndSettle();

    expect(find.text(titleOf(0)), findsOneWidget);
  });

  testWidgets('옆으로 밀면 넘어간다', (tester) async {
    await openOnboarding(tester);

    await tester.fling(find.text(titleOf(0)), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text(titleOf(1)), findsOneWidget);
  });

  testWidgets('건너뛰면 처음 오셨네요에 남고 다시 보거나 홈으로 갈 수 있다', (tester) async {
    await openOnboarding(tester);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingTutorial), findsNothing);
    expect(find.text('새록에\n처음 오셨네요!'), findsOneWidget);
    expect(
      find.text(tutorialHelpHint),
      findsOneWidget,
      reason: '건너뛰어도 설정의 도움말에서 다시 볼 수 있다고 알린다',
    );

    await tester.tap(find.text('새록 소개 다시 보기'));
    await tester.pumpAndSettle();
    expect(find.text(titleOf(0)), findsOneWidget);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('홈 화면'), findsOneWidget);
  });

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('글자를 키워도 넘치지 않는다 ${width}dp 글자 $scale', (tester) async {
        await openOnboarding(tester, width: width, scale: scale);

        // 장마다 글 길이가 달라 모두 넘겨 본다. 버튼이 아래로 밀려나면
        // 스크롤해서 누른다.
        for (var i = 1; i < tutorialPages.length; i++) {
          await tester.ensureVisible(find.text('다음'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('다음'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text(titleOf(tutorialPages.length - 1)), findsOneWidget);
      });
    }
  }
}
