// 갤러리 사진을 눌러 설명 칸을 펼치고 접을 때의 스크롤을 확인한다.
//
// 기준 화면(412 x 917)에서 갤러리가 맨 아래에 겨우 보이게 둔다. 펼치면 끝까지
// 내려 칸을 화면 맨 아래에 두고, 접으면 펼치기 전 자리로 돌아온다. 값은 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile/profile_screen.dart';

import 'sample_profile.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [withSampleProfile]);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('펼치면 끝까지 내려 설명 칸을 화면 맨 아래에 두고 접으면 펼치기 전 자리로 돌아온다', (
    tester,
  ) async {
    await _open(tester);
    // 첫 줄 사진이 화면 맨 아래에 겨우 걸리게 내린다.
    await tester.ensureVisible(find.bySemanticsLabel(RegExp('^사진 1')));
    await tester.pumpAndSettle();
    final before = _position(tester).pixels;
    final screenBottom = tester.view.physicalSize.height / 3;

    await tester.tap(find.bySemanticsLabel(RegExp('^사진 1')));
    await tester.pumpAndSettle();
    expect(
      _position(tester).pixels,
      greaterThan(before),
      reason: '칸이 보이게 내려간다',
    );
    expect(
      _position(tester).pixels,
      closeTo(_position(tester).maxScrollExtent, 0.5),
      reason: '끝까지 내려 칸을 화면 맨 아래에 붙인다',
    );
    expect(
      tester.getBottomLeft(find.text('저장하기')).dy,
      lessThanOrEqualTo(screenBottom),
      reason: '펼친 칸의 버튼까지 보인다',
    );

    // 다른 사진으로 바꿔도 오류 없이 그 사진의 칸이 펼쳐진다.
    await tester.tap(find.bySemanticsLabel(RegExp('^사진 2')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel(RegExp('^사진 2')));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(before, 0.5), reason: '접으면 돌아온다');
    expect(find.text('저장하기'), findsNothing);
  });

  testWidgets('펼친 칸이 이미 다 보이면 스크롤하지 않는다', (tester) async {
    await _open(tester);
    // 화면을 길게 늘려 펼친 칸까지 처음부터 다 보이게 한다.
    tester.view.physicalSize = const Size(1236, 6000);
    await tester.pumpAndSettle();
    final before = _position(tester).pixels;

    await tester.tap(find.bySemanticsLabel(RegExp('^사진 1')));
    await tester.pumpAndSettle();

    expect(find.text('저장하기'), findsOneWidget);
    expect(_position(tester).pixels, before, reason: '다 보이면 그대로 둔다');
  });
}
