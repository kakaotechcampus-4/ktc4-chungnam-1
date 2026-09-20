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
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/consent_terms.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/google_consent_screen.dart';
import 'package:saerok/features/auth/google_sign_in_button.dart';
import 'package:saerok/features/auth/login_screen.dart';
import 'package:saerok/features/auth/splash_screen.dart';
import 'package:saerok/features/auth/session_store.dart';

// ── 가짜 구글 SDK ───────────────────────────────────

class _FakeGoogleAuthenticator implements GoogleAuthenticator {
  _FakeGoogleAuthenticator({this.token, this.failure, this.silentToken});

  /// `null` 이면 사용자가 취소한 경우다.
  final String? token;

  final AuthFailure? failure;

  /// 무음 로그인이 돌려줄 ID 토큰. `null` 이면 고른 계정이 없는 경우다.
  final String? silentToken;

  int calls = 0;
  int silentCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> idToken() async {
    calls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return token;
  }

  @override
  Future<String?> silentIdToken() async {
    silentCalls++;
    return silentToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

/// 단말 저장소 대신 쓴다. 실제 보안 저장소는 플랫폼 채널이 필요해 테스트에서
/// 돌지 않는다.
class _FakeSessionStore implements SessionStore {
  _FakeSessionStore([this._session]);

  AuthSession? _session;

  int writes = 0;
  int clears = 0;

  AuthSession? get stored => _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async {
    writes++;
    _session = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    _session = null;
  }
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

String _consentRequiredBody({
  String version = consentVersion,
  List<String> required = const ['serviceData', 'sensitiveData'],
  List<String> optional = const ['pushNotification', 'serviceImprovement'],
}) => jsonEncode({
  'schemaVersion': 1,
  'status': 'consentRequired',
  'registrationToken': 'fake-registration-token',
  'expiresIn': 600,
  'consentVersion': version,
  'requiredConsents': required,
  'optionalConsents': optional,
});

String _errorBody(String errorCode, {bool retryable = false}) => jsonEncode({
  'schemaVersion': 1,
  'errorCode': errorCode,
  'message': '테스트용 오류',
  'requestId': 'req_test',
  'retryable': retryable,
});

ConsentRequiredResult _pending({
  String version = consentVersion,
  List<String> required = const ['serviceData', 'sensitiveData'],
  List<String> optional = const ['pushNotification', 'serviceImprovement'],
}) => ConsentRequiredResult.fromJson(
  jsonDecode(
        _consentRequiredBody(
          version: version,
          required: required,
          optional: optional,
        ),
      )
      as Map<String, dynamic>,
);

/// 동의 항목의 체크박스 자리. 전체 동의가 뒤에 하나 더 붙는다.
int _rowOf(String key) => consentTerms.indexWhere((term) => term.key == key);

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
  SessionStore? store,
  String? initialLocation,
}) {
  final router = GoRouter(
    initialLocation:
        initialLocation ??
        (home == null ? AppRoutes.login : AppRoutes.googleConsent),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
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
      // 실제 보안 저장소는 플랫폼 채널이 필요해 테스트에서 끝나지 않는다.
      // 넘기지 않은 화면도 가짜를 쓴다.
      sessionStoreProvider.overrideWithValue(store ?? _FakeSessionStore()),
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

    testWidgets('필수 여부는 앱 상수가 아니라 서버가 준 목록을 따른다', (tester) async {
      // 앱 상수는 알림 수신을 선택으로 둔다. 서버가 필수로 주면 서버를 따라야
      // 한다. 앱이 제 상수를 보고 제출하면 서버가 422 로 거절한다.
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('서버가 필수로 준 항목 없이 보내지 않는다');
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(
            required: const ['serviceData', 'sensitiveData', 'pushNotification'],
            optional: const ['serviceImprovement'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 앱 상수 기준의 필수 둘만 수락한다.
      await tester.tap(find.byType(Checkbox).at(_rowOf('serviceData')));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(_rowOf('sensitiveData')));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(find.text('필수 항목에 모두 동의해야 가입할 수 있어요.'), findsOneWidget);
    });

    testWidgets('서버가 선택으로 준 항목은 없어도 제출한다', (tester) async {
      // 앱 상수는 건강 민감정보를 필수로 둔다. 서버가 선택으로 내리면 그것만
      // 빼고도 가입이 되어야 한다.
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
          extra: _pending(
            required: const ['serviceData'],
            optional: const [
              'sensitiveData',
              'pushNotification',
              'serviceImprovement',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).at(_rowOf('serviceData')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '동의하고 시작하기'));
      await tester.pumpAndSettle();

      expect(sent!['consents'], {
        'serviceData': true,
        'sensitiveData': false,
        'pushNotification': false,
        'serviceImprovement': false,
      }, reason: '계약의 네 항목은 그대로 보내고 고르지 않은 것은 거부로 보낸다');
      expect(find.text('처음 오셨네요'), findsOneWidget);
    });

    testWidgets('필수 표시도 서버 목록을 따른다', (tester) async {
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(MockClient((request) async => fail('제출하지 않는다'))),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(
            required: const ['serviceData'],
            optional: const [
              'sensitiveData',
              'pushNotification',
              'serviceImprovement',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('[필수]', findRichText: true),
        findsOneWidget,
        reason: '서버가 하나만 필수로 주면 화면에도 하나만 필수로 보여야 한다',
      );
    });

    testWidgets('서버가 앱에 없는 항목을 필수로 요구하면 동의를 받지 않는다', (tester) async {
      // 문구를 보여줄 수 없으면 동의를 받을 수도 없다. 약관 버전이 다를 때와
      // 같은 이유로 막되, 무엇이 달라졌는지 구분되게 다른 문구를 쓴다.
      _tallScreen(tester);

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              fail('보여주지 않은 항목에 동의를 받아 보내지 않는다');
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          home: const SizedBox.shrink(),
          extra: _pending(
            required: const ['serviceData', 'sensitiveData', 'locationData'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('동의 항목이 바뀌었어요'), findsOneWidget);
      expect(find.textContaining('약관이 새로 바뀌었어요'), findsNothing);
      expect(find.text('로그인으로 돌아가기'), findsOneWidget);
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

  group('세션 보관', () {
    testWidgets('로그인에 성공하면 세션을 단말에 보관한다', (tester) async {
      final store = _FakeSessionStore();

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async => _json(_authenticatedBody(), 200)),
          ),
          google: _FakeGoogleAuthenticator(token: 'fake-id-token'),
          store: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GoogleSignInButton));
      await tester.pumpAndSettle();

      expect(find.text('홈 화면'), findsOneWidget);
      expect(store.writes, 1, reason: '앱을 다시 켤 때 쓰려면 보관해야 한다');
      expect(store.stored!.accessToken, 'fake-session-token');
    });

    test('보관한 값은 그대로 되읽힌다', () {
      final result = AuthenticatedResult.fromJson(
        jsonDecode(_authenticatedBody()) as Map<String, dynamic>,
      );
      final session = AuthSession.fromResult(
        result,
        now: DateTime.utc(2026, 9, 18, 9),
      );

      final again = AuthSession.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
      );

      expect(again.accessToken, session.accessToken);
      expect(again.tokenType, session.tokenType);
      expect(again.expiresAt, session.expiresAt);
      expect(again.account.accountId, session.account.accountId);
      expect(again.account.displayName, session.account.displayName);
      expect(again.account.email, isNull, reason: '없는 값을 지어내지 않는다');
      expect(again.account.consentVersion, session.account.consentVersion);
    });

    test('절반만 읽어 로그인한 것처럼 넘기지 않는다', () {
      expect(
        () => AuthSession.fromJson({'tokenType': 'Bearer'}),
        throwsA(isA<AuthUnexpectedResponseFailure>()),
      );
      expect(
        () => AuthSession.fromJson({
          'accessToken': 'fake-session-token',
          'expiresAt': '2026-09-18T10:00:00Z',
        }),
        throwsA(isA<AuthUnexpectedResponseFailure>()),
      );
    });

    test('로그아웃하면 보관한 세션과 구글 쪽을 함께 지운다', () async {
      final store = _FakeSessionStore();
      final google = _FakeGoogleAuthenticator();
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          googleAuthenticatorProvider.overrideWithValue(google),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(sessionProvider.notifier)
          .start(
            AuthenticatedResult.fromJson(
              jsonDecode(_authenticatedBody()) as Map<String, dynamic>,
            ),
          );
      expect(container.read(sessionProvider), isNotNull);

      await container.read(sessionProvider.notifier).signOut();

      expect(container.read(sessionProvider), isNull);
      expect(store.stored, isNull, reason: '로그아웃하면 보관한 세션은 지워야 한다');
      expect(store.clears, 1);
      expect(
        google.signOutCalls,
        1,
        reason: '다음 로그인에서 계정을 다시 고를 수 있어야 한다',
      );
    });
  });

  group('앱을 다시 켰을 때', () {
    /// 보관해 둔 세션을 만든다.
    AuthSession keptSession({Duration remaining = const Duration(hours: 1)}) =>
        AuthSession(
          accessToken: 'kept-session-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(remaining),
          account: AuthAccount.fromJson(
            (jsonDecode(_authenticatedBody()) as Map<String, dynamic>)['account']
                as Map<String, dynamic>,
          ),
        );

    String accountBody() => jsonEncode(
      (jsonDecode(_authenticatedBody()) as Map<String, dynamic>)['account'],
    );

    testWidgets('보관한 세션이 없으면 로그인부터 시작한다', (tester) async {
      final store = _FakeSessionStore();

      await tester.pumpWidget(
        _app(
          api: _api(MockClient((request) async => fail('부를 일이 없다'))),
          google: _FakeGoogleAuthenticator(),
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(GoogleSignInButton), findsOneWidget);
    });

    testWidgets('살아 있는 세션이면 로그인 화면을 거치지 않는다', (tester) async {
      final store = _FakeSessionStore(keptSession());
      var asked = 0;

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              asked++;
              expect(request.url.path, '/auth/me');
              expect(
                request.headers['Authorization'],
                'Bearer kept-session-token',
              );
              return _json(accountBody(), 200);
            }),
          ),
          google: _FakeGoogleAuthenticator(),
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(asked, 1, reason: '보관한 값만 믿지 않고 서버에 확인한다');
      expect(find.text('홈 화면'), findsOneWidget);
    });

    testWidgets('서버가 세션을 거절하면 무음 로그인으로 새로 받는다', (tester) async {
      final store = _FakeSessionStore(keptSession());
      final google = _FakeGoogleAuthenticator(silentToken: 'silent-id-token');
      final paths = <String>[];

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              paths.add(request.url.path);
              if (request.url.path == '/auth/me') {
                return _json(_errorBody('UNAUTHORIZED'), 401);
              }
              return _json(_authenticatedBody(), 200);
            }),
          ),
          google: google,
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(paths, ['/auth/me', '/auth/google']);
      expect(google.silentCalls, 1, reason: '로그인 버튼을 다시 누르게 하지 않는다');
      expect(find.text('홈 화면'), findsOneWidget);
      expect(
        store.stored!.accessToken,
        'fake-session-token',
        reason: '새로 받은 세션을 보관한다',
      );
    });

    testWidgets('만료된 세션은 확인하지 않고 바로 새로 받는다', (tester) async {
      final store = _FakeSessionStore(
        keptSession(remaining: const Duration(seconds: -1)),
      );
      final google = _FakeGoogleAuthenticator(silentToken: 'silent-id-token');
      final paths = <String>[];

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async {
              paths.add(request.url.path);
              return _json(_authenticatedBody(), 200);
            }),
          ),
          google: google,
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(paths, ['/auth/google'], reason: '이미 만료됐으므로 확인할 것이 없다');
      expect(find.text('홈 화면'), findsOneWidget);
    });

    testWidgets('무음 로그인도 안 되면 보관한 세션을 버리고 로그인으로 보낸다', (tester) async {
      final store = _FakeSessionStore(
        keptSession(remaining: const Duration(seconds: -1)),
      );

      await tester.pumpWidget(
        _app(
          api: _api(MockClient((request) async => fail('부를 토큰이 없다'))),
          google: _FakeGoogleAuthenticator(),
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(GoogleSignInButton), findsOneWidget);
      expect(store.stored, isNull, reason: '되살릴 수 없는 세션은 남기지 않는다');
    });

    testWidgets('서버에 닿지 못해도 만료 전 세션은 버리지 않는다', (tester) async {
      // 비행기 모드에서 앱을 열었다고 로그인이 풀리면 안 된다. 확인하지
      // 못했을 뿐 만료된 것은 아니다.
      final store = _FakeSessionStore(keptSession());

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient(
              (request) async => throw const SocketException('오프라인'),
            ),
          ),
          google: _FakeGoogleAuthenticator(),
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('홈 화면'), findsOneWidget);
      expect(store.stored, isNotNull);
    });

    testWidgets('계정이 사라졌으면 동의 화면으로 보내지 않는다', (tester) async {
      // 가입은 사용자가 로그인 화면에서 스스로 시작해야 한다(ADR-007).
      final store = _FakeSessionStore(
        keptSession(remaining: const Duration(seconds: -1)),
      );

      await tester.pumpWidget(
        _app(
          api: _api(
            MockClient((request) async => _json(_consentRequiredBody(), 200)),
          ),
          google: _FakeGoogleAuthenticator(silentToken: 'silent-id-token'),
          store: store,
          initialLocation: AppRoutes.splash,
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(GoogleSignInButton), findsOneWidget);
      expect(find.text('약관 동의'), findsNothing);
      expect(store.stored, isNull);
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
