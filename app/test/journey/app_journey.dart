// 앱 전체 여정. 실제 앱을 띄우고 보호자가 누르는 순서대로 화면을 지나간다.
//
// 같은 여정을 두 곳에서 부른다.
// - `test/app_journey_test.dart`: `flutter test` 로 호스트에서 화면 없이 돈다.
//   지금 develop 의 GitHub Actions 에는 `flutter test` 를 도는 작업이 없다.
// - `integration_test/app_journey_test.dart`: 연결한 기기나 에뮬레이터에서
//   `flutter test integration_test/app_journey_test.dart` 로 돈다.
//
// 바꾸는 것은 서버와 기기 경계뿐이다(`journey_harness.dart`). 실제 마이크,
// STT, 리포트 모델, 운영 서버와 TalkBack 은 확인하지 않는다(`app/README.md`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/features/cards/cards_screen.dart' show cardSelectLabel;
import 'package:saerok/features/report/report_text.dart'
    show splitIntoParagraphs;
import 'package:saerok/widgets/app_surfaces.dart';

import 'journey_harness.dart';
import 'journey_server.dart';

const _homeCardsButton = '오늘의 대화카드 받기';

/// 이야기 제안을 승인하면서 보호자가 고친 내용.
const _correctedContent = '두루마기를 주로 지으셨어요.';

/// 일대기에서 다시 고친 이야기 제목.
const _correctedTitle = '두루마기 짓던 시절';

/// 제목을 고친 뒤 이어서 고친 이야기 내용.
const _correctedAgainContent = '명절 앞에는 두루마기를 밤새 지으셨어요.';

/// 카드 묶음을 만들어 달라는 요청(2-5) 수.
int _cardRequests(JourneyServer server) => server.requests
    .where((r) => r.method == 'POST' && r.path.endsWith('/card-generations'))
    .length;

Finder _cardToggle(String title) => find.byWidgetPredicate(
  (w) => w is SelectionToggle && w.label == cardSelectLabel(title),
);

/// 홈에서 카드를 받아 [titles] 를 고르고 녹음 화면에서 녹음을 시작한다.
///
/// 녹음 전 안내(E-1)의 `네, 좋아요` 가 녹음 전에 보호자가 승인하는 단계다.
/// 회차마다 받는 동의 체크는 팀 결정(2026-10-13)으로 없다.
Future<void> _startVisit(JourneyDriver app) async {
  await app.tap(find.text('대화 시작하기'));
  await app.tap(find.text('사진 없이 시작할게요'));

  await app.waitFor(find.text('네, 좋아요'));
  expect(find.text('소중한 대화 내용을\n놓치지 않게 녹음할게요'), findsOneWidget);
  expect(find.text('녹음은 리포트를 만드는 데만 쓰고\n분석이 끝나면 바로 지워요.'), findsOneWidget);
  final sessionsBefore = app.server.sessionSetIds.length;
  final startsBefore = app.recorder.starts;
  expect(find.text('녹음 중이에요'), findsNothing, reason: '승인 전에는 녹음하지 않는다');
  expect(app.recorder.starts, startsBefore, reason: '승인 전에는 마이크를 켜지 않는다');

  await app.tap(find.text('네, 좋아요'));
  await app.waitFor(find.text('녹음 중이에요'));
  expect(app.server.sessionSetIds, hasLength(sessionsBefore + 1));
  expect(app.recorder.starts, startsBefore + 1);
}

Future<void> _pickCards(JourneyDriver app, List<String> titles) async {
  for (final title in titles) {
    await app.tap(_cardToggle(title));
  }
  await app.waitFor(find.text('${titles.length}개 선택함'));
}

