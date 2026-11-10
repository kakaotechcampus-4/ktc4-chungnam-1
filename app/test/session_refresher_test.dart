// 앱을 쓰는 도중 세션이 만료됐을 때 조용히 다시 받는지, 받지 못하면 로그인부터
// 하도록 알리는지 확인한다(`lib/features/auth/session_refresher.dart`).
//
// 구글과 서버는 가짜다. 값은 모두 합성이다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/session_refresher.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/main.dart';

class _FakeGoogle implements GoogleAuthenticator {
  /// 무음 로그인이 돌려줄 ID 토큰. `null` 이면 조용히 받지 못한다.
  String? silent = 'fake-id-token';

  /// 무음 로그인을 기다리게 할 때 쓴다.
  Completer<void>? gate;

  int silentCalls = 0;

  @override
  Future<String?> idToken() async => silent;

  @override
  Future<String?> silentIdToken() async {
    silentCalls++;
    await gate?.future;
    return silent;
  }

  @override
  Future<void> signOut() async {}
}

class _MemoryStore implements SessionStore {
  AuthSession? stored;

  @override
  Future<AuthSession?> read() async => stored;

  @override
  Future<void> write(AuthSession session) async => stored = session;

  @override
  Future<void> clear() async => stored = null;
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _authenticated(
  String token, {
  String accountId = 'acc_test_0001',
}) => {
  'schemaVersion': 1,
  'status': 'authenticated',
  'accessToken': token,
  'tokenType': 'Bearer',
  'expiresIn': 3600,
  'account': {
    'schemaVersion': 1,
    'accountId': accountId,
    'authProvider': 'google',
    'displayName': '보호자',
    'email': null,
    'consent': {'consentVersion': '2026-09-06'},
    'createdAt': '2026-09-18T09:00:00Z',
  },
};

const _consentRequired = {
  'schemaVersion': 1,
  'status': 'consentRequired',
  'registrationToken': 'fake-registration-token',
  'expiresIn': 600,
  'consentVersion': '2026-09-06',
  'requiredConsents': ['serviceData', 'sensitiveData'],
  'optionalConsents': ['pushNotification', 'serviceImprovement'],
};

/// [expiresAt] 에 만료되는 로그인 세션이다.
AuthSession _session({required DateTime expiresAt}) => AuthSession(
  accessToken: 'old-token',
  tokenType: 'Bearer',
  expiresAt: expiresAt,
  account: AuthSession.fromResult(
    AuthenticatedResult.fromJson(_authenticated('old-token')),
  ).account,
);

class _Harness {
  _Harness({
    Future<http.Response> Function(http.Request)? server,
    AuthSession? session,
  }) : google = _FakeGoogle(),
       store = _MemoryStore() {
    container = ProviderContainer(
      overrides: [
        googleAuthenticatorProvider.overrideWithValue(google),
        sessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(
          AuthApi(
            baseUrl: 'http://api.test',
            client: MockClient((request) async {
              requests.add(request);
              return server?.call(request) ??
                  _json(_authenticated('new-token'), 200);
            }),
          ),
        ),
      ],
    );
    container
        .read(sessionProvider.notifier)
        .restore(session ?? _session(expiresAt: DateTime(2100)));
  }

  final _FakeGoogle google;
  final _MemoryStore store;
  final requests = <http.Request>[];
  late final ProviderContainer container;

  SessionRefresher get refresher => container.read(sessionRefresherProvider);
  AuthSession? get session => container.read(sessionProvider);
  SessionLoss? get loss => container.read(sessionLossProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('세션 다시 받기', () {
    test('무음 로그인으로 새 세션을 받아 바꾸고 보관한다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isTrue);

      expect(h.session!.accessToken, 'new-token');
      expect(h.store.stored!.accessToken, 'new-token');
      expect(h.requests.single.url.path, '/auth/google');
      expect(h.loss, isNull);
    });

    test('여러 요청이 함께 만료돼도 한 번만 다시 받는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.gate = Completer<void>();

      final first = h.refresher.refresh();
      final second = h.refresher.refresh();
      h.google.gate!.complete();

      expect(await Future.wait([first, second]), [true, true]);
      expect(h.google.silentCalls, 1);
      expect(h.requests, hasLength(1));
    });

    test('무음 로그인을 받지 못하면 세션을 지우고 로그인부터 하라고 알린다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.silent = null;

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session, isNull);
      expect(h.store.stored, isNull);
      expect(h.loss, isA<SessionSignedOut>());
    });

