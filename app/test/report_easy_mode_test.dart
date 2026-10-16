// G-1 리포트의 쉬운 모드를 확인한다.
//
// 리뷰 미팅 피드백으로 글자 크기 키우기 대신, 크기와 대비를 함께 올리는 모드를
// 넣었다. 읽는 사람은 보호자 본인이고 이 화면에 머무는 동안만 기억한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/report/report_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openReport(
    WidgetTester tester, {
    bool noChanges = false,
    List<CardReview>? cardReviews,
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      final base = await const MockRepository().loadCaregiverEvaluation();
      // 고른 카드는 목 회차에서 읽는다. 화면이 읽기 전에 실제 시간에서 넣어 둔다.
      final session = await const MockRepository().loadVisitSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            visitSessionProvider.overrideWith((ref) async => session),
            // 확인할 제안이 없으면 변경 사항 버튼을 두지 않는다.
            if (noChanges)
              changeProposalProvider.overrideWith(
                (ref) async => const ChangeProposal(
                  sessionId: 'r-001',
                  lifeFactProposals: [],
                  topicProposals: [],
                ),
              ),
            if (cardReviews != null)
              caregiverEvaluationProvider.overrideWith(
                (ref) async => CaregiverEvaluation(
                  reviewId: base.reviewId,
                  sessionId: base.sessionId,
                  conversationSatisfaction: base.conversationSatisfaction,
                  careRecipientReaction: base.careRecipientReaction,
                  cardReviews: cardReviews,
                ),
              ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ReportScreen(reportId: 'r-001'),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    // 변경 제안은 리포트를 띄운 뒤에 읽는다. 목 데이터라 실제 시간을 기다린다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
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

    testWidgets('확인할 제안이 없어 하단 버튼이 없어도 화면 안에 있다', (tester) async {
      await openReport(tester, noChanges: true);

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

  group('대화 카드별 반응', () {
    // 목 회차는 카드 네 장(001, 004, 007, 010)을 골랐다. 목 평가는 001, 004 를
    // 쓰고 평가했고 010 은 쓰지 않았으며 007 에는 답하지 않았다.
    //
    // 쓰고 평가한 카드만 요약을 보여주고, 나머지는 제목 없이 장 수로 알린다.
    // 쓰지 않았다는 답과 답하지 않은 것은 다르게 센다.

    testWidgets('쓰고 평가한 카드만 요약을 보여주고 나머지는 장 수로 알린다', (tester) async {
      await openReport(tester);

      expect(find.textContaining('한복을 주로 만드셨고'), findsOneWidget);
      expect(find.textContaining('옛날 노래를 따라 부르셨다며'), findsOneWidget);
      expect(
        find.textContaining('말수가 줄어들어'),
        findsNothing,
        reason: '답하지 않은 카드에 분석 결과를 붙이지 않는다',
      );
      expect(find.text('다루지 않은 카드 1장, 평가하지 않은 카드 1장'), findsOneWidget);
    });

    testWidgets('쓰지 않았다고 답한 카드는 요약 없이 다루지 않은 카드로 센다', (tester) async {
      await openReport(
        tester,
        cardReviews: const [
          CardReview(cardId: 'card_demo_001', wasUsed: false),
          CardReview(
            cardId: 'card_demo_004',
            wasUsed: true,
            caregiverReaction: CaregiverReaction.positive,
          ),
        ],
      );

      expect(
        find.textContaining('한복을 주로 만드셨고'),
        findsNothing,
        reason: '쓰지 않은 카드에 분석 결과를 붙이지 않는다',
      );
      expect(find.textContaining('옛날 노래를 따라 부르셨다며'), findsOneWidget);
      expect(find.text('다루지 않은 카드 1장, 평가하지 않은 카드 2장'), findsOneWidget);
    });

    testWidgets('하나도 답하지 않았으면 다룬 카드가 없다고 하고 모두 평가하지 않은 카드로 센다', (tester) async {
      await openReport(tester, cardReviews: const []);

      expect(find.text('이번 만남에서 다룬 카드가 없어요.'), findsOneWidget);
      expect(find.text('평가하지 않은 카드 4장'), findsOneWidget);
      expect(find.textContaining('다루지 않은 카드'), findsNothing);
    });

    testWidgets('모두 쓰고 평가했으면 장 수를 적지 않는다', (tester) async {
      await openReport(
        tester,
        cardReviews: [
          for (final id in [
            'card_demo_001',
            'card_demo_004',
            'card_demo_007',
            'card_demo_010',
          ])
            CardReview(
              cardId: id,
              wasUsed: true,
              caregiverReaction: CaregiverReaction.neutral,
            ),
        ],
      );

      expect(find.textContaining('카드 '), findsNothing);
      expect(find.textContaining('말수가 줄어들어'), findsOneWidget);
    });
  });
}
