// G-2 변경 사항 확인 화면을 확인한다.
//
// 주제 제안은 다음 대화 카드에, 생애 정보 제안은 일대기에 반영된다. 반영되는
// 곳이 다르므로 두 구역으로 나눠 보여준다. 주제 카드는 AI 제안이 처음에
// 골라져 있고 보호자가 다른 행동을 고를 수 있다. 이야기 카드는 수정 화면에서
// 제목과 내용을 고칠 수 있다. 반영하면 넓힌 API 7-4 요청 모양으로 저장소에
// 넘긴다. 값은 모두 합성이다.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/report/changes_screen.dart';
import 'package:saerok/features/report/story_edit_screen.dart';

const _topic = TopicProposal(
  proposalId: 'topic_proposal_test_001',
  cardId: 'card_test_001',
  topic: ProposalTopic(
    topicId: 'topic_test_001',
    title: '합성 주제',
    description: '합성 주제 설명',
  ),
  suggestedAction: TopicAction.more,
  reason: '합성 주제 이유',
  reviewStatus: ChangeReviewStatus.pending,
);

/// 넘겨받은 7-4 요청을 기록하는 저장소. 아무 데도 보내지 않는다.
class _RecordingRepository extends MockRepository {
  String? sessionId;
  Map<String, dynamic>? sent;

  @override
  Future<void> submitProposalReview(
    String sessionId,
    ProposalReview review,
  ) async {
    this.sessionId = sessionId;
    sent = review.toJson();
  }
}

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
  double textScale = 1,
  MockRepository repository = const MockRepository(),
}) async {
  // 기준 화면 412 x 917 dp 보다 길게 잡아 스크롤 없이 모두 본다.
  tester.view.physicalSize = const Size(1236, 4800);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mockRepositoryProvider.overrideWithValue(repository),
        changeProposalProvider.overrideWith(
          (ref) async => ChangeProposal(
            sessionId: 'session_test_001',
            lifeFactProposals: facts,
            topicProposals: topics,
          ),
        ),
      ],
      // 이야기 수정 화면을 오가므로 앱과 같은 두 경로를 둔다.
      child: MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: GoRouter(
          initialLocation: AppRoutes.reportChangesOf('report_test_001'),
          routes: [
            GoRoute(
              path: AppRoutes.reportChanges,
              builder: (context, state) =>
                  const ReportChangesScreen(reportId: 'report_test_001'),
            ),
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const Scaffold(body: Text('홈 화면')),
            ),
            GoRoute(
              path: AppRoutes.storyEdit,
              builder: (context, state) =>
                  StoryEditScreen(initial: state.extra! as StoryDraft),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 행동 한 줄. 고른 줄인지 읽으려고 의미 정보를 단 위젯까지 찾는다.
Finder _option(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Semantics)).first;

bool _isSelected(WidgetTester tester, String label) =>
    tester.getSemantics(_option(label)).flagsCollection.isSelected ==
    Tristate.isTrue;

/// 수정 화면에서 [label] 이름표가 붙은 입력칸.
Finder _fieldFinder(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

TextField _field(String label) =>
    _fieldFinder(label).evaluate().single.widget as TextField;

FilledButton _doneButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '수정 완료'));

FilledButton _applyButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

