// 구글 로그인의 규칙을 확인한다.
//
// 서버와 구글 SDK 는 가짜로 바꿔 끼운다. 여기 쓰는 값은 모두 합성이며 실제 계정,
// 실제 토큰과 실제 사용자 정보를 쓰지 않는다(`CLAUDE.md`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/google_consent_screen.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/login_screen.dart';

// ── 가짜 구글 SDK ───────────────────────────────────

class _FakeGoogleAuthenticator implements GoogleAuthenticator {
  _FakeGoogleAuthenticator({this.token, this.failure});

  /// `null` 이면 사용자가 취소한 경우다.
  final String? token;

  final AuthFailure? failure;

  int calls = 0;

  @override
  Future<String?> idToken() async {
    calls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return token;
  }

  @override
  Future<void> signOut() async {}
}

// ── 합성 응답 ───────────────────────────────────────

String _authenticatedBody({String displayName = '보호자'}) => jsonEncode({
  'schemaVersion': 1,
  'status': 'authenticated',
  'accessToken': 'fake-session-token',
  'tokenType': 'Bearer',
  'expiresIn': 3600,
  'account': {
    'schemaVersion': 1,
    'accountId': 'acc_test_0001',
    'authProvider': 'google',
    'displayName': displayName,
    'email': null,
    'consent': {'consentVersion': consentVersion},
    'createdAt': '2026-09-18T09:00:00Z',
  },
});

String _consentRequiredBody({String version = consentVersion}) => jsonEncode({
  'schemaVersion': 1,
  'status': 'consentRequired',
  'registrationToken': 'fake-registration-token',
  'expiresIn': 600,
  'consentVersion': version,
  'requiredConsents': ['serviceData', 'sensitiveData'],
  'optionalConsents': ['pushNotification', 'serviceImprovement'],
});

String _errorBody(String errorCode, {bool retryable = false}) => jsonEncode({
  'schemaVersion': 1,
  'errorCode': errorCode,
  'message': '테스트용 오류',
  'requestId': 'req_test',
  'retryable': retryable,
});

ConsentRequiredResult _pending({String version = consentVersion}) =>
    ConsentRequiredResult.fromJson(
      jsonDecode(_consentRequiredBody(version: version))
          as Map<String, dynamic>,
    );

AuthApi _api(MockClient client) =>
    AuthApi(baseUrl: 'http://api.test', client: client);

/// `http.Response` 는 기본이 latin1 이라 한글이 깨진다. 서버와 같은 utf-8 로 준다.
http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

// ── 화면 묶기 ───────────────────────────────────────

Widget _app({
  required AuthApi api,
  required GoogleAuthenticator google,
  Widget? home,
  Object? extra,
}) {
  final router = GoRouter(
    initialLocation: home == null ? AppRoutes.login : AppRoutes.googleConsent,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.googleConsent,
        builder: (context, state) => GoogleConsentScreen(
          pending: (state.extra ?? extra) as ConsentRequiredResult,
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('홈 화면'))),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('처음 오셨네요'))),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('회원가입 화면'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authApiProvider.overrideWithValue(api),
      googleAuthenticatorProvider.overrideWithValue(google),
    ],
    child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
}

