// 대화 카드 API(`lib/data/card_api.dart`)를 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성 데이터다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/card_api.dart';

const _profileId = 'profile-1';
const _base = 'http://api.test/api/v1/profiles/$_profileId/card-generations';

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

http.Response _error(int status, String errorCode) => _json({
  'schemaVersion': 1,
  'errorCode': errorCode,
  'message': '합성 메시지',
  'requestId': 'req_01',
  'retryable': false,
}, status);

CardApi _api(Future<http.Response> Function(http.Request request) handler) =>
    ServerCardApi(
      ApiClient(
        authorization: () => 'Bearer test-token',
        baseUrl: 'http://api.test',
        client: MockClient(handler),
      ),
    );

Map<String, dynamic> _card(int position) => {
  'cardId': 'card-$position',
  'position': position,
  'topic': {
    'topicId': 'topic-$position',
    'title': '주제 $position',
    'description': '주제 설명',
  },
  'cardTitle': '카드 $position',
  'description': '카드 설명',
  'primaryQuestion': '첫 질문',
  'followUpQuestions': ['꼬리 1', '꼬리 2', '꼬리 3'],
  'evidenceSource': 'none',
  'evidence': <Object>[],
  'selected': false,
};

void main() {
  group('4-1 카드 생성 요청', () {
    test('본문 없이 POST 하고 running 을 받는다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json({'schemaVersion': 1, 'status': 'running'}, 202);
      });

      final status = await api.requestGeneration(_profileId);

      expect(sent.method, 'POST');
      expect(sent.url.toString(), _base);
      expect(sent.body, isEmpty);
      expect(status, CardGenerationStatus.running);
    });

    test('이미 쓸 묶음이 있다는 거절은 그 상태로 받는다', () async {
      final ready = _api((_) async => _error(409, 'CARD_SET_READY'));
      final inVisit = _api((_) async => _error(409, 'VISIT_IN_PROGRESS'));

      expect(
        await ready.requestGeneration(_profileId),
        CardGenerationStatus.ready,
      );
      expect(
        await inVisit.requestGeneration(_profileId),
        CardGenerationStatus.inVisit,
      );
    });

    test('그 밖의 거절은 실패로 그대로 넘긴다', () async {
      final api = _api(
        (_) async => _error(503, 'CARD_GENERATION_NOT_CONFIGURED'),
      );

      await expectLater(
        api.requestGeneration(_profileId),
        throwsA(
          isA<ApiServerFailure>().having(
            (f) => f.errorCode,
            'errorCode',
            'CARD_GENERATION_NOT_CONFIGURED',
          ),
        ),
      );
    });
  });

  group('4-2 상태 확인', () {
    test('다섯 상태를 모두 읽는다', () async {
      final serverValues = CardGenerationStatus.values.where(
        (v) => v != CardGenerationStatus.needsRefresh,
      );
      for (final value in serverValues) {
        late http.Request sent;
        final api = _api((request) async {
          sent = request;
          return _json({'schemaVersion': 1, 'status': value.name}, 200);
        });

        expect(await api.status(_profileId), value);
        expect(sent.method, 'GET');
        expect(sent.url.toString(), '$_base/status');
      }
    });

    test('모르는 상태는 성공으로 넘기지 않는다', () async {
      final api = _api(
        (_) async => _json({'schemaVersion': 1, 'status': 'done'}, 200),
      );

      await expectLater(
        api.status(_profileId),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });

    test('ready 에 needsRefresh 가 붙으면 다시 만들 묶음으로 읽는다', () async {
      CardApi reply(Map<String, dynamic> body) =>
          _api((_) async => _json({'schemaVersion': 1, ...body}, 200));

      expect(
        await reply({
          'status': 'ready',
          'needsRefresh': true,
        }).status(_profileId),
        CardGenerationStatus.needsRefresh,
      );
      expect(
        await reply({
          'status': 'ready',
          'needsRefresh': false,
        }).status(_profileId),
        CardGenerationStatus.ready,
      );
      // 이 값을 주기 전의 서버다.
      expect(
        await reply({'status': 'ready'}).status(_profileId),
        CardGenerationStatus.ready,
      );
    });

    test('needsRefresh 는 서버의 status 값으로 받지 않는다', () async {
      final api = _api(
        (_) async => _json({'schemaVersion': 1, 'status': 'needsRefresh'}, 200),
      );

      await expectLater(
        api.status(_profileId),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });
  });

  group('4-3 카드 묶음 받기', () {
    test('묶음을 읽고 position 순서로 줄 세운다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json({
          'schemaVersion': 1,
          'setId': 'set-1',
          'usedBySessionId': null,
          'cards': [for (var p = 12; p >= 1; p--) _card(p)],
        }, 200);
      });

      final set = await api.current(_profileId);

      expect(sent.method, 'GET');
      expect(sent.url.toString(), '$_base/current');
      expect(set.setId, 'set-1');
      expect(set.usedBySessionId, isNull);
      expect(set.needsRefresh, isFalse, reason: '값이 없으면 다시 만들 일이 없다');
      expect(set.cards.map((c) => c.position), List.generate(12, (i) => i + 1));
      expect(set.cards.first.cardTitle, '카드 1');
    });

    test('받은 뒤 정보를 고친 묶음이면 needsRefresh 를 읽는다', () async {
      final api = _api(
        (_) async => _json({
          'schemaVersion': 1,
          'setId': 'set-1',
          'usedBySessionId': null,
          'needsRefresh': true,
          'cards': [for (var p = 1; p <= 12; p++) _card(p)],
        }, 200),
      );

      expect((await api.current(_profileId)).needsRefresh, isTrue);
    });

    test('형식이 다른 묶음은 성공으로 넘기지 않는다', () async {
      final api = _api(
        (_) async => _json({'schemaVersion': 1, 'setId': 'set-1'}, 200),
      );

      await expectLater(
        api.current(_profileId),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });

    test('쓸 묶음이 없으면 서버 거절로 넘긴다', () async {
      final api = _api((_) async => _error(404, 'CARD_GENERATION_NOT_FOUND'));

      await expectLater(
        api.current(_profileId),
        throwsA(
          isA<ApiServerFailure>().having(
            (f) => f.errorCode,
            'errorCode',
            'CARD_GENERATION_NOT_FOUND',
          ),
        ),
      );
    });
  });
}
