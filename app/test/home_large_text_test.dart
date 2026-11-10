// 글자를 크게 키워도 홈이 넘치지 않는지 확인한다(`app/DESIGN.md` 접근성 기준).
//
// 안내 문구와 말풍선이 자리를 차지해 그림을 줄여도 모자라면 본문이 스크롤된다.
// 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';

import 'sample_profile.dart';

Future<void> _openHome(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [withSampleProfile]);
  addTearDown(container.dispose);
  final router = buildRouter()..go(AppRoutes.home);
  addTearDown(router.dispose);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final size in const [Size(412, 917), Size(360, 800)]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} 글자 $scale배에서 '
          '홈이 넘치지 않는다', (tester) async {
        await _openHome(tester, size, scale);

        expect(tester.takeException(), isNull);
        expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
      });
    }
  }
}
