// 프로필 설정(MYPAGE)에서 어르신 정보를 보여주는 자리를 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile/profile_screen.dart';

import 'sample_profile.dart';

/// 어르신 한 분을 등록한 상태로 프로필 설정을 띄운다.
Future<ProviderContainer> _open(WidgetTester tester) async {
  // 기준 화면 412 x 917 dp 를 길게 늘려 스크롤 없이 모든 항목을 본다.
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [withSampleProfile]);
  addTearDown(container.dispose);

  // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('어르신 정보 칸이 보이고 내용 추가하기 버튼은 없다', (tester) async {
    await _open(tester);

    for (final shown in ['기본 정보', '세부 정보', '갤러리']) {
      expect(find.text(shown), findsOneWidget, reason: shown);
    }
    expect(
      find.text('내용 추가하기'),
      findsNothing,
      reason: '생애 정보 추가는 일대기에서 한다',
    );
  });
}