/// 녹음을 끝내고 소감을 남겨 녹음까지 보낸 뒤 홈으로 돌아온다.
Future<void> _finishVisit(JourneyDriver app) async {
  // 글자 위의 둥근 버튼이 누르는 자리다.
  expect(find.text('만남 끝내기'), findsOneWidget);
  await app.tap(find.byIcon(Icons.stop));
  await app.waitFor(find.text('만남을 끝낼까요?'));
  // 참여자 수는 기본 2명 그대로 둔다.
  await app.tap(find.text('끝내기'));

  await app.waitFor(find.text('오늘 만남은\n어떠셨나요?'));
  // 첫 카드는 썼고 좋았다고 답한다. 두 번째 카드는 답하지 않는다.
  await app.tap(find.text('좋았어요').first);
  await app.tap(find.text('4'));
  await app.tap(find.text('기뻐하셨어요'));
  await app.tap(find.text('리포트 만들기'));

  await app.waitFor(find.text('제출 완료!'));
  await app.tap(find.text('홈으로'));
  await app.waitFor(find.text(_homeCardsButton));
}

/// 앱을 켜고 첫 면회를 마쳐 홈으로 돌아온다. 첫 카드 묶음은 온보딩에서 받았다.
Future<JourneyDriver> _firstVisit(
  WidgetTester tester,
  JourneyServer server,
) async {
  final app = await JourneyDriver.launch(tester, server);
  await app.waitFor(find.text(_homeCardsButton), maxSteps: 300);
  // 서버(2-1, 2-3)의 어르신을 불러와 이름을 보여준다.
  await app.waitFor(find.textContaining('김새록'));

  await app.tap(find.text(_homeCardsButton));
  await app.waitFor(find.text('오늘의 대화 카드'));
  final firstSet = server.setIds.single;
  final titles = server.cardTitlesOf(firstSet).take(2).toList();
  await _pickCards(app, titles);
  await _startVisit(app);
  expect(server.sessionSetIds.single, firstSet);

  await _finishVisit(app);
  final audio = server.requests.lastWhere(
    (r) => r.path.endsWith('/speech-analyses'),
  );
  expect(audio.body, {'participantCount': '2', 'audio': true});
  expect(
    server.requests.indexWhere((r) => r.path.endsWith('/evaluation')),
    lessThan(server.requests.indexOf(audio)),
    reason: '소감을 먼저 저장하고 녹음을 보낸다',
  );
  return app;
}

/// 화면에 보이는 글자를 모두 모은다.
List<String> _visibleTexts(WidgetTester tester) => [
  for (final widget in tester.widgetList<Text>(find.byType(Text)))
    widget.data ?? widget.textSpan?.toPlainText() ?? '',
];