    test('계정이 사라졌으면 동의 화면으로 가도록 등록 정보를 넘긴다', () async {
      final h = _Harness(server: (_) async => _json(_consentRequired, 200));
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session, isNull);
      final loss = h.loss;
      expect(loss, isA<SessionConsentRequired>());
      expect(
        (loss! as SessionConsentRequired).pending.registrationToken,
        'fake-registration-token',
      );
    });

    test('서버에 닿지 못하면 세션을 지우지 않는다', () async {
      final h = _Harness(
        server: (_) async => throw http.ClientException('오프라인'),
      );
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session!.accessToken, 'old-token', reason: '세션이 죽었다고 단정하지 않는다');
      expect(h.loss, isNull);
    });

    test('서버가 거절하면 세션을 지우고 로그인부터 하라고 알린다', () async {
      final h = _Harness(
        server: (_) async => _json({
          'schemaVersion': 1,
          'errorCode': 'INVALID_ID_TOKEN',
          'message': '테스트',
          'requestId': 'r',
          'retryable': false,
        }, 401),
      );
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session, isNull);
      expect(h.loss, isA<SessionSignedOut>());
    });
  });

  // 2026-11-10 E2E: 녹음 중 매시간 뜨는 계정 선택 창을 취소하면 로그인 화면으로
  // 가서 녹음 화면이 닫히고 녹음이 멈출 수 있었다.
  group('면회를 녹음하는 동안 잃은 세션', () {
    void hold(_Harness h) =>
        h.container.read(sessionHoldProvider.notifier).hold();

    void release(_Harness h) =>
        h.container.read(sessionHoldProvider.notifier).release();

    test('계정 선택을 취소해도 세션을 지우지 않고 녹음이 끝나면 로그인부터 하게 한다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.silent = null;
      hold(h);

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session!.accessToken, 'old-token', reason: '녹음 화면이 닫히지 않게 둔다');
      expect(h.loss, isNull);

      release(h);
      await pumpEventQueue();

      expect(h.session, isNull);
      expect(h.store.stored, isNull);
      expect(h.loss, isA<SessionSignedOut>());
    });

    test('녹음하는 동안에는 계정 선택 창을 다시 띄우지 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.silent = null;
      hold(h);

      expect(await h.refresher.refresh(), isFalse);
      expect(
        await h.refresher.retryAfterUnauthorized('Bearer old-token'),
        isFalse,
      );
      expect(await h.refresher.refresh(), isFalse);

      expect(h.google.silentCalls, 1);
    });

    test('다른 계정을 골라도 녹음이 끝난 뒤에 로그인부터 하게 한다', () async {
      final h = _Harness(
        server: (_) async => _json(
          _authenticated('other-token', accountId: 'acc_test_0002'),
          200,
        ),
      );
      addTearDown(h.container.dispose);
      hold(h);

      expect(await h.refresher.refresh(), isFalse);
      expect(h.session!.accessToken, 'old-token');
      expect(h.loss, isNull);

      release(h);
      await pumpEventQueue();

      expect(h.session, isNull);
      expect(h.loss, isA<SessionSignedOut>());
    });

    test('계정이 사라졌어도 녹음이 끝난 뒤에 동의 화면으로 가게 한다', () async {
      final h = _Harness(server: (_) async => _json(_consentRequired, 200));
      addTearDown(h.container.dispose);
      hold(h);

      expect(await h.refresher.refresh(), isFalse);
      expect(h.loss, isNull);

      release(h);
      await pumpEventQueue();

      expect(h.loss, isA<SessionConsentRequired>());
    });

    test('녹음 중에도 같은 계정으로 받으면 그대로 바꾼다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      hold(h);

      expect(await h.refresher.refresh(), isTrue);

      expect(h.session!.accessToken, 'new-token');
      release(h);
      await pumpEventQueue();
      expect(h.loss, isNull);
    });

    test('녹음하는 동안 로그아웃하고 다시 로그인했으면 녹음이 끝나도 그 세션을 지우지 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.silent = null;
      hold(h);
      expect(await h.refresher.refresh(), isFalse);

      h.container
          .read(sessionProvider.notifier)
          .restore(_session(expiresAt: DateTime(2100)));
      release(h);
      await pumpEventQueue();

      expect(h.session, isNotNull);
      expect(h.loss, isNull);
    });
  });

  group('다시 받는 동안 바뀐 것', () {
    test('계정 선택 창에서 다른 계정을 고르면 바꾸지 않고 로그인부터 하게 한다', () async {
      final h = _Harness(
        server: (_) async =>
            _json(_authenticated('other-token', accountId: 'acc_other'), 200),
      );
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isFalse, reason: '원래 요청을 다시 보내지 않는다');

      expect(h.session, isNull, reason: '다른 계정의 세션을 쓰지 않는다');
      expect(h.store.stored, isNull);
      expect(h.loss, isA<SessionSignedOut>());
    });

    test('계정 선택 창이 떠 있는 동안 로그아웃하면 다시 받지 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      h.google.gate = Completer<void>();

      final refreshing = h.refresher.refresh();
      await h.container.read(sessionProvider.notifier).discard();
      h.google.gate!.complete();

      expect(await refreshing, isFalse);
      expect(h.requests, isEmpty, reason: '서버에 로그인하러 가지 않는다');
      expect(h.session, isNull);
      expect(h.loss, isNull, reason: '이미 로그인 화면이라 다시 옮기지 않는다');
    });

    test('서버 응답을 기다리는 동안 로그아웃하면 늦게 온 로그인을 저장하지 않는다', () async {
      final answer = Completer<void>();
      final h = _Harness(
        server: (_) async {
          await answer.future;
          return _json(_authenticated('late-token'), 200);
        },
      );
      addTearDown(h.container.dispose);

      final refreshing = h.refresher.refresh();
      await Future<void>.delayed(Duration.zero);
      await h.container.read(sessionProvider.notifier).discard();
      answer.complete();

      expect(await refreshing, isFalse);
      expect(h.session, isNull, reason: '로그아웃한 뒤 다시 로그인되지 않는다');
      expect(h.store.stored, isNull);
      expect(h.loss, isNull);
    });
  });

  group('요청을 보낸 뒤 늦게 온 401', () {
    test('보낸 뒤 로그아웃했으면 다시 받지도, 다시 보내지도 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      final sent = h.session!.authorizationHeader;

      await h.container.read(sessionProvider.notifier).discard();

      expect(await h.refresher.retryAfterUnauthorized(sent), isFalse);
      expect(h.google.silentCalls, 0, reason: '자동 재로그인을 시작하지 않는다');
      expect(h.session, isNull, reason: '로그아웃한 뒤 다시 로그인되지 않는다');
      expect(h.loss, isNull);
    });

    test('보낸 뒤 다른 계정으로 로그인했으면 그 계정으로 다시 보내지 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      final sent = h.session!.authorizationHeader;

      final other = AuthSession.fromResult(
        AuthenticatedResult.fromJson(
          _authenticated('b-token', accountId: 'acc_other'),
        ),
      );
      h.container.read(sessionProvider.notifier).restore(other);

      expect(await h.refresher.retryAfterUnauthorized(sent), isFalse);
      expect(h.google.silentCalls, 0);
      expect(h.session!.account.accountId, 'acc_other', reason: 'B 계정은 그대로다');
    });

    test('같은 계정을 그 사이 이미 새로 받았으면 받지 않고 새 세션으로 다시 보낸다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      final sent = h.session!.authorizationHeader;
      // 먼저 401 을 받은 다른 요청이 새로 받았다.
      expect(await h.refresher.refresh(), isTrue);

      expect(await h.refresher.retryAfterUnauthorized(sent), isTrue);
      expect(h.google.silentCalls, 1, reason: '같은 계정을 두 번 받지 않는다');
      expect(h.session!.accessToken, 'new-token');
    });

    test('보낸 세션 그대로면 새로 받는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);

      expect(
        await h.refresher.retryAfterUnauthorized(
          h.session!.authorizationHeader,
        ),
        isTrue,
      );
      expect(h.session!.accessToken, 'new-token');
    });
  });

  group('공개 API 요청 중 다시 받기', () {
    /// 하루 뒤 만료되는 세션으로 보낸 요청은 401, 새 세션은 성공으로 답하는
    /// 공개 API 다. 받은 요청은 [sent] 에 남는다.
    ApiClient client(_Harness h, List<http.Request> sent) => ApiClient(
      authorization: () => h.session?.authorizationHeader,
      beforeRequest: h.refresher.refreshIfExpiring,
      reauthenticate: h.refresher.retryAfterUnauthorized,
      continues: h.refresher.continues,
      baseUrl: 'http://public.test',
      client: MockClient((request) async {
        sent.add(request);
        return request.headers['Authorization'] == 'Bearer old-token'
            ? _json({
                'schemaVersion': 1,
                'errorCode': 'SESSION_EXPIRED',
                'message': '테스트',
                'requestId': 'r',
                'retryable': false,
              }, 401)
            : _json({'schemaVersion': 1}, 200);
      }),
    );

    test('다시 받기를 기다리는 동안 다른 계정으로 바뀌면 원래 요청을 보내지 않는다', () async {
      final h = _Harness(
        session: _session(
          expiresAt: DateTime.now().add(const Duration(seconds: 30)),
        ),
      );
      addTearDown(h.container.dispose);
      final sent = <http.Request>[];
      h.google.gate = Completer<void>();

      final saving = client(h, sent).post('/api/v1/profiles', {'a': 1});
      await pumpEventQueue();
      expect(h.google.silentCalls, 1, reason: '보내기 전에 다시 받는 중이다');

      // 기다리는 동안 로그아웃하고 B 계정으로 로그인한다.
      await h.container.read(sessionProvider.notifier).discard();
      h.container
          .read(sessionProvider.notifier)
          .restore(
            AuthSession.fromResult(
              AuthenticatedResult.fromJson(
                _authenticated('b-token', accountId: 'acc_other'),
              ),
            ),
          );
      h.google.gate!.complete();

      await expectLater(saving, throwsA(isA<ApiSignedOutFailure>()));
      expect(sent, isEmpty, reason: 'A 에서 시작한 요청을 B 로 보내지 않는다');
      expect(h.session!.account.accountId, 'acc_other');
    });

    test('곧 만료돼 같은 계정으로 새로 받았으면 새 세션으로 보낸다', () async {
      final h = _Harness(
        session: _session(
          expiresAt: DateTime.now().add(const Duration(seconds: 30)),
        ),
      );
      addTearDown(h.container.dispose);
      final sent = <http.Request>[];

      await client(h, sent).post('/api/v1/profiles', {'a': 1});

      expect(sent.single.headers['Authorization'], 'Bearer new-token');
    });

    test('401 뒤 다시 받는 서버에 닿지 못하면 연결 실패로 돌려주고 세션을 둔다', () async {
      final h = _Harness(
        server: (_) async => throw http.ClientException('오프라인'),
      );
      addTearDown(h.container.dispose);
      final sent = <http.Request>[];

      await expectLater(
        client(h, sent).get('/api/v1/x'),
        throwsA(isA<ApiNetworkFailure>()),
        reason: '다시 보낼 수 있는 실패라 보낼 자료를 지우지 않는다',
      );
      expect(sent, hasLength(1));
      expect(h.session!.accessToken, 'old-token');
      expect(h.loss, isNull);
    });

    test('다시 받는 서버가 잠시 응답하지 못하면 로그아웃하지 않고 다시 시도할 수 있게 한다', () async {
      final h = _Harness(
        server: (_) async => _json({
          'schemaVersion': 1,
          'errorCode': 'IDENTITY_PROVIDER_UNAVAILABLE',
          'message': '테스트',
          'requestId': 'r',
          'retryable': true,
        }, 503),
      );
      addTearDown(h.container.dispose);
      final sent = <http.Request>[];

      await expectLater(
        client(h, sent).get('/api/v1/x'),
        throwsA(
          isA<ApiServerFailure>()
              .having((f) => f.statusCode, 'statusCode', 503)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
      expect(sent, hasLength(1), reason: '원래 요청은 다시 보내지 않는다');
      expect(h.session!.accessToken, 'old-token', reason: '세션을 지우지 않는다');
      expect(h.loss, isNull, reason: '로그인 화면으로 보내지 않는다');
    });

    test('곧 만료될 세션을 미리 받다가 서버가 잠시 응답하지 못해도 로그아웃하지 않는다', () async {
      final h = _Harness(
        server: (_) async => _json({
          'schemaVersion': 1,
          'errorCode': 'IDENTITY_PROVIDER_UNAVAILABLE',
          'message': '테스트',
          'requestId': 'r',
          'retryable': true,
        }, 503),
      );
      addTearDown(h.container.dispose);

      expect(await h.refresher.refresh(), isFalse);

      expect(h.session!.accessToken, 'old-token');
      expect(h.loss, isNull);
    });
  });

  group('곧 만료될 세션', () {
    test('1분 안에 만료되면 보내기 전에 새로 받는다', () async {
      final h = _Harness(
        session: _session(
          expiresAt: DateTime.now().add(const Duration(seconds: 30)),
        ),
      );
      addTearDown(h.container.dispose);

      await h.refresher.refreshIfExpiring();

      expect(h.session!.accessToken, 'new-token');
    });

    test('넉넉히 남았으면 새로 받지 않는다', () async {
      final h = _Harness();
      addTearDown(h.container.dispose);

      await h.refresher.refreshIfExpiring();

      expect(h.google.silentCalls, 0);
      expect(h.session!.accessToken, 'old-token');
    });
  });

  group('세션을 잃으면 앱이 옮기는 화면', () {
    Future<ProviderContainer> openApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [sessionStoreProvider.overrideWithValue(_MemoryStore())],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SaerokApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('로그인부터 해야 하면 로그인 화면으로 간다', (tester) async {
      final container = await openApp(tester);
      container
          .read(sessionLossProvider.notifier)
          .report(const SessionSignedOut());
      await tester.pumpAndSettle();

      expect(find.byType(GoogleSignInButton), findsOneWidget);
      expect(container.read(sessionLossProvider), isNull, reason: '한 번만 옮긴다');
    });

    testWidgets('계정이 사라졌으면 동의 화면으로 간다', (tester) async {
      final container = await openApp(tester);
      container
          .read(sessionLossProvider.notifier)
          .report(
            SessionConsentRequired(
              ConsentRequiredResult.fromJson(
                Map<String, dynamic>.from(_consentRequired),
              ),
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('약관 동의'), findsWidgets);
    });
  });
}
