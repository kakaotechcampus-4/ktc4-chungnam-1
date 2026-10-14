// 회차 상태, 분석 상태와 리포트 API(`api-spec.md` 5-4, 6-3, 6-4, 7-1 ~ 7-4)를
// 흉내 내는 가짜 서버다.
//
// 로그인한 상태로 홈을 띄우면 가장 최근 회차를 서버에 묻는다. 실제 주소로
// 요청이 나가지 않도록 이 서버를 `reportApiProvider` 에 넣는다. 값은 모두
// 합성이다.

import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/report_api.dart';

class FakeReportServer {
  FakeReportServer({
    Map<String, List<Map<String, Object?>>>? sessions,
    Map<String, List<String>>? analyses,
    Map<String, Map<String, Object?>>? reports,
    Map<String, Map<String, Object?>>? evaluations,
    Map<String, Map<String, Object?>>? proposals,
  }) : sessions = sessions ?? {},
       analyses = analyses ?? {},
       reports = reports ?? {},
       evaluations = evaluations ?? {},
       proposals = proposals ?? {};

  /// 프로필마다의 회차. 최근 회차가 앞이다. 명세의 VisitSession 모양이다.
  final Map<String, List<Map<String, Object?>>> sessions;

  /// 분석 작업마다 물을 때 차례로 돌려줄 `status`. 마지막 값은 계속 돌려준다.
  final Map<String, List<String>> analyses;

  /// 회차마다의 리포트(VisitReport).
  final Map<String, Map<String, Object?>> reports;

  /// 회차마다의 보호자 평가(CaregiverEvaluation).
  final Map<String, Map<String, Object?>> evaluations;

  /// 회차마다의 변경 제안(ChangeProposal).
  final Map<String, Map<String, Object?>> proposals;

  /// 받은 요청을 차례대로 남긴다. 본문은 JSON 으로 읽은 값이다.
  final requests = <({String method, String path, Object? body})>[];

  /// 정해 두면 그 요청에 이 오류로 답한다. 키는 `METHOD path` 다.
  final failures = <String, ({int status, String errorCode})>{};

  /// 연결이 끊긴 것처럼 모든 요청을 실패시킨다.
  bool offline = false;

  ReportApi get api => ReportApi(
    ApiClient(
      authorization: () => 'Bearer fake-token',
      baseUrl: 'http://api.test',
      client: MockClient(_handle),
    ),
  );

  Override get override => reportApiProvider.overrideWithValue(api);

  /// [path] 로 받은 요청 수.
  int count(String path) => requests.where((r) => r.path == path).length;

  Future<http.Response> _handle(http.Request request) async {
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    final path = request.url.path;
    requests.add((method: request.method, path: path, body: body));
    if (offline) throw http.ClientException('오프라인');

    final failure = failures['${request.method} $path'];
    if (failure != null) return _error(failure.status, failure.errorCode);

    final s = request.url.pathSegments;
    // /api/v1/profiles/{id}/visit-sessions, /api/v1/profiles/{id}/reports
    if (s.length == 5 && s[2] == 'profiles') {
      final profileId = s[3];
      if (s[4] == 'visit-sessions') {
        final limit = int.parse(request.url.queryParameters['limit'] ?? '20');
        return _json({
          'schemaVersion': 1,
          'sessions': (sessions[profileId] ?? const []).take(limit).toList(),
        });
      }
      return _json({
        'schemaVersion': 1,
        'reports': [
          for (final session in sessions[profileId] ?? const [])
            if (reports[session['sessionId']] case final r?)
              {
                'sessionId': r['sessionId'],
                'title': r['title'],
                'visitDate': r['visitDate'],
                'mood': r['mood'],
              },
        ],
      });
    }

    // /api/v1/speech-analyses/{id}
    if (s.length == 4 && s[2] == 'speech-analyses') {
      final statuses = analyses[s[3]];
      if (statuses == null) return _error(404, 'SPEECH_ANALYSIS_NOT_FOUND');
      final status = statuses.length > 1
          ? statuses.removeAt(0)
          : statuses.single;
      return _json({
        'schemaVersion': 1,
        'analysisId': s[3],
        'sessionId': 'session-of-${s[3]}',
        'status': status,
        'errorCode': null,
      });
    }

    // /api/v1/visit-sessions/{id}/...
    if (s.length >= 5 && s[2] == 'visit-sessions') {
      final sessionId = s[3];
      switch (s.sublist(4).join('/')) {
        case 'report':
          final report = reports[sessionId];
          return report == null
              ? _error(404, 'REPORT_NOT_FOUND')
              : _json(report);
        case 'evaluation':
          final evaluation = evaluations[sessionId];
          return evaluation == null
              ? _error(404, 'EVALUATION_NOT_FOUND')
              : _json(evaluation);
        case 'proposals':
          final proposal = proposals[sessionId];
          return proposal == null
              ? _error(404, 'REPORT_NOT_FOUND')
              : _json(proposal);
        case 'proposals/review':
          final proposal = proposals[sessionId]!;
          return _json(proposal);
      }
    }
    return _error(404, 'NOT_FOUND');
  }

