// G-1 리포트의 쉬운 모드를 확인한다.
//
// 리뷰 미팅 피드백으로 글자 크기 키우기 대신, 크기와 대비를 함께 올리는 모드를
// 넣었다. 읽는 사람은 보호자 본인이고 이 화면에 머무는 동안만 기억한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/report/report_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openReport(
    WidgetTester tester, {
    bool fromHistory = false,
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: ReportScreen(reportId: 'r-001', fromHistory: fromHistory),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  group('쉬운 모드 버튼', () {
    testWidgets('리포트에 떠 있고 처음에는 꺼져 있다', (tester) async {
      await openReport(tester);

      expect(find.text('쉬운 모드'), findsOneWidget);
      expect(
        find.byIcon(Icons.format_size),
        findsOneWidget,
        reason: '꺼짐은 글자 크기 아이콘이다',
      );
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('켜면 색과 아이콘이 함께 바뀐다', (tester) async {
      await openReport(tester);

      await tester.tap(find.text('쉬운 모드'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.check),
        findsOneWidget,
        reason: '색만으로 상태를 알리지 않는다',
      );
      expect(find.byIcon(Icons.format_size), findsNothing);
    });

    testWidgets('변경 사항 버튼과 겹치지 않는다', (tester) async {
      await openReport(tester);

      final easy = tester.getRect(find.text('쉬운 모드'));
      final primary = tester.getRect(find.text('변경 사항 확인하기'));

      expect(easy.bottom, lessThan(primary.top), reason: '변경 사항 버튼 위에 둔다');
    });

    testWidgets('기록에서 열어 하단 버튼이 없어도 화면 안에 있다', (tester) async {
      await openReport(tester, fromHistory: true);

      expect(find.text('변경 사항 확인하기'), findsNothing);

      final easy = tester.getRect(find.text('쉬운 모드'));
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      expect(easy.bottom, lessThanOrEqualTo(screen));
      expect(find.text('쉬운 모드'), findsOneWidget);
    });
  });

  group('쉬운 모드가 바꾸는 것', () {
    /// 글 하나의 스타일을 집는다.
    TextStyle styleOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!;

    testWidgets('본문과 소제목이 커진다', (tester) async {
      await openReport(tester);

      final beforeSection = styleOf(tester, '오늘의 만남').fontSize!;

      await tester.tap(find.text('쉬운 모드'));
      await tester.pumpAndSettle();

      final afterSection = styleOf(tester, '오늘의 만남').fontSize!;

      expect(afterSection, greaterThan(beforeSection));
      expect(afterSection, 26);
    });

    testWidgets('보조 글자는 커지면서 대비까지 올라간다', (tester) async {
      await openReport(tester);

      // 날짜는 보조 글자다.
      final dateFinder = find.textContaining('년');
      final before = tester.widget<Text>(dateFinder.first).style!;
      expect(before.color, AppColors.textSub);

      await tester.tap(find.text('쉬운 모드'));
      await tester.pumpAndSettle();

      final after = tester.widget<Text>(dateFinder.first).style!;

      expect(after.fontSize!, greaterThan(before.fontSize!));
      expect(after.color, AppColors.ink, reason: '노안에는 크기보다 대비가 더 잘 듣는다');
    });

    testWidgets('다시 누르면 원래대로 돌아온다', (tester) async {
      await openReport(tester);

      final before = styleOf(tester, '오늘의 만남').fontSize;

      await tester.tap(find.text('쉬운 모드'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('쉬운 모드'));
      await tester.pumpAndSettle();

      expect(styleOf(tester, '오늘의 만남').fontSize, before);
    });
  });
}