/// 화면을 길게 두어 스크롤 없이 모든 항목을 만질 수 있게 한다.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('구글 로그인 버튼', () {
    test('구글이 배포한 이미지를 그대로 쓰고 pubspec 에 담는다', () {
      expect(File(GoogleSignInButton.asset).existsSync(), isTrue);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains(GoogleSignInButton.asset),
        reason: 'asset 으로 선언하지 않으면 앱에 들어가지 않는다',
      );
    });

    testWidgets('로그인 화면에 하나 있고 눌러서 로그인할 수 있다', (tester) async {
      _tallScreen(tester);
      final google = _FakeGoogleAuthenticator(token: 'fake-id-token');

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              expect(request.url.path, '/auth/google');
              expect(jsonDecode(request.body), {
                'idToken': 'fake-id-token',
              }, reason: 'ID 토큰만 보내고 다른 값을 덧붙이지 않는다');
              return _json(_authenticatedBody(), 200);
            }),
          ),
          google: google,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GoogleSignInButton), findsOneWidget);

      await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
      await tester.pumpAndSettle();

      expect(google.calls, 1);
      expect(find.text('홈 화면'), findsOneWidget, reason: '계정이 있으면 바로 홈이다');
    });
  });

  group('로그인 화면', () {
    testWidgets('계정이 없으면 동의 화면으로 넘긴다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async => _json(_consentRequiredBody(), 200)),
          ),
          google: _FakeGoogleAuthenticator(token: 'fake-id-token'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
      await tester.pumpAndSettle();

      expect(find.byType(GoogleConsentScreen), findsOneWidget);
      expect(find.text('홈 화면'), findsNothing, reason: '동의 전에는 계정이 없다');
    });

    testWidgets('사용자가 취소하면 아무 오류도 띄우지 않는다', (tester) async {
      _tallScreen(tester);
      // 취소는 `idToken()` 이 null 을 주는 경우다.
      final google = _FakeGoogleAuthenticator();

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('취소했으면 서버를 부르지 않아야 한다');
            }),
          ),
          google: google,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
      await tester.pumpAndSettle();

      expect(google.calls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('못했어요'), findsNothing);
    });

    testWidgets('서버가 거절하면 이유를 화면에 남긴다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient(
              (request) async => _json(_errorBody('AUTH_NOT_CONFIGURED'), 503),
            ),
          ),
          google: _FakeGoogleAuthenticator(token: 'fake-id-token'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget, reason: '실패하면 넘어가지 않는다');
      expect(find.textContaining('로그인 설정이 아직 준비되지 않았어요'), findsOneWidget);
    });

    testWidgets('설정이 비어 있으면 구글 창을 띄우기 전에 알린다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('구글 인증을 받지 못했으면 서버를 부르지 않는다');
            }),
          ),
          google: _FakeGoogleAuthenticator(
            failure: const AuthGoogleFailure(misconfigured: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.image(const AssetImage(GoogleSignInButton.asset)));
      await tester.pumpAndSettle();

      expect(find.textContaining('구글 로그인 설정이 아직 준비되지 않았어요'), findsOneWidget);
    });
  });

  group('구글 동의 화면', () {
    testWidgets('필수 동의를 하지 않으면 제출하지 않고 이유를 알린다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('필수 동의 없이 서버를 부르지 않는다');
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(find.text('필수 항목에 모두 동의해야 가입할 수 있어요.'), findsOneWidget);
    });

    testWidgets('필수만 동의해도 계약의 네 항목을 모두 보낸다', (tester) async {
      _tallScreen(tester);
      Map<String, dynamic>? sent;

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              expect(request.url.path, '/auth/consent');
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return _json(_authenticatedBody(), 200);
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < consentTerms.length; i++) {
        if (!consentTerms[i].required) continue;
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(sent!['registrationToken'], 'fake-registration-token');
      expect(sent!['consentVersion'], consentVersion);
      expect(sent!['consents'], {
        'serviceData': true,
        'sensitiveData': true,
        'pushNotification': false,
        'serviceImprovement': false,
      }, reason: '고르지 않은 항목은 거부로 보낸다. 임의로 true 를 넣지 않는다');
      expect(
        sent!.containsKey('displayName'),
        isFalse,
        reason: '이름을 비웠으면 보내지 않고 서버 기본값을 쓴다',
      );
      expect(find.text('처음 오셨네요'), findsOneWidget, reason: '새 계정은 프로필부터 만든다');
    });

    testWidgets('이름을 적으면 함께 보낸다', (tester) async {
      _tallScreen(tester);
      Map<String, dynamic>? sent;

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return _json(_authenticatedBody(), 200);
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '  테스트보호자  ');
      for (var i = 0; i < consentTerms.length; i++) {
        if (!consentTerms[i].required) continue;
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(sent!['displayName'], '테스트보호자');
    });

    testWidgets('서버가 다른 약관 버전을 제시하면 동의를 받지 않는다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('보여주지 않은 문구에 동의를 받아 보내지 않는다');
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(version: '2099-01-01'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('약관이 새로 바뀌었어요'), findsOneWidget);
      expect(find.text('로그인으로 돌아가기'), findsOneWidget);
    });

    testWidgets('서버가 필수 동의로 거절하면 화면이 막을 때와 다른 문구를 보여준다', (tester) async {
      // 앱과 서버가 보는 필수 항목이 어긋났을 때만 나오는 자리다. 두 문구가
      // 같으면 앱 버그와 서버 불일치를 구분할 수 없다.
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient(
              (request) async =>
                  _json(_errorBody('REQUIRED_CONSENT_MISSING'), 422),
            ),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < consentTerms.length; i++) {
        if (!consentTerms[i].required) continue;
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(find.text('필수 항목에 모두 동의해야 가입할 수 있어요.'), findsNothing);
      expect(find.textContaining('서버가 동의 항목을 받아들이지 않았어요'), findsOneWidget);
      expect(find.text('처음 오셨네요'), findsNothing);
    });

    testWidgets('등록 토큰이 만료되면 로그인으로 돌아갈 길을 준다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient(
              (request) async =>
                  _json(_errorBody('REGISTRATION_TOKEN_EXPIRED'), 401),
            ),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < consentTerms.length; i++) {
        if (!consentTerms[i].required) continue;
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('시간이 지났어요'), findsOneWidget);
      expect(find.text('로그인으로 돌아가기'), findsOneWidget);
      expect(find.text('처음 오셨네요'), findsNothing, reason: '실패했는데 넘어가면 안 된다');
    });
  });

  group('로그인 API', () {
    test('status 로 두 응답을 가른다', () async {
      final api = _api(
        MockClient((request) async => _json(_authenticatedBody(), 200)),
      );
      expect(
        await api.signInWithGoogle('fake-id-token'),
        isA<AuthenticatedResult>(),
      );

      final second = _api(
        MockClient((request) async => _json(_consentRequiredBody(), 200)),
      );
      expect(
        await second.signInWithGoogle('fake-id-token'),
        isA<ConsentRequiredResult>(),
      );
    });

    test('서버가 준 errorCode 를 그대로 옮긴다', () async {
      final api = _api(
        MockClient(
          (request) async => _json(
            _errorBody('IDENTITY_PROVIDER_UNAVAILABLE', retryable: true),
            503,
          ),
        ),
      );

      await expectLater(
        api.signInWithGoogle('fake-id-token'),
        throwsA(
          isA<AuthServerFailure>()
              .having(
                (f) => f.errorCode,
                'errorCode',
                'IDENTITY_PROVIDER_UNAVAILABLE',
              )
              .having((f) => f.retryable, 'retryable', isTrue)
              .having((f) => f.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('모르는 status 를 성공으로 넘기지 않는다', () async {
      final api = _api(
        MockClient(
          (request) async =>
              _json(jsonEncode({'status': 'somethingElse'}), 200),
        ),
      );

      await expectLater(
        api.signInWithGoogle('fake-id-token'),
        throwsA(isA<AuthUnexpectedResponseFailure>()),
      );
    });

    test('서버에 닿지 못하면 연결 실패로 구분한다', () async {
      final api = _api(
        MockClient((request) async => throw const SocketException('연결 실패')),
      );

      await expectLater(
        api.signInWithGoogle('fake-id-token'),
        throwsA(isA<AuthNetworkFailure>()),
      );
    });

    test('세션은 받은 시각에서 만료 시각을 계산한다', () {
      final result = AuthenticatedResult.fromJson(
        jsonDecode(_authenticatedBody()) as Map<String, dynamic>,
      );
      final now = DateTime.utc(2026, 9, 18, 9);
      final session = AuthSession.fromResult(result, now: now);

      expect(session.expiresAt, now.add(const Duration(seconds: 3600)));
      expect(session.isExpired(now: now), isFalse);
      expect(
        session.isExpired(now: now.add(const Duration(seconds: 3601))),
        isTrue,
      );
      expect(session.authorizationHeader, 'Bearer fake-session-token');
    });
  });
}
