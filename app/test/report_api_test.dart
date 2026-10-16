// 회차 상태와 리포트 API(`api-spec.md` 5-4, 6-3, 6-4, 7-1 ~ 7-4)의 경로와
// 응답 읽기를 확인한다. 값은 모두 합성이다.

import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/report_api.dart';

import 'fake_report_server.dart';

void main() {
  group('가장 최근 회차(5-4)', () {
    test('한 건만 달라고 하고 상태와 분석 작업을 읽는다', () async {
      final server = FakeReportServer(
        sessions: {
          'p1': [
            FakeReportServer.session(
              id: 's2',
              status: 'processing',
              analysisId: 'a2',
            ),
            FakeReportServer.session(id: 's1', status: 'completed'),
          ],
        },
      );

      final latest = await server.api.latestSession('p1');

      expect(server.requests.single.path, '/api/v1/profiles/p1/visit-sessions');
      expect(latest!.sessionId, 's2');
      expect(latest.status, VisitStatus.processing);
      expect(latest.analysisId, 'a2');
    });

    test('회차가 없으면 null 이다', () async {
      final server = FakeReportServer();
      expect(await server.api.latestSession('p1'), isNull);
    });

    test('면회한 날은 시작 시각의 한국 날짜다', () {
      final session = VisitProgress.fromJson(
        FakeReportServer.session(
          id: 's1',
          status: 'completed',
          startedAt: '2026-10-13T15:30:00+00:00',
        ),
      );
      expect(session.visitDate, '2026-10-14');
    });

    test('모르는 상태는 null 로 둔다', () async {
      final server = FakeReportServer(
        sessions: {
          'p1': [FakeReportServer.session(id: 's1', status: 'somethingNew')],
        },
      );
      expect((await server.api.latestSession('p1'))!.status, isNull);
    });
  });

  test('리포트 회차에 고른 카드를 최근 회차 목록(5-4)에서 찾는다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [
          FakeReportServer.session(id: 's2', status: 'processing'),
          FakeReportServer.session(id: 's1', status: 'completed'),
        ],
      },
    );

    expect(await server.api.selectedCardIds('p1', 's1'), [
      'card-1',
      'card-2',
      'card-3',
    ]);
    expect(
      await server.api.selectedCardIds('p1', 'no-such'),
      isNull,
      reason: '목록에 없으면 고른 카드를 지어내지 않는다',
    );
  });

  test('분석 작업 상태(6-3)를 읽는다', () async {
    final server = FakeReportServer(
      analyses: {
        'a1': ['transcribing'],
      },
    );
    expect(await server.api.analysis('a1'), AnalysisStatus.transcribing);
    expect(server.requests.single.path, '/api/v1/speech-analyses/a1');
  });

  test('리포트 기록(7-1)은 회차 ID 로 연다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
      reports: {'s1': FakeReportServer.report(sessionId: 's1')},
    );

    final items = await server.api.reports('p1');

    expect(items.single.reportId, 's1');
    expect(items.single.title, '재봉 일 이야기를 나눈 날');
    expect(items.single.mood, VisitMood.good);
  });

  group('리포트(7-2)', () {
    test('본문, 카드 제목과 사진을 화면이 쓰는 이름으로 읽는다', () async {
      final server = FakeReportServer(
        reports: {
          's1': FakeReportServer.report(
            sessionId: 's1',
            imageUrl: 'https://example.test/visit.jpg',
          ),
        },
      );

      final report = await server.api.report('s1');

      expect(server.requests.single.path, '/api/v1/visit-sessions/s1/report');
      expect(report.reportId, 's1');
      expect(report.summaryText, '오늘은 재봉 일을 하시던 시절 이야기를 나눴어요.');
      expect(report.cardSummaries.first.topicTitle, '수선집 시절');
      expect(report.photoUrl, 'https://example.test/visit.jpg');
    });

    test('사진 없이 한 면회는 사진 주소가 없다', () async {
      final server = FakeReportServer(
        reports: {'s1': FakeReportServer.report(sessionId: 's1')},
      );
      final report = await server.api.report('s1');
      expect(report.photoId, isNull);
      expect(report.photoUrl, isNull);
    });

    test('응답 모양이 다르면 성공으로 넘기지 않는다', () async {
      final server = FakeReportServer(
        reports: {
          's1': {...FakeReportServer.report(sessionId: 's1'), 'body': null},
        },
      );
      await expectLater(
        server.api.report('s1'),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });
  });

  test('카드마다 남긴 답(6-4)을 읽는다', () async {
    final server = FakeReportServer(
      evaluations: {'s1': FakeReportServer.evaluation('s1')},
    );

    final reviews = await server.api.cardReviews('s1');

    expect(server.requests.single.path, '/api/v1/visit-sessions/s1/evaluation');
    expect(reviews.first.caregiverReaction, CaregiverReaction.positive);
    expect(reviews.last.wasUsed, isFalse);
  });

  test('변경 제안 검토(7-4)를 보낸다', () async {
    final server = FakeReportServer(
      proposals: {'s1': FakeReportServer.proposal('s1')},
    );

    await server.api.reviewProposals(
      's1',
      const ProposalReview(
        lifeFacts: [
          LifeFactReview.accepted(
            proposalId: 'proposal-1',
            title: '한복',
            content: '한복을 주로 만드셨어요.',
          ),
        ],
        topics: [],
      ),
    );

    final sent = server.requests.single;
    expect(sent.method, 'POST');
    expect(sent.path, '/api/v1/visit-sessions/s1/proposals/review');
    expect(sent.body, {
      'lifeFacts': [
        {
          'proposalId': 'proposal-1',
          'reviewStatus': 'accepted',
          'title': '한복',
          'content': '한복을 주로 만드셨어요.',
        },
      ],
      'topics': <Object>[],
    });
  });

  test('이미 확인한 변경 제안은 그렇게 알린다', () {
    expect(
      reportFailureMessage(
        const ApiServerFailure(
          statusCode: 409,
          errorCode: 'PROPOSAL_ALREADY_REVIEWED',
        ),
      ),
      '이미 확인을 마친 변경 사항이에요.',
    );
    expect(
      reportFailureMessage(const ApiNetworkFailure()),
      '서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.',
    );
  });
}
