// 시스템 글자를 크게 키웠을 때 한 줄이어야 할 글이 꺾이지 않는지 확인한다.
//
// 2026-11-07 Galaxy S22에서 글자 크기 1.3배일 때 하단 탭 "마이페이지"가 두 줄로
// 꺾였고, 기본 크기에서도 생년 칸의 "1933년"이 두 줄로 꺾였다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile_setup/basic_info_step.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/widgets/app_scaffold.dart';

void main() {
  void useScreen(WidgetTester tester, double width, double scale) {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('하단 탭 이름은 한 줄이고 칸 안에 들어간다 ${width}dp 글자 $scale', (
        tester,
      ) async {
        useScreen(tester, width, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              bottomNavigationBar: AppBottomNav(
                current: AppTab.home,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final oneLine = tester.getRect(find.text('홈')).height;
        for (final label in ['일대기', '리포트', '홈', '마이페이지', '설정']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.height, lessThanOrEqualTo(oneLine + 0.5), reason: label);
          expect(rect.width, lessThanOrEqualTo(width / 5), reason: label);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('고른 생년월일은 칸 안에서 한 줄이다 ${width}dp 글자 $scale', (tester) async {
        useScreen(tester, width, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: BasicInfoStep(
                  draft: const SetupDraft(
                    birthYear: 1933,
                    birthMonth: 3,
                    birthDay: 5,
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final oneLine = tester.getRect(find.text('3월')).height;
        for (final value in ['1933년', '3월', '5일']) {
          expect(
            tester.getRect(find.text(value)).height,
            lessThanOrEqualTo(oneLine + 0.5),
            reason: value,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
