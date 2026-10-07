// 경로가 모두 실제 화면으로 이어지는지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/report/report_screen.dart';
import 'package:saerok/features/report/story_edit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 화면 하나를 그 경로로 띄운다.
  Future<void> openAt(
    WidgetTester tester,
    String location, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = buildRouter();
    router.go(location);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  const locations = <String, String>{
    AppRoutes.login: '로그인',
    AppRoutes.signup: '회원가입',
    AppRoutes.onboarding: '온보딩',
    AppRoutes.profileCreate: '환자 정보 입력',
    AppRoutes.home: '홈',
    AppRoutes.cards: '대화 카드',
    AppRoutes.visitPhoto: '면회 전 사진',
    AppRoutes.visitRecord: '녹음',
    AppRoutes.visitAddCards: '대화 카드 추가',
    AppRoutes.visitReview: '보호자 소감',
    AppRoutes.visitReviewDone: '보호자 위로',
    AppRoutes.profile: '프로필 설정',
    AppRoutes.reports: '리포트 기록',
    AppRoutes.album: '일대기',
  };

  group('경로', () {
    for (final entry in locations.entries) {
      testWidgets('${entry.value} 화면이 뜬다', (tester) async {
        await openAt(tester, entry.key);
        expect(tester.takeException(), isNull);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }

    testWidgets('리포트는 reportId 를 받는다', (tester) async {
      await openAt(tester, AppRoutes.reportOf('report_demo_001'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('변경 사항 확인도 reportId 를 받는다', (tester) async {
      await openAt(tester, AppRoutes.reportChangesOf('report_demo_001'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('변경 사항 확인에서 이야기 수정하기를 누르면 수정 화면이 열린다', (tester) async {
      // 이야기 수정 경로가 `/report/:reportId` 와 겹치면 리포트 화면이 열린다.
      // 경로만 보므로 asset 을 읽지 않고 합성 제안 하나를 바로 넣는다.
      await openAt(
        tester,
        AppRoutes.reportChangesOf('report_demo_001'),
        overrides: [
          changeProposalProvider.overrideWith(
            (ref) async => const ChangeProposal(
              sessionId: 'session_test_001',
              topicProposals: [],
              lifeFactProposals: [
                LifeFactProposal(
                  proposalId: 'life_fact_proposal_test_001',
                  title: '합성 제목',
                  content: '합성 내용',
                  reason: '합성 이유',
                  reviewStatus: ChangeReviewStatus.pending,
                ),
              ],
            ),
          ),
        ],
      );

      await tester.tap(find.text('이야기 수정하기'));
      await tester.pumpAndSettle();

      expect(find.byType(StoryEditScreen), findsOneWidget);
      expect(find.byType(ReportScreen), findsNothing);
    });

    testWidgets('이야기 수정 주소로 바로 들어오면 안내만 보여준다', (tester) async {
      await openAt(tester, AppRoutes.storyEditOf('report_demo_001'));

      expect(tester.takeException(), isNull);
      expect(find.byType(StoryEditMissingView), findsOneWidget);
    });

    testWidgets('기록에서 연 리포트에는 변경 사항 버튼이 없다', (tester) async {
      await openAt(tester, AppRoutes.reportOf('report_demo_001'));
      expect(
        find.text('변경 사항 확인하기'),
        findsOneWidget,
        reason: '알림에서 들어오면 아직 확인 전이다',
      );

      await openAt(
        tester,
        AppRoutes.reportOf('report_demo_001', fromHistory: true),
      );
      expect(find.text('변경 사항 확인하기'), findsNothing, reason: '이미 반영을 마친 회차다');
    });

    testWidgets('보류된 일대기는 안내를 보여준다', (tester) async {
      await openAt(tester, AppRoutes.album);
      expect(find.text('화면 설계 중입니다'), findsOneWidget);
    });

    testWidgets('없는 경로는 오류 안내를 보여준다', (tester) async {
      await openAt(tester, '/there-is-no-such-screen');
      expect(find.textContaining('찾을 수 없는 화면'), findsOneWidget);
    });
  });
}
