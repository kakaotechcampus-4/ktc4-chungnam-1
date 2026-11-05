// 하단 탭의 설정 탭과 고른 탭 위 막대의 움직임을 확인한다. 값은 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/widgets/app_scaffold.dart';

import 'sample_profile.dart';

/// 막대(높이 3)의 가운데 x 좌표.
double _barCenterX(WidgetTester tester) {
  final bar = find.descendant(
    of: find.byType(AppBottomNav),
    matching: find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 3,
    ),
  );
  return tester.getCenter(bar.last).dx;
}

/// [label] 탭 칸의 가운데 x 좌표.
double _slotCenterX(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label).last).dx;

/// 목 자료를 읽는 실제 비동기 처리에 차례를 주며 화면을 흘린다. 불러오는 동안
/// 도는 표시가 있어 pumpAndSettle 은 끝나지 않을 수 있다.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('설정 탭은 맨 오른쪽 톱니바퀴이고 누르면 설정 화면이 열린다', (tester) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [withSampleProfile]);
    addTearDown(container.dispose);
    final router = buildRouter();
    router.go(AppRoutes.home);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    final labels = ['일대기', '리포트', '홈', '마이페이지', '설정'];
    final xs = [for (final l in labels) _slotCenterX(tester, l)];
    expect(xs, orderedEquals([...xs]..sort()), reason: '일대기 옆에 리포트, 맨 오른쪽에 설정');
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(_barCenterX(tester), closeTo(_slotCenterX(tester, '홈'), 1));

    final homeX = _slotCenterX(tester, '홈');
    final settingsX = _slotCenterX(tester, '설정');
    await tester.tap(find.text('설정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // 화면이 바뀌는 동안에도 하단 탭은 하나뿐이고 막대가 옮겨 가는 중이다.
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(_barCenterX(tester), inExclusiveRange(homeX, settingsX));
    await tester.pumpAndSettle();

    expect(find.text('계정 약관 동의'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget, reason: '고른 탭은 채운 아이콘');
    expect(_barCenterX(tester), closeTo(_slotCenterX(tester, '설정'), 1));
  });

  testWidgets('리포트 탭은 리포트 기록을, 마이페이지 탭은 메뉴 없이 프로필 설정을 연다', (tester) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [withSampleProfile]);
    addTearDown(container.dispose);
    final router = buildRouter();
    router.go(AppRoutes.home);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('리포트'));
    await _settle(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('리포트 기록')),
      findsOneWidget,
    );
    expect(_barCenterX(tester), closeTo(_slotCenterX(tester, '리포트'), 1));

    await tester.tap(find.text('마이페이지'));
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing, reason: '메뉴를 띄우지 않는다');
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('프로필 설정')),
      findsOneWidget,
    );
    expect(_barCenterX(tester), closeTo(_slotCenterX(tester, '마이페이지'), 1));

    // 탭 화면끼리는 바꿔 끼우므로 뒤로 가면 홈이다.
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
  });

  testWidgets('고른 탭이 바뀌면 막대가 앞 탭 자리에서 새 탭으로 미끄러진다', (tester) async {
    Widget nav(AppTab current) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(current: current, onSelected: (_) {}),
      ),
    );

    await tester.pumpWidget(nav(AppTab.home));
    await tester.pumpAndSettle();
    final home = _slotCenterX(tester, '홈');
    final settings = _slotCenterX(tester, '설정');

    await tester.pumpWidget(nav(AppTab.settings));
    final start = _barCenterX(tester);
    await tester.pump(const Duration(milliseconds: 120));
    final middle = _barCenterX(tester);
    await tester.pumpAndSettle();
    final end = _barCenterX(tester);

    expect(start, closeTo(home, 1), reason: '앞 탭인 홈 자리에서 출발한다');
    expect(middle, inExclusiveRange(home, settings), reason: '중간을 지난다');
    expect(end, closeTo(settings, 1));
  });
}
