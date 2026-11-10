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
      files: () async => [
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

  group('앱이 서버와 맞지 않아 보이는 실패', () {
    Future<List<ApiFailure>> reported(http.Response response) async {
      final mismatches = <ApiFailure>[];
      final api = ApiClient(
        authorization: () => _auth,
        baseUrl: 'http://api.test/',
        client: MockClient((_) async => response),
        onContractMismatch: mismatches.add,
      );
      try {
        await api.get('/api/v1/anything');
      } on ApiFailure {
        // 실패는 그대로 던진다. 여기서는 알렸는지만 본다.
      }
      return mismatches;
    }

    Map<String, Object> error(String code) => {
      'schemaVersion': 1,
      'errorCode': code,
      'retryable': false,
    };

    test('모르는 경로, 형식 오류, 업데이트 요구와 읽지 못한 응답은 알린다', () async {
      expect(await reported(_json(error('NOT_FOUND'), 404)), hasLength(1));
      expect(await reported(_json(error('HTTP_ERROR'), 405)), hasLength(1));
      expect(
        await reported(_json(error('INVALID_REQUEST'), 422)),
        hasLength(1),
      );
      expect(await reported(_json(error('UPGRADE'), 426)), hasLength(1));
      expect(await reported(_json([1, 2], 200)), hasLength(1));
    });

    test('업무상 거절, 서버 장애와 연결 실패는 알리지 않는다', () async {
      expect(
        await reported(_json(error('VISIT_SESSION_NOT_FOUND'), 404)),
        isEmpty,
      );
      expect(
        await reported(_json(error('REQUIRED_CONSENT_MISSING'), 422)),
        isEmpty,
      );
      expect(await reported(_json(error('CARD_SET_READY'), 409)), isEmpty);
      expect(
        await reported(_json(error('INTERNAL_SERVER_ERROR'), 500)),
        isEmpty,
      );
      expect(await reported(http.Response('<html>', 404)), isEmpty);
    });

    test('426 만 업데이트가 필요하다고 단정한다', () {
      expect(isUpdateRequired(const ApiServerFailure(statusCode: 426)), isTrue);
      expect(
        isUpdateRequired(
          const ApiServerFailure(statusCode: 404, errorCode: 'NOT_FOUND'),
        ),
        isFalse,
      );
    });

    test('응답을 읽다가 모양이 다르면 실패로 바꾸고 알린다', () {
      final mismatches = <ApiFailure>[];
      final api = ApiClient(
        authorization: () => _auth,
        client: MockClient((_) async => http.Response('', 200)),
        onContractMismatch: mismatches.add,
      );

      expect(
        () => api.read('회차', () => ({'id': 1})['id'] as String),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
      expect(
        () => api.read(
          '상태',
          () => throw const ApiUnexpectedResponseFailure('모르는 status'),
        ),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
      expect(() => api.unexpected('id 가 없다'), returnsNormally);
      expect(mismatches, hasLength(3));
    });
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

  group('세션 만료', () {
    /// 첫 요청은 401 로, 새 세션으로 다시 보낸 요청은 성공으로 답하는 서버다.
    ///
    /// [rejectAgain] 이면 다시 보낸 요청도 401 이다.
    ({ApiClient api, List<http.Request> sent, List<String?> reauths}) expired({
      bool reauthenticated = true,
      bool rejectAgain = false,
    }) {
      var token = 'Bearer old';
      final sent = <http.Request>[];
      // 다시 받을 때 넘겨받은, 요청에 실었던 세션.
      final reauths = <String?>[];
      final api = ApiClient(
        authorization: () => token,
        reauthenticate: (sentAuthorization) async {
          reauths.add(sentAuthorization);
          if (reauthenticated) token = 'Bearer new';
          return reauthenticated;
        },
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          sent.add(request);
          final rejected =
              request.headers['Authorization'] == 'Bearer old' || rejectAgain;
          return rejected
              ? _json({
                  'schemaVersion': 1,
                  'errorCode': 'SESSION_EXPIRED',
                  'message': '테스트',
                  'requestId': 'r',
                  'retryable': false,
                }, 401)
              : _json({'schemaVersion': 1, 'status': 'ready'}, 200);
        }),
      );
      return (api: api, sent: sent, reauths: reauths);
    }

    test('401 이면 세션을 새로 받아 같은 요청을 새 세션으로 다시 보낸다', () async {
      final server = expired();

      final body = await server.api.post('/api/v1/x', {'a': 1});

      expect(body['status'], 'ready');
      expect(server.reauths, ['Bearer old']);
      expect(server.sent, hasLength(2));
      expect(server.sent.last.headers['Authorization'], 'Bearer new');
      expect(server.sent.last.body, server.sent.first.body, reason: '같은 요청이다');
    });

    test('세션을 새로 받지 못하면 다시 보내지 않고 401 을 돌려준다', () async {
      final server = expired(reauthenticated: false);

      await expectLater(
        server.api.get('/api/v1/x'),
        throwsA(
          isA<ApiServerFailure>().having((f) => f.statusCode, 'status', 401),
        ),
      );
      expect(server.sent, hasLength(1));
    });

    test('다시 보내도 401 이면 더 반복하지 않는다', () async {
      final server = expired(rejectAgain: true);

      await expectLater(
        server.api.get('/api/v1/x'),
        throwsA(isA<ApiServerFailure>()),
      );
      expect(server.reauths, ['Bearer old']);
      expect(server.sent, hasLength(2));
    });

    test('파일 업로드도 파일을 새로 만들어 다시 보낸다', () async {
      final server = expired();
      var built = 0;

      await server.api.postMultipart(
        '/api/v1/visit-sessions/s1/speech-analyses',
        fields: {'participantCount': '2'},
        files: () async {
          built++;
          return [
            http.MultipartFile.fromBytes('audio', [1, 2, 3], filename: 'a.wav'),
          ];
        },
      );

      expect(built, 2);
      expect(server.sent.last.body, contains('name="audio"; filename="a.wav"'));
    });

    test('보내기 전에 매번 곧 만료될 세션을 확인한다', () async {
      var checked = 0;
      final api = ApiClient(
        authorization: () => _auth,
        beforeRequest: () async => checked++,
        baseUrl: 'http://api.test',
        client: MockClient((_) async => _json({'schemaVersion': 1}, 200)),
      );

      await api.get('/x');
      await api.delete('/y');

      expect(checked, 2);
    });
  });
}
