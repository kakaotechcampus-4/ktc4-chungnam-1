// 보호자 평가 뒤 위로 화면이 Q1 점수에 맞는 문구를 띄우고 홈으로 보내는지
// 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/review/comfort_messages.dart';
import 'package:saerok/features/review/comfort_screen.dart';
import 'package:saerok/features/review/review_controller.dart';

void main() {
  group('점수별 문구', () {
    test('1점부터 5점까지 서로 다른 문구가 있다', () {
      final titles = {
        for (var score = 1; score <= 5; score++)
          comfortMessageFor(score)!.title,
      };
      expect(titles, hasLength(5));
    });

    test('점수가 없거나 범위를 벗어나면 문구가 없다', () {
      expect(comfortMessageFor(null), isNull);
      expect(comfortMessageFor(0), isNull);
      expect(comfortMessageFor(6), isNull);
    });
  });

  group('위로 화면', () {
    /// 위로 화면과 홈 자리만 있는 라우터로 띄운다.
    ///
    /// 기본은 기준 화면 412 x 917 dp 다.
    Future<void> open(
      WidgetTester tester, {
      int? satisfaction,
      Size physicalSize = const Size(1236, 2751),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      if (satisfaction != null) {
        container
            .read(reviewControllerProvider.notifier)
            .setSatisfaction(satisfaction);
      }

      final router = GoRouter(
        initialLocation: AppRoutes.visitReviewDone,
        routes: [
          GoRoute(
            path: AppRoutes.visitReviewDone,
            builder: (context, state) => const ComfortScreen(),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('홈 자리')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (var score = 1; score <= 5; score++) {
      testWidgets('$score점이면 그 점수의 문구를 띄운다', (tester) async {
        await open(tester, satisfaction: score);

        final message = comfortMessageFor(score)!;
        expect(find.text('제출 완료!'), findsOneWidget);
        expect(find.text(comfortFixedMessage), findsOneWidget);
        expect(find.text(message.title), findsOneWidget);
        expect(find.text(message.body), findsOneWidget);
      });
    }

    testWidgets('작은 화면에서 글자를 키워도 넘치지 않고 버튼이 보인다', (tester) async {
      // 360 x 640 dp 에 글자 1.5배.
      await open(
        tester,
        satisfaction: 1,
        physicalSize: const Size(1080, 1920),
        textScale: 1.5,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('홈으로'), findsOneWidget);
    });

    testWidgets('점수가 없으면 고정 문장만 띄운다', (tester) async {
      await open(tester);

      expect(find.text(comfortFixedMessage), findsOneWidget);
      for (var score = 1; score <= 5; score++) {
        expect(find.text(comfortMessageFor(score)!.title), findsNothing);
      }
    });

    testWidgets('홈으로 버튼을 누르면 홈으로 간다', (tester) async {
      await open(tester, satisfaction: 3);

      await tester.tap(find.text('홈으로'));
      await tester.pumpAndSettle();

      expect(find.text('홈 자리'), findsOneWidget);
    });

    testWidgets('뒤로 가기를 해도 소감 화면이 아니라 홈으로 간다', (tester) async {
      await open(tester, satisfaction: 3);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('홈 자리'), findsOneWidget);
    });
  });
}