void defineAppJourneyTests() {
  group('앱 전체 여정', () {
    testWidgets('카드 선택, 녹음 제출, 리포트, 이야기 정정, 다음 대화 준비와 두 번째 면회', (tester) async {
      final server = JourneyServer()..holdAnalyses = true;
      final app = await _firstVisit(tester, server);

      // 분석 상태: 만드는 중 → 도착.
      await app.waitFor(find.text('리포트를 만들고 있어요'));
      expect(find.text('리포트가 도착했어요'), findsNothing);
      server.holdAnalyses = false;
      await app.waitFor(find.text('리포트가 도착했어요'));
      await app.tap(find.text('리포트가 도착했어요'));

      // 리포트
      await app.waitFor(find.text(journeyReportTitle));
      expect(find.text(journeyReportBody), findsOneWidget);
      expect(find.text(journeyCardSummary), findsOneWidget);
      expect(find.text('평가하지 않은 카드 1장'), findsOneWidget);

      // 변경 사항 확인: AI 가 제안한 이야기의 내용을 고쳐 승인한다.
      await app.tap(find.text('변경 사항 확인하기'));
      await app.waitFor(find.text(journeyProposalTitle));
      expect(server.lifeFacts, isEmpty, reason: '승인 전에는 일대기에 넣지 않는다');
      await app.tap(find.text('이야기 수정하기'));
      await app.waitFor(find.text('수정 완료'));
      await tester.enterText(find.byType(TextField).at(1), _correctedContent);
      await app.tap(find.text('수정 완료'));
      await app.waitFor(find.text('직접 고친 이야기예요.'));
      await app.tap(find.text('이대로 반영하기'));
      await app.waitFor(find.text(_homeCardsButton));

      final review = server.requests.lastWhere(
        (r) => r.path.endsWith('/proposals/review'),
      );
      final reviewed = ((review.body! as Map)['lifeFacts'] as List).single;
      expect(reviewed, {
        'proposalId': (reviewed as Map)['proposalId'],
        'reviewStatus': 'accepted',
        'title': journeyProposalTitle,
        'content': _correctedContent,
      });
      expect(server.lifeFacts.single['content'], _correctedContent);
      expect(find.text('리포트가 도착했어요'), findsNothing, reason: '확인을 마친 알림');

      // 다음 대화 준비 1: 지난 묶음은 평가까지 끝나 서버가 새로 만든다.
      await app.tap(find.text(_homeCardsButton));
      await app.waitFor(find.text('오늘의 대화 카드'));
      expect(server.setIds, hasLength(2));
      expect(
        find.text(journeyProposalTitle),
        findsOneWidget,
        reason: '승인한 이야기로 만든 카드가 새 묶음에 있다',
      );
      expect(find.text('대화 시작하기'), findsOneWidget);
      await app.back();
      await app.waitFor(find.text(_homeCardsButton));

      // 사실 정정: 카드를 받은 뒤 일대기에서 이야기 제목을 고친다.
      await app.tap(find.text('일대기'));
      await app.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '일대기 책 펼치기',
        ),
      );
      await app.tap(find.text(journeyProposalTitle));
      await app.tap(find.byTooltip('이야기 수정'));
      await app.waitFor(find.text('수정 완료'));
      final requestsBeforeCorrections = _cardRequests(server);
      await tester.enterText(find.byType(TextField).at(0), _correctedTitle);
      await app.tap(find.text('수정 완료'));
      await app.waitFor(find.text('이야기를 고쳤어요.'));
      expect(server.lifeFacts.single['title'], _correctedTitle);

      // 같은 이야기를 한 번 더 고친다. 정정은 바로 저장하고 묶음은 다시 만들지 않는다.
      await app.tap(find.byTooltip('이야기 수정'));
      await app.waitFor(find.text('수정 완료'));
      await tester.enterText(
        find.byType(TextField).at(1),
        _correctedAgainContent,
      );
      await app.tap(find.text('수정 완료'));
      await app.waitUntilGone(find.text('수정 완료'));
      expect(server.lifeFacts.single['title'], _correctedTitle);
      expect(server.lifeFacts.single['content'], _correctedAgainContent);
      expect(
        server.requests.where(
          (r) => r.method == 'PATCH' && r.path.contains('/life-facts/'),
        ),
        hasLength(2),
      );
      expect(
        _cardRequests(server),
        requestsBeforeCorrections,
        reason: '정정할 때마다 묶음을 다시 만들지 않는다',
      );
      for (var i = 0; i < 6; i++) {
        if (find.text(_homeCardsButton).evaluate().isNotEmpty) break;
        await app.back();
      }
      await app.waitFor(find.text(_homeCardsButton));

      // 다음 대화 준비 2: 고친 뒤의 묶음은 볼 수만 있고 시작할 수 없다.
      await app.tap(find.text(_homeCardsButton));
      await app.waitFor(find.text('다음 대화 준비하기'));
      expect(find.textContaining('어르신 정보가 바뀌었어요'), findsOneWidget);
      expect(find.text('대화 시작하기'), findsNothing);
      expect(_cardToggle(journeyProposalTitle), findsNothing);
      expect(server.setIds, hasLength(2), reason: '누르기 전에는 다시 만들지 않는다');
      expect(_cardRequests(server), requestsBeforeCorrections);

      await app.tap(find.text('다음 대화 준비하기'));
      await app.waitFor(find.text('대화 시작하기'));
      expect(server.setIds, hasLength(3), reason: '묶음 전체를 한 번 다시 만든다');
      expect(
        _cardRequests(server),
        requestsBeforeCorrections + 1,
        reason: '두 번 고친 것을 모아 한 번만 요청한다',
      );
      expect(find.text(_correctedTitle), findsOneWidget);
      expect(find.text(journeyProposalTitle), findsNothing);

      // 두 번째 면회는 새 묶음으로 시작한다.
      final secondTitles = [_correctedTitle];
      await _pickCards(app, secondTitles);
      await _startVisit(app);
      expect(server.sessionSetIds, [server.setIds[0], server.setIds[2]]);
      expect(
        server.count('POST', '/api/v1/visit-sessions'),
        2,
        reason: '고친 뒤의 묶음(두 번째)으로는 회차를 만들지 않았다',
      );

      // 녹음 파일을 닫고 소감 화면까지 간 뒤 마친다. 녹음 중에 정리되는 경우는
      // `visit_recording_test.dart` 가 따로 확인한다.
      await app.tap(find.byIcon(Icons.stop));
      await app.tap(find.text('끝내기'));
      await app.waitFor(find.text('오늘 만남은\n어떠셨나요?'));
      expect(
        find.text(_correctedTitle),
        findsOneWidget,
        reason: '새 묶음의 카드를 평가한다',
      );

      await app.close();
    });

    testWidgets('분석이 실패하면 홈에서 다시 요청하고 리포트를 받는다', (tester) async {
      final server = JourneyServer(plans: [AnalysisPlan.failed]);
      final app = await _firstVisit(tester, server);

      await app.waitFor(find.text('리포트를 만들지 못했어요'));
      expect(find.text('눌러서 분석 다시 요청하기'), findsOneWidget);
      expect(find.text('리포트가 도착했어요'), findsNothing);

      await app.tap(find.text('리포트를 만들지 못했어요'));
      await app.waitFor(find.text('리포트를 다시 만들고 있어요'));
      expect(
        server.requests.where((r) => r.path.endsWith('/retry')),
        hasLength(1),
      );
      expect(
        server.responses.singleWhere((r) => r.path.endsWith('/retry')).status,
        202,
      );
      await app.tap(find.text('홈으로'));

      await app.waitFor(find.text('리포트가 도착했어요'));
      await app.tap(find.text('리포트가 도착했어요'));
      await app.waitFor(find.text(journeyReportTitle));

      await app.close();
    });

    testWidgets('화자를 확인하지 못한 리포트는 안내만 보여주고 해석과 제안을 두지 않는다', (tester) async {
      final server = JourneyServer(plans: [AnalysisPlan.speakerUnverified]);
      final app = await _firstVisit(tester, server);

      await app.waitFor(find.text('리포트가 도착했어요'));
      await app.tap(find.text('리포트가 도착했어요'));

      await app.waitFor(find.text(unverifiedSpeakerTitle));
      // 리포트 화면은 본문을 문장 단위로 나눠 보여준다. 고정 안내를 고치지 않는다.
      for (final paragraph in splitIntoParagraphs(unverifiedSpeakerBody)) {
        expect(find.text(paragraph), findsOneWidget);
      }
      expect(find.text(journeyReportTitle), findsNothing);
      expect(find.text(journeyCardSummary), findsNothing);
      // 보호자는 첫 카드를 썼다고 답했다. 요약이 없다고 다룬 카드가 없다고 하지 않는다.
      expect(find.text('이번 만남에서 다룬 카드가 없어요.'), findsNothing);
      expect(find.text('이번 리포트에는 카드별 요약이 없어요.'), findsOneWidget);
      expect(find.text('변경 사항 확인하기'), findsNothing, reason: '이야기와 주제 제안이 없다');

      final texts = _visibleTexts(tester);
      expect(
        texts.where((t) => RegExp(r'\d+\s*(점|%)').hasMatch(t)),
        isEmpty,
        reason: '점수나 비율 같은 수치를 만들지 않는다',
      );

      await app.close();
    });
  });
}
