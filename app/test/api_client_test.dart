// 공개 API 공통 요청 틀(`lib/data/api_client.dart`)을 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성 데이터다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';

const _auth = 'Bearer test-token';

ApiClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  String? authorization = _auth,
}) => ApiClient(
  authorization: () => authorization,
  baseUrl: 'http://api.test/',
  client: MockClient(handler),
);

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('GET 은 서버 주소와 Authorization 을 붙이고 응답 객체를 돌려준다', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return _json({'schemaVersion': 1, 'status': 'ready'}, 200);
    });

    final body = await api.get(
      '/api/v1/profiles/p1/card-generations/status',
      query: {'a': '1'},
    );

    expect(sent.method, 'GET');
    expect(
      sent.url.toString(),
      'http://api.test/api/v1/profiles/p1/card-generations/status?a=1',
    );
    expect(sent.headers['Authorization'], _auth);
    expect(body['status'], 'ready');
  });

  test('POST 와 PATCH 는 JSON 본문을 보낸다', () async {
    final sent = <http.Request>[];
    final api = _client((request) async {
      sent.add(request);
      return _json({'schemaVersion': 1}, 201);
    });

    await api.post('/api/v1/visit-sessions', {
      'cardIds': ['c1'],
    });
    await api.patch('/api/v1/visit-sessions/s1/cards', {
      'cardIds': ['c2'],
    });

    expect(sent.map((r) => r.method), ['POST', 'PATCH']);
    for (final request in sent) {
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['Authorization'], _auth);
    }
    expect(jsonDecode(sent.first.body), {
      'cardIds': ['c1'],
    });
  });

  test('본문 없는 POST 는 Content-Type 을 붙이지 않는다', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return _json({'schemaVersion': 1}, 202);
    });

    await api.post('/api/v1/profiles/p1/card-generations');

    expect(sent.body, isEmpty);
    expect(sent.headers.containsKey('Content-Type'), isFalse);
  });

  test('파일 업로드는 multipart 로 필드와 파일을 함께 보낸다', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return _json({'schemaVersion': 1, 'status': 'queued'}, 202);
    });

    final body = await api.postMultipart(
      '/api/v1/visit-sessions/s1/speech-analyses',
      fields: {'participantCount': '2'},
      files: [
        http.MultipartFile.fromBytes('audio', [1, 2, 3], filename: 'a.wav'),
      ],
    );

    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(sent.headers['Authorization'], _auth);
    expect(sent.body, contains('name="participantCount"'));
    expect(sent.body, contains('name="audio"; filename="a.wav"'));
    expect(body['status'], 'queued');
  });

  test('DELETE 는 빈 204 응답을 성공으로 본다', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return http.Response('', 204);
    });

    await api.delete('/api/v1/profiles/p1');

    expect(sent.method, 'DELETE');
    expect(sent.url.toString(), 'http://api.test/api/v1/profiles/p1');
    expect(sent.headers['Authorization'], _auth);
  });

  test('DELETE 가 거절되면 ErrorResponse 를 담는다', () async {
    final api = _client(
      (_) async => _json({
        'schemaVersion': 1,
        'errorCode': 'PROFILE_NOT_FOUND',
        'message': '프로필을 찾을 수 없습니다.',
        'requestId': 'req_02',
        'retryable': false,
      }, 404),
    );

    await expectLater(
      api.delete('/api/v1/profiles/p1'),
      throwsA(
        isA<ApiServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)
            .having((f) => f.errorCode, 'errorCode', 'PROFILE_NOT_FOUND'),
      ),
    );
  });

  test('서버가 거절하면 ErrorResponse 의 errorCode 와 retryable 을 담는다', () async {
    final api = _client(
      (_) async => _json({
        'schemaVersion': 1,
        'errorCode': 'AUDIO_STORAGE_UNAVAILABLE',
        'message': '잠시 후 다시 시도해 주세요.',
        'requestId': 'req_01',
        'retryable': true,
      }, 503),
    );

    await expectLater(
      api.get('/x'),
      throwsA(
        isA<ApiServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 503)
            .having(
              (f) => f.errorCode,
              'errorCode',
              'AUDIO_STORAGE_UNAVAILABLE',
            )
            .having((f) => f.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('오류 본문을 읽지 못해도 상태 코드는 남기고 코드를 지어내지 않는다', () async {
    final api = _client((_) async => http.Response('Bad Gateway', 502));

    await expectLater(
      api.get('/x'),
      throwsA(
        isA<ApiServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 502)
            .having((f) => f.errorCode, 'errorCode', isNull)
            .having((f) => f.retryable, 'retryable', isFalse),
      ),
    );
  });

  test('연결 실패와 시간 초과는 네트워크 실패다', () async {
    final refused = _client(
      (_) async => throw const SocketException('connection refused'),
    );
    await expectLater(refused.get('/x'), throwsA(isA<ApiNetworkFailure>()));

    final slow = ApiClient(
      authorization: () => _auth,
      baseUrl: 'http://api.test',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json({}, 200);
      }),
    );
    await expectLater(slow.get('/x'), throwsA(isA<ApiNetworkFailure>()));
  });

  test('성공 응답이 객체가 아니면 성공으로 넘기지 않는다', () async {
    final api = _client((_) async => _json([1, 2], 200));

    await expectLater(
      api.get('/x'),
      throwsA(isA<ApiUnexpectedResponseFailure>()),
    );
  });

  test('로그인 세션이 없으면 요청을 보내지 않는다', () async {
    var called = false;
    final api = _client((_) async {
      called = true;
      return _json({}, 200);
    }, authorization: null);

    await expectLater(api.get('/x'), throwsA(isA<ApiSignedOutFailure>()));
    expect(called, isFalse);
  });

  test('세션은 요청할 때마다 새로 읽는다', () async {
    var token = 'Bearer first';
    final seen = <String?>[];
    final api = ApiClient(
      authorization: () => token,
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        seen.add(request.headers['Authorization']);
        return _json({}, 200);
      }),
    );

    await api.get('/x');
    token = 'Bearer second';
    await api.get('/x');

    expect(seen, ['Bearer first', 'Bearer second']);
  });
}
