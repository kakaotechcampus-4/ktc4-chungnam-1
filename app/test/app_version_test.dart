// 요청마다 앱 버전을 싣는지, 로그인 요청의 실패도 업데이트 안내에 알리는지
// 확인한다(`lib/data/app_version.dart`).
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성 데이터다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/app_version.dart';
import 'package:saerok/data/auth_api.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object> _error(String code) => {
  'schemaVersion': 1,
  'errorCode': code,
  'retryable': false,
};

void main() {
  test('서버와 맞지 않아 보이는 거절만 고른다', () {
    expect(suggestsContractMismatch(404, 'NOT_FOUND'), isTrue);
    expect(suggestsContractMismatch(405, 'HTTP_ERROR'), isTrue);
    expect(suggestsContractMismatch(410, null), isTrue);
    expect(suggestsContractMismatch(422, 'INVALID_REQUEST'), isTrue);
    expect(suggestsContractMismatch(426, 'APP_UPDATE_REQUIRED'), isTrue);

    expect(suggestsContractMismatch(404, 'VISIT_SESSION_NOT_FOUND'), isFalse);
    expect(suggestsContractMismatch(404, null), isFalse);
    expect(suggestsContractMismatch(422, 'REQUIRED_CONSENT_MISSING'), isFalse);
    expect(suggestsContractMismatch(500, 'INTERNAL_SERVER_ERROR'), isFalse);
    expect(isUpdateRequiredStatus(426), isTrue);
    expect(isUpdateRequiredStatus(404), isFalse);
  });

  group('ApiClient', () {
    Future<http.BaseRequest> sentWith(String? versionCode) async {
      late http.BaseRequest sent;
      final api = ApiClient(
        authorization: () => 'Bearer test-token',
        baseUrl: 'http://api.test',
        appVersionCode: versionCode,
        client: MockClient((request) async {
          sent = request;
          return _json({'schemaVersion': 1}, 200);
        }),
      );
      await api.get('/api/v1/anything');
      return sent;
    }

    test('앱 버전을 알면 요청마다 싣는다', () async {
      final sent = await sentWith('5');
      expect(sent.headers[appVersionCodeHeader], '5');
      expect(sent.headers['Authorization'], 'Bearer test-token');
    });

    test('앱 버전을 모르면 싣지 않는다', () async {
      final sent = await sentWith(null);
      expect(sent.headers.containsKey(appVersionCodeHeader), isFalse);
    });
  });

  group('AuthApi', () {
    late List<http.BaseRequest> sent;
    late List<AuthFailure> mismatches;

    AuthApi api(http.Response Function(http.Request request) respond) {
      sent = [];
      mismatches = [];
      return AuthApi(
        baseUrl: 'http://api.test',
        appVersionCode: '5',
        onContractMismatch: mismatches.add,
        client: MockClient((request) async {
          sent.add(request);
          return respond(request);
        }),
      );
    }

    test('로그인, 동의, 계정 확인, 로그아웃과 탈퇴에 앱 버전을 싣는다', () async {
      final auth = api((_) => http.Response('', 204));

      // 응답 모양은 이 테스트의 관심이 아니다. 실린 헤더만 본다.
      Future<void> send(Future<Object?> request) =>
          request.then((_) {}, onError: (Object _) {});
      await send(auth.signInWithGoogle('id-token'));
      await send(auth.me('Bearer s1'));
      await send(auth.logout('Bearer s1'));
      await send(auth.deleteAccount('Bearer s1'));
      await send(
        auth.submitConsent(
          registrationToken: 'r1',
          consentVersion: 'v1',
          consents: const {'serviceData': true},
        ),
      );

      expect(sent, hasLength(5));
      for (final request in sent) {
        expect(
          request.headers[appVersionCodeHeader],
          '5',
          reason: request.url.path,
        );
      }
      expect(sent[1].headers['Authorization'], 'Bearer s1');
      expect(sent[0].headers['Content-Type'], startsWith('application/json'));
    });

    test('앱 버전을 모르면 싣지 않는다', () async {
      final requests = <http.BaseRequest>[];
      final auth = AuthApi(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );

      await auth.logout('Bearer s1');

      expect(
        requests.single.headers.containsKey(appVersionCodeHeader),
        isFalse,
      );
    });

    test('업데이트 요구와 모르는 경로는 알리고, 업무상 거절은 알리지 않는다', () async {
      await expectLater(
        api(
          (_) => _json(_error('APP_UPDATE_REQUIRED'), 426),
        ).signInWithGoogle('id-token'),
        throwsA(isA<AuthServerFailure>()),
      );
      expect(mismatches, hasLength(1));
      expect((mismatches.single as AuthServerFailure).statusCode, 426);

      await expectLater(
        api((_) => _json(_error('NOT_FOUND'), 404)).logout('Bearer s1'),
        throwsA(isA<AuthServerFailure>()),
      );
      expect(mismatches, hasLength(1));

      await expectLater(
        api(
          (_) => _json(_error('INVALID_GOOGLE_TOKEN'), 401),
        ).signInWithGoogle('id-token'),
        throwsA(isA<AuthServerFailure>()),
      );
      expect(mismatches, isEmpty);
    });

    test('모르는 로그인 결과가 오면 알린다', () async {
      await expectLater(
        api(
          (_) => _json({'schemaVersion': 1, 'status': 'newStatus'}, 200),
        ).signInWithGoogle('id-token'),
        throwsA(isA<AuthUnexpectedResponseFailure>()),
      );
      expect(mismatches, hasLength(1));
    });
  });
}