  /// 명세의 VisitSession 하나를 만든다.
  static Map<String, Object?> session({
    required String id,
    String profileId = 'p1',
    required String status,
    String? analysisId,
    String startedAt = '2026-10-13T14:00:00+09:00',
  }) => {
    'schemaVersion': 1,
    'sessionId': id,
    'profileId': profileId,
    'setId': 'set-1',
    'selectedCardIds': ['card-1', 'card-2'],
    'sessionStatus': status,
    'photoId': null,
    'participantCount': analysisId == null ? null : 2,
    'startedAt': startedAt,
    'analysisId': analysisId,
  };

  /// 명세의 VisitReport 하나를 만든다.
  static Map<String, Object?> report({
    required String sessionId,
    String title = '재봉 일 이야기를 나눈 날',
    String body = '오늘은 재봉 일을 하시던 시절 이야기를 나눴어요.',
    String visitDate = '2026-10-13',
    String mood = 'good',
    String? imageUrl,
  }) => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'title': title,
    'body': body,
    'visitDate': visitDate,
    'mood': mood,
    'photo': imageUrl == null
        ? null
        : {
            'photoId': 'visit-photo-1',
            'imageUrl': imageUrl,
            'imageUrlExpiresAt': '2026-10-13T15:00:00+09:00',
          },
    'cardSummaries': [
      {
        'cardId': 'card-1',
        'cardTitle': '수선집 시절',
        'summary': '한복을 주로 만드셨다고 하셨어요.',
      },
      {'cardId': 'card-2', 'cardTitle': '고향 마을', 'summary': '다루지 못했어요.'},
    ],
    'generatedAt': '2026-10-13T14:30:00+09:00',
  };

  /// 명세의 CaregiverEvaluation 하나를 만든다. card-1 은 쓰고 평가했고 card-2 는
  /// 쓰지 않았다.
  static Map<String, Object?> evaluation(String sessionId) => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'conversationSatisfaction': 4,
    'careRecipientReaction': 'pleased',
    'cardReviews': [
      {'cardId': 'card-1', 'wasUsed': true, 'caregiverReaction': 'positive'},
      {'cardId': 'card-2', 'wasUsed': false, 'caregiverReaction': null},
    ],
    'freeNote': null,
    'evaluatedAt': '2026-10-13T14:25:00+09:00',
  };

  /// 명세의 ChangeProposal 하나를 만든다. 생애 정보 제안이 하나 있다.
  static Map<String, Object?> proposal(String sessionId) => {
    'schemaVersion': 1,
    'sessionId': sessionId,
    'lifeFactProposals': [
      {
        'proposalId': 'proposal-1',
        'title': '한복',
        'content': '한복을 주로 만드셨어요.',
        'reason': '이번 면회에서 말씀하셨어요.',
        'reviewStatus': 'pending',
      },
    ],
    'topicProposals': <Object>[],
  };

  static http.Response _error(int status, String errorCode) => _json({
    'schemaVersion': 1,
    'errorCode': errorCode,
    'message': '테스트용 오류',
    'requestId': 'req_test',
    'retryable': false,
  }, status);

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}
