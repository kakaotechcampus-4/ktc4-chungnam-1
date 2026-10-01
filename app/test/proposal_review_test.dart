import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/report/changes_screen.dart';

void main() {
  for (final config in [
    (const Size(412, 917), 1.0),
    (const Size(320, 640), 2.0),
  ]) {
    testWidgets('제안 선택·수정·제외·반영 ${config.$1}', (tester) async {
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final profile = (await tester.runAsync(
        () => const MockRepository().loadProfile(),
      ))!;
      final proposal = (await tester.runAsync(
        () => const MockRepository().loadChangeProposal(),
      ))!;
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) async => profile),
          changeProposalProvider.overrideWith((ref) async => proposal),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/review',
        routes: [
          GoRoute(
            path: '/review',
            builder: (_, _) =>
                const ReportChangesScreen(reportId: 'report_demo_001'),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('완료 화면')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildAppTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(config.$2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder, {double delta = 200}) async {
        for (var i = 0; i < 60; i++) {
          var exists = false;
          try {
            exists = finder.evaluate().isNotEmpty;
          } on StateError {
            exists = false;
          }
          if (exists) {
            await tester.ensureVisible(finder);
            break;
          }
          await tester.drag(find.byType(Scrollable).first, Offset(0, -delta));
          await tester.pumpAndSettle();
        }
        await tester.pumpAndSettle();
      }

      await reveal(find.text('덜 꺼내기').first);
      await tester.tap(find.text('덜 꺼내기').first);
      await tester.pumpAndSettle();
      expect(container.read(proposalReviewsProvider), isEmpty);
      await reveal(find.text('이야기 수정').first);
      await tester.tap(find.text('이야기 수정').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '수정한 합성 제목');
      await tester.enterText(
        find.byType(TextFormField).last,
        '보호자가 확인한 합성 이야기입니다.',
      );
      await reveal(find.text('수정 완료'));
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();
      expect(container.read(proposalReviewsProvider), isEmpty);
      await reveal(find.byTooltip('학창 시절 이야기 이번 반영에서 빼기'));
      await tester.tap(find.byTooltip('학창 시절 이야기 이번 반영에서 빼기'));
      await tester.pumpAndSettle();
      await reveal(find.text('되돌리기'));
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      await reveal(find.byTooltip('학창 시절 이야기 이번 반영에서 빼기'));
      await tester.tap(find.byTooltip('학창 시절 이야기 이번 반영에서 빼기'));
      await tester.pumpAndSettle();
      await reveal(find.text('선택한 3개 반영하기'));
      await tester.tap(find.text('선택한 3개 반영하기'));
      await tester.pumpAndSettle();
      expect(find.text('완료 화면'), findsOneWidget);
      final result = container.read(
        proposalReviewsProvider,
      )['report_demo_001']!;
      expect(result['change_demo_001']!.action, 'less');
      expect(result['change_demo_002']!.action, 'exclude');
      expect(result['change_demo_004']!.accepted, isFalse);
      expect(result['change_demo_003']!.accepted, isTrue);
      expect(result['change_demo_003']!.title, '수정한 합성 제목');
      expect(result['change_demo_003']!.content, '보호자가 확인한 합성 이야기입니다.');
      router.go('/review');
      await tester.pumpAndSettle();
      expect(find.text('이미 확인을 마친 제안이에요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