/// 아래 반영 버튼을 누르고 홈으로 갈 때까지 기다린다.
Future<void> _apply(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

/// 첫 이야기 카드의 수정 화면을 연다.
Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('이야기 수정하기'));
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

  group('주제 카드', () {
    testWidgets('위에 제목, 그 아래 설명을 두고 오른쪽 위에 지우기를 둔다', (tester) async {
      await _open(tester, facts: const []);

      final title = tester.getRect(find.text('합성 주제'));
      final description = tester.getRect(find.text('합성 주제 설명'));
      final remove = tester.getRect(find.byTooltip('이 제안 지우기'));

      expect(title.top, lessThan(description.top));
      expect(remove.left, greaterThan(title.right));
      expect(remove.top, lessThan(description.top));
    });

    testWidgets('설명이 없으면 제목만 둔다', (tester) async {
      await _open(
        tester,
        facts: const [],
        topics: const [
          TopicProposal(
            proposalId: 'topic_proposal_test_002',
            cardId: 'card_test_002',
            topic: ProposalTopic(topicId: 'topic_test_002', title: '설명 없는 주제'),
            suggestedAction: TopicAction.less,
            reason: '합성 이유',
            reviewStatus: ChangeReviewStatus.pending,
          ),
        ],
      );

      expect(find.text('설명 없는 주제'), findsOneWidget);
      expect(find.text('합성 주제 설명'), findsNothing);
    });

    testWidgets('행동 셋을 한 줄에 하나씩 둔다', (tester) async {
      await _open(tester, facts: const []);

      final more = tester.getRect(_option('더 자주 꺼내기'));
      final less = tester.getRect(_option('당분간 쉬어가기'));
      final exclude = tester.getRect(_option('제외하기'));

      expect(more.bottom, lessThanOrEqualTo(less.top));
      expect(less.bottom, lessThanOrEqualTo(exclude.top));
    });

    testWidgets('AI 제안이 골라져 있고 그 줄 오른쪽에 AI 제안이라고 적는다', (tester) async {
      await _open(tester, facts: const []);

      expect(_isSelected(tester, '더 자주 꺼내기'), isTrue);
      expect(_isSelected(tester, '당분간 쉬어가기'), isFalse);
      expect(_isSelected(tester, '제외하기'), isFalse);

      final mark = tester.getRect(find.text('AI 제안'));
      expect(find.text('AI 제안'), findsOneWidget);
      expect(tester.getRect(_option('더 자주 꺼내기')).contains(mark.center), isTrue);
      expect(
        mark.left,
        greaterThan(tester.getRect(find.text('더 자주 꺼내기')).right),
      );
    });

    testWidgets('고른 줄 바로 아래에 무엇이 바뀌는지 보여준다', (tester) async {
      await _open(tester, facts: const []);

      final effect = tester.getRect(find.text('다음 추천에서 이 주제의 우선순위를 높여요.'));
      expect(
        effect.top,
        greaterThanOrEqualTo(tester.getRect(_option('더 자주 꺼내기')).bottom),
      );
      expect(
        effect.bottom,
        lessThanOrEqualTo(tester.getRect(_option('당분간 쉬어가기')).top),
      );
      expect(find.text('다음 추천에서 이 주제의 우선순위를 낮춰요.'), findsNothing);
    });

    testWidgets('다른 행동을 누르면 그 줄이 골라지고 설명도 바뀐다', (tester) async {
      await _open(tester, facts: const []);

      await tester.tap(find.text('제외하기'));
      await tester.pumpAndSettle();

      expect(_isSelected(tester, '제외하기'), isTrue);
      expect(_isSelected(tester, '더 자주 꺼내기'), isFalse);
      expect(find.text('앞으로 이 주제는 추천하지 않아요.'), findsOneWidget);
      expect(find.text('다음 추천에서 이 주제의 우선순위를 높여요.'), findsNothing);

      final mark = tester.getRect(find.text('AI 제안'));
      expect(
        tester.getRect(_option('더 자주 꺼내기')).contains(mark.center),
        isTrue,
        reason: '다른 행동을 골라도 AI 제안 표시는 원래 줄에 남는다',
      );
    });

    testWidgets('AI 제안을 읽지 못하면 아무것도 고르지 않는다', (tester) async {
      await _open(
        tester,
        facts: const [],
        topics: const [
          TopicProposal(
            proposalId: 'topic_proposal_test_003',
            cardId: 'card_test_003',
            topic: ProposalTopic(topicId: 'topic_test_003', title: '합성 주제'),
            suggestedAction: null,
            reason: '합성 이유',
            reviewStatus: ChangeReviewStatus.pending,
          ),
        ],
      );

      for (final label in ['더 자주 꺼내기', '당분간 쉬어가기', '제외하기']) {
        expect(_isSelected(tester, label), isFalse, reason: label);
      }
      expect(find.text('AI 제안'), findsNothing);
    });

    testWidgets('AI 제안 이유는 행동 아래에 접혀 있다가 누르면 펼친다', (tester) async {
      await _open(tester, facts: const []);

      expect(find.text('합성 주제 이유'), findsNothing);
      expect(
        tester.getRect(find.text('AI 제안 이유 보기')).top,
        greaterThan(tester.getRect(_option('제외하기')).bottom),
      );

      await tester.tap(find.text('AI 제안 이유 보기'));
      await tester.pumpAndSettle();
      expect(find.text('합성 주제 이유'), findsOneWidget);

      await tester.tap(find.text('AI 제안 이유 보기'));
      await tester.pumpAndSettle();
      expect(find.text('합성 주제 이유'), findsNothing);
    });

    testWidgets('글자를 키워도 넘치지 않고 행동 줄은 48 이상이다', (tester) async {
      await _open(tester, facts: const [], textScale: 1.5);

      expect(tester.takeException(), isNull);
      for (final label in ['더 자주 꺼내기', '당분간 쉬어가기', '제외하기']) {
        expect(
          tester.getSize(_option(label)).height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
    });
  });

  group('일대기에 추가 카드', () {
    testWidgets('새 이야기 표시 옆에 제목, 그 아래 내용과 수정 버튼을 둔다', (tester) async {
      await _open(tester, topics: const []);

      final badge = tester.getRect(find.text('NEW'));
      final title = tester.getRect(find.text('합성 제목'));
      final content = tester.getRect(find.text('합성 이야기 내용'));
      final edit = tester.getRect(find.text('이야기 수정하기'));
      final reason = tester.getRect(find.text('AI 제안 이유 보기'));
      final remove = tester.getRect(find.byTooltip('이 제안 지우기'));

      expect(badge.right, lessThanOrEqualTo(title.left));
      expect(badge.top, lessThan(title.bottom), reason: '제목과 같은 줄에 있다');
      expect(title.bottom, lessThanOrEqualTo(content.top));
      expect(content.bottom, lessThan(edit.top));
      expect(edit.bottom, lessThan(reason.top));
      expect(remove.left, greaterThanOrEqualTo(title.right));
      expect(find.bySemanticsLabel('새 이야기'), findsOneWidget);
    });

    testWidgets('AI 제안 이유는 접혀 있다가 누르면 펼친다', (tester) async {
      await _open(tester, topics: const []);

      expect(find.text('합성 이야기 이유'), findsNothing);

      await tester.tap(find.text('AI 제안 이유 보기'));
      await tester.pumpAndSettle();

      expect(find.text('합성 이야기 이유'), findsOneWidget);
    });

    testWidgets('이야기 수정하기를 누르면 제목과 내용이 채워진 수정 화면이 열린다', (tester) async {
      await _open(tester, topics: const []);

      await _openEditor(tester);

      expect(find.byType(StoryEditScreen), findsOneWidget);
      expect(_field('제목').controller!.text, '합성 제목');
      expect(_field('내용').controller!.text, '합성 이야기 내용');
    });

    testWidgets('수정 완료를 누르면 돌아와 고친 이야기를 보여준다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);

      await tester.enterText(_fieldFinder('제목'), '고친 제목');
      await tester.enterText(_fieldFinder('내용'), '고친 내용');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      expect(find.byType(StoryEditScreen), findsNothing);
      expect(find.text('고친 제목'), findsOneWidget);
      expect(find.text('고친 내용'), findsOneWidget);
      expect(find.text('합성 이야기 내용'), findsNothing);
      expect(find.text('직접 고친 이야기예요.'), findsOneWidget);

      // 제안 이유는 AI 가 처음 제안한 내용에 대한 것이라 그대로다.
      await tester.tap(find.text('AI 제안 이유 보기'));
      await tester.pumpAndSettle();
      expect(find.text('합성 이야기 이유'), findsOneWidget);
    });

    testWidgets('다시 열면 고친 값에서 이어서 고친다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);
      await tester.enterText(_fieldFinder('제목'), '고친 제목');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      await _openEditor(tester);

      expect(_field('제목').controller!.text, '고친 제목');
    });

    testWidgets('원래대로 되돌리면 고친 것으로 치지 않는다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);
      await tester.enterText(_fieldFinder('제목'), '고친 제목');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      await _openEditor(tester);
      await tester.enterText(_fieldFinder('제목'), '합성 제목');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      expect(find.text('합성 제목'), findsOneWidget);
      expect(find.text('직접 고친 이야기예요.'), findsNothing);
    });

    testWidgets('뒤로 가면 고친 값을 버린다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);
      await tester.enterText(_fieldFinder('제목'), '버릴 제목');
      await tester.pump();

      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();

      expect(find.byType(StoryEditScreen), findsNothing);
      expect(find.text('합성 제목'), findsOneWidget);
      expect(find.text('버릴 제목'), findsNothing);
    });
  });

  group('이야기 수정 화면', () {
    testWidgets('제목은 100자까지만 받고 쓴 글자 수를 보여준다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);

      await tester.enterText(_fieldFinder('제목'), '가' * 120);
      await tester.pump();

      expect(_field('제목').controller!.text.length, 100);
      expect(find.text('100/100'), findsOneWidget);
    });

    testWidgets('제목이나 내용이 비면 수정 완료를 누를 수 없다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);

      await tester.enterText(_fieldFinder('제목'), '   ');
      await tester.pump();
      expect(_doneButton(tester).onPressed, isNull);

      await tester.enterText(_fieldFinder('제목'), '합성 제목');
      await tester.enterText(_fieldFinder('내용'), '');
      await tester.pump();
      expect(_doneButton(tester).onPressed, isNull);

      await tester.enterText(_fieldFinder('내용'), '합성 내용');
      await tester.pump();
      expect(_doneButton(tester).onPressed, isNotNull);
    });

    testWidgets('앞뒤 공백은 떼고 돌려준다', (tester) async {
      await _open(tester, topics: const []);
      await _openEditor(tester);

      await tester.enterText(_fieldFinder('제목'), '  고친 제목  ');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      expect(find.text('고친 제목'), findsOneWidget);
    });

    testWidgets('고칠 이야기 없이 주소로 들어오면 안내한다', (tester) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: AppRoutes.storyEditOf('report_test_001'),
        routes: [
          GoRoute(
            path: AppRoutes.storyEdit,
            builder: (context, state) => state.extra is StoryDraft
                ? StoryEditScreen(initial: state.extra! as StoryDraft)
                : const StoryEditMissingView(),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('고칠 이야기를 찾지 못했어요.'), findsOneWidget);
      expect(find.text('수정 완료'), findsNothing);
    });
  });

  group('반영하기', () {
    testWidgets('그대로 반영하면 AI 제안과 원래 이야기를 accepted 로 보낸다', (tester) async {
      final repository = _RecordingRepository();
      await _open(tester, repository: repository);

      await _apply(tester, '이대로 반영하기');

      expect(repository.sessionId, 'session_test_001');
      expect(repository.sent, {
        'lifeFacts': [
          {
            'proposalId': 'life_fact_proposal_test_001',
            'reviewStatus': 'accepted',
            'title': '합성 제목',
            'content': '합성 이야기 내용',
          },
        ],
        'topics': [
          {
            'proposalId': 'topic_proposal_test_001',
            'reviewStatus': 'accepted',
            'action': 'more',
          },
        ],
      });
      expect(find.text('홈 화면'), findsOneWidget);
    });

    testWidgets('고른 행동과 고친 이야기를 보낸다', (tester) async {
      final repository = _RecordingRepository();
      await _open(tester, repository: repository);

      await tester.tap(find.text('제외하기'));
      await tester.pumpAndSettle();
      await _openEditor(tester);
      await tester.enterText(_fieldFinder('제목'), '고친 제목');
      await tester.enterText(_fieldFinder('내용'), '고친 내용');
      await tester.pump();
      await tester.tap(find.text('수정 완료'));
      await tester.pumpAndSettle();

      await _apply(tester, '이대로 반영하기');

      final sent = repository.sent!;
      expect((sent['topics'] as List).single, {
        'proposalId': 'topic_proposal_test_001',
        'reviewStatus': 'accepted',
        'action': 'exclude',
      });
      expect((sent['lifeFacts'] as List).single, {
        'proposalId': 'life_fact_proposal_test_001',
        'reviewStatus': 'accepted',
        'title': '고친 제목',
        'content': '고친 내용',
      });
    });

    testWidgets('뺀 항목은 rejected 만 보내고 남긴 항목은 그대로 보낸다', (tester) async {
      final repository = _RecordingRepository();
      await _open(tester, repository: repository);

      // 주제 카드가 첫 번째다.
      await _remove(tester, 0);
      await _apply(tester, '이대로 반영하기');

      final sent = repository.sent!;
      expect((sent['topics'] as List).single, {
        'proposalId': 'topic_proposal_test_001',
        'reviewStatus': 'rejected',
      });
      expect(
        ((sent['lifeFacts'] as List).single as Map)['reviewStatus'],
        'accepted',
      );
    });

    testWidgets('모두 빼고 마치면 모든 제안을 rejected 로 보낸다', (tester) async {
      final repository = _RecordingRepository();
      await _open(tester, repository: repository);

      await _remove(tester, 0);
      await _remove(tester, 0);
      await _apply(tester, '반영하지 않고 마치기');

      expect(repository.sent, {
        'lifeFacts': [
          {
            'proposalId': 'life_fact_proposal_test_001',
            'reviewStatus': 'rejected',
          },
        ],
        'topics': [
          {'proposalId': 'topic_proposal_test_001', 'reviewStatus': 'rejected'},
        ],
      });
    });

    testWidgets('행동을 고르지 않은 주제가 있으면 반영을 막고 알린다', (tester) async {
      final repository = _RecordingRepository();
      await _open(
        tester,
        repository: repository,
        facts: const [],
        topics: const [
          TopicProposal(
            proposalId: 'topic_proposal_test_003',
            cardId: 'card_test_003',
            topic: ProposalTopic(topicId: 'topic_test_003', title: '합성 주제'),
            suggestedAction: null,
            reason: '합성 이유',
            reviewStatus: ChangeReviewStatus.pending,
          ),
        ],
      );

      expect(find.text('어떻게 할지 고르지 않은 주제가 있어요.'), findsOneWidget);
      expect(_applyButton(tester, '이대로 반영하기').onPressed, isNull);

      await tester.tap(find.text('당분간 쉬어가기'));
      await tester.pumpAndSettle();

      expect(find.text('어떻게 할지 고르지 않은 주제가 있어요.'), findsNothing);
      await _apply(tester, '이대로 반영하기');
      expect(
        ((repository.sent!['topics'] as List).single as Map)['action'],
        'less',
      );
    });

    testWidgets('고르지 않은 주제를 빼면 반영할 수 있다', (tester) async {
      final repository = _RecordingRepository();
      await _open(
        tester,
        repository: repository,
        topics: const [
          TopicProposal(
            proposalId: 'topic_proposal_test_003',
            cardId: 'card_test_003',
            topic: ProposalTopic(topicId: 'topic_test_003', title: '합성 주제'),
            suggestedAction: null,
            reason: '합성 이유',
            reviewStatus: ChangeReviewStatus.pending,
          ),
        ],
      );

      await _remove(tester, 0);

      expect(_applyButton(tester, '이대로 반영하기').onPressed, isNotNull);
    });
  });
}
