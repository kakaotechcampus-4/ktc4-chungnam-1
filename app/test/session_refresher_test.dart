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

Map<String, Object?> _authenticated(String token) => {
  'schemaVersion': 1,
  'status': 'authenticated',
  'accessToken': token,
  'tokenType': 'Bearer',
  'expiresIn': 3600,
  'account': {
    'schemaVersion': 1,
    'accountId': 'acc_test_0001',
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
