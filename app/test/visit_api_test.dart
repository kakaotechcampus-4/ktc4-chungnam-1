// 면회 회차 API(`lib/data/visit_api.dart`)를 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성 데이터다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/visit_api.dart';

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

http.Response _error(int status, String errorCode) => _json({
  'schemaVersion': 1,
  'errorCode': errorCode,
  'message': '합성 메시지',
  'requestId': 'req_01',
  'retryable': false,
}, status);

Map<String, dynamic> _session(List<String> cardIds) => {
  'schemaVersion': 1,
  'sessionId': 'session-1',
  'profileId': 'profile-1',
  'setId': 'set-1',
  'selectedCardIds': cardIds,
  'sessionStatus': 'evaluationPending',
  'photoId': null,
  'participantCount': null,
  'startedAt': '2026-10-13T14:00:00+09:00',
  'analysisId': null,
};

VisitApi _api(Future<http.Response> Function(http.Request request) handler) =>
    ServerVisitApi(
      ApiClient(
        authorization: () => 'Bearer test-token',
        baseUrl: 'http://api.test',
        client: MockClient(handler),
      ),
    );

void main() {
  group('5-1 회차 만들기', () {
    test('묶음과 고른 카드를 보내고 회차를 받는다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json(_session(['card-1', 'card-2']), 201);
      });

      final session = await api.createSession(
        setId: 'set-1',
        selectedCardIds: ['card-1', 'card-2'],
      );

      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'http://api.test/api/v1/visit-sessions');
      expect(jsonDecode(sent.body), {
        'setId': 'set-1',
        'selectedCardIds': ['card-1', 'card-2'],
      });
      expect(session.sessionId, 'session-1');
      expect(session.setId, 'set-1');
      expect(session.sessionStatus, SessionStatus.evaluationPending);
      expect(session.analysisId, isNull);
    });

    test('이미 쓴 묶음이라는 거절은 그대로 넘긴다', () async {
      final api = _api((_) async => _error(409, 'CARD_SET_ALREADY_USED'));

      await expectLater(
        api.createSession(setId: 'set-1', selectedCardIds: ['card-1']),
        throwsA(
          isA<ApiServerFailure>().having(
            (f) => f.errorCode,
            'errorCode',
            'CARD_SET_ALREADY_USED',
          ),
        ),
      );
    });

    test('형식이 다른 회차는 성공으로 넘기지 않는다', () async {
      final api = _api(
        (_) async => _json({'schemaVersion': 1, 'sessionId': 's'}, 201),
      );

      await expectLater(
        api.createSession(setId: 'set-1', selectedCardIds: ['card-1']),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });
  });

  group('5-3 보충 카드 더하기', () {
    test('더한 카드를 보내고 늘어난 회차를 받는다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json(_session(['card-1', 'card-10']), 200);
      });

      final session = await api.addCards('session-1', ['card-10']);

      expect(sent.method, 'PATCH');
      expect(
        sent.url.toString(),
        'http://api.test/api/v1/visit-sessions/session-1/cards',
      );
      expect(jsonDecode(sent.body), {
        'cardIds': ['card-10'],
      });
      expect(session.selectedCardIds, ['card-1', 'card-10']);
    });

    test('회차가 이미 평가를 마쳤다는 거절은 그대로 넘긴다', () async {
      final api = _api((_) async => _error(409, 'INVALID_SESSION_STATE'));

      await expectLater(
        api.addCards('session-1', ['card-10']),
        throwsA(
          isA<ApiServerFailure>().having(
            (f) => f.errorCode,
            'errorCode',
            'INVALID_SESSION_STATE',
          ),
        ),
      );
    });
  });
}
