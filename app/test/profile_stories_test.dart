import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile/stories_provider.dart';
import 'package:saerok/features/profile/stories_screen.dart';

void main() {
  for (final config in [
    (const Size(412, 917), 1.0),
    (const Size(320, 640), 2.0),
  ]) {
    testWidgets('이야기 탐색·추가·수정 ${config.$1} 배율 ${config.$2}', (tester) async {
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bundle = (await tester.runAsync(
        () => const MockRepository().loadProfile(),
      ))!;
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) async => bundle)],
      );
      addTearDown(container.dispose);
      final router = buildRouter()..go(AppRoutes.profile);
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
              ).copyWith(textScaler: TextScaler.linear(config.$2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StoryTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('이야기 전체 보기 (5)'));
      await tester.tap(find.text('이야기 전체 보기 (5)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이야기 추가하기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '합성 새 이야기');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '테스트용으로 만든 합성 내용입니다.',
      );
      await tester.scrollUntilVisible(
        find.text('이야기 저장하기'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('이야기 저장하기'));
      await tester.pumpAndSettle();
      expect(find.text('전체 6개'), findsOneWidget);
      expect(
        container.read(profileStoriesProvider).requireValue.first.title,
        '합성 새 이야기',
      );
      await tester.ensureVisible(find.text('합성 새 이야기'));
      await tester.tap(find.text('합성 새 이야기'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('이야기 수정하기'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('이야기 수정하기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '수정한 합성 이야기');
      await tester.scrollUntilVisible(
        find.text('수정한 내용 저장'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('수정한 내용 저장'));
      await tester.pumpAndSettle();
      expect(find.text('수정한 합성 이야기'), findsOneWidget);
      expect(container.read(profileStoriesProvider).requireValue, hasLength(6));
      expect(tester.takeException(), isNull);
    });
  }
}
