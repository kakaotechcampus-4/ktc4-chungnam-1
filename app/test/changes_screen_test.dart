// G-2 변경 사항 확인 화면의 구역 나누기를 확인한다.
//
// 주제 제안은 다음 대화 카드에, 생애 정보 제안은 일대기에 반영된다. 반영되는
// 곳이 다르므로 두 구역으로 나눠 보여준다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/report/changes_screen.dart';

const _topic = TopicProposal(
  proposalId: 'topic_proposal_test_001',
  cardId: 'card_test_001',
  topic: ProposalTopic(topicId: 'topic_test_001', title: '합성 주제'),
  suggestedAction: TopicAction.more,
  reason: '합성 주제 이유',
  reviewStatus: ChangeReviewStatus.pending,
);

const _fact = LifeFactProposal(
  proposalId: 'life_fact_proposal_test_001',
  title: '합성 제목',
  content: '합성 이야기 내용',
  reason: '합성 이야기 이유',
  reviewStatus: ChangeReviewStatus.pending,
);

Future<void> _open(
  WidgetTester tester, {
  List<TopicProposal> topics = const [_topic],
  List<LifeFactProposal> facts = const [_fact],
}) async {
  // 기준 화면 412 x 917 dp 보다 길게 잡아 스크롤 없이 모두 본다.
  tester.view.physicalSize = const Size(1236, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        changeProposalProvider.overrideWith(
          (ref) async => ChangeProposal(
            sessionId: 'session_test_001',
            lifeFactProposals: facts,
            topicProposals: topics,
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const ReportChangesScreen(reportId: 'report_test_001'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// [index] 번째 카드의 지우기 버튼을 누른다.
Future<void> _remove(WidgetTester tester, int index) async {
  await tester.tap(find.byTooltip('이 제안 지우기').at(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('대화 주제와 일대기에 추가로 나누고 주제를 먼저 둔다', (tester) async {
    await _open(tester);

    final topicHeader = tester.getTopLeft(find.text('대화 주제'));
    final topicCard = tester.getTopLeft(find.text('합성 주제'));
    final factHeader = tester.getTopLeft(find.text('일대기에 추가'));
    final factCard = tester.getTopLeft(find.text('합성 이야기 내용'));

    expect(topicHeader.dy, lessThan(topicCard.dy));
    expect(topicCard.dy, lessThan(factHeader.dy), reason: '주제 카드는 주제 구역 안에 있다');
    expect(factHeader.dy, lessThan(factCard.dy));
  });

  testWidgets('구역마다 어디에 반영되는지 알린다', (tester) async {
    await _open(tester);

    expect(find.text('다음 대화 카드를 만들 때 반영해요.'), findsOneWidget);
    expect(find.text('남겨두신 이야기를 일대기에 더해요.'), findsOneWidget);
  });

  testWidgets('제안이 없는 구역은 보이지 않는다', (tester) async {
    await _open(tester, facts: const []);

    expect(find.text('대화 주제'), findsOneWidget);
    expect(find.text('일대기에 추가'), findsNothing);
  });

  testWidgets('한 구역의 제안을 모두 빼면 그 구역만 사라진다', (tester) async {
    await _open(tester);

    // 주제 카드가 첫 번째다.
    await _remove(tester, 0);

    expect(find.text('대화 주제'), findsNothing);
    expect(find.text('일대기에 추가'), findsOneWidget);
  });

  testWidgets('모두 빼면 빈 상태와 반영하지 않고 마치기를 보여준다', (tester) async {
    await _open(tester);

    await _remove(tester, 0);
    await _remove(tester, 0);

    expect(find.text('대화 주제'), findsNothing);
    expect(find.text('일대기에 추가'), findsNothing);
    expect(find.text('모두 지우셨어요.\n이대로 마쳐도 괜찮아요.'), findsOneWidget);
    expect(find.text('반영하지 않고 마치기'), findsOneWidget);
  });
}
