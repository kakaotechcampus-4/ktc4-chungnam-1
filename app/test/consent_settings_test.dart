// 프로필 설정의 계정 약관 동의가 서버(`api-spec.md` 1-3, 1-6)와 이어지는지
// 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성이다.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/account_api.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/session_store.dart';

import 'fake_profile_server.dart';
import 'fake_report_server.dart';

AuthSession _session() => AuthSession(
  accessToken: 'token',
  tokenType: 'Bearer',
  expiresAt: DateTime(2100),
  account: const AuthAccount(
    accountId: 'account-a',
    authProvider: 'google',
    displayName: '테스트 보호자',
    email: null,
    consentVersion: null,
    createdAt: null,
  ),
);

class _FakeGoogle implements GoogleAuthenticator {
  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> silentIdToken() async => null;

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

/// 계정 API 를 흉내 낸다. 동의는 [consent] 에 두고 1-6 이 보낸 항목만 바꾼다.
class _FakeAccountServer {
  final consent = <String, bool>{
    'serviceData': true,
    'sensitiveData': true,
    'serviceImprovement': false,
    'pushNotification': true,
  };

  final requests = <({String method, String path, Object? body})>[];

  /// 연결이 끊긴 것처럼 1-6 을 실패시킨다.
  bool patchOffline = false;

  /// 정해 두면 1-6 은 이 Future 가 끝난 뒤에 저장하고 답한다.
  Future<void>? patchHold;

  /// 세션이 만료된 것처럼 1-3 을 401 로 거절한다.
  bool meRejected = false;

  /// 정해 두면 로그아웃(1-5)은 이 Future 가 끝난 뒤에 답한다.
  Future<void>? logoutHold;

  AccountApi get api => AccountApi(
    ApiClient(
      authorization: () => 'Bearer fake-token',
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        final body = request.body.isEmpty ? null : jsonDecode(request.body);
        requests.add((
          method: request.method,
          path: request.url.path,
          body: body,
        ));
        if (request.method == 'GET' && meRejected) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'schemaVersion': 1,
                'errorCode': 'SESSION_EXPIRED',
                'message': '테스트',
                'requestId': 'r',
                'retryable': false,
              }),
            ),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PATCH') {
          await patchHold;
          if (patchOffline) throw http.ClientException('오프라인');
          consent.addAll((body as Map).cast<String, bool>());
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(_account())),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );

  Map<String, Object?> _account() => {
    'schemaVersion': 1,
    'accountId': 'account-a',
    'authProvider': 'google',
    'displayName': '테스트 보호자',
    'email': null,
    'consent': {
      'consentVersion': '2026-09-06',
      for (final entry in consent.entries)
        entry.key: {
          'granted': entry.value,
          'grantedAt': entry.value ? '2026-10-18T10:00:00+09:00' : null,
        },
    },
    'createdAt': '2026-10-18T10:00:00+09:00',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('계정 API', () {
    test('1-3 으로 지금 계정과 동의를 읽는다', () async {
      final server = _FakeAccountServer();

      final account = await server.api.me();

      expect(server.requests.single.path, '/auth/me');
      expect(account.consent['pushNotification']!.granted, isTrue);
      expect(account.consent['serviceImprovement']!.granted, isFalse);
    });

    test('1-6 에는 보낸 항목만 담는다', () async {
      final server = _FakeAccountServer();

      final account = await server.api.updateConsents({
        'serviceImprovement': true,
      });

      final sent = server.requests.single;
      expect(sent.method, 'PATCH');
      expect(sent.path, '/auth/me/consents');
      expect(sent.body, {'serviceImprovement': true});
      expect(account.consent['serviceImprovement']!.granted, isTrue);
    });

    test('로그인했으면 계정을 서버에서, 아니면 목에서 읽는다', () async {
      final server = _FakeAccountServer();
      final online = ProviderContainer(
        overrides: [accountApiProvider.overrideWithValue(server.api)],
      );
      addTearDown(online.dispose);
      online.read(sessionProvider.notifier).restore(_session());

      expect(
        (await online.read(accountProvider.future)).accountId,
        'account-a',
      );
      expect(server.requests.single.path, '/auth/me');

      final offline = ProviderContainer(
        overrides: [accountApiProvider.overrideWithValue(server.api)],
      );
      addTearDown(offline.dispose);
      await offline.read(accountProvider.future);
      expect(server.requests, hasLength(1), reason: '로그인하지 않았으면 서버에 묻지 않는다');
    });
  });

  group('설정의 동의 저장', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<GoRouter> open(
      WidgetTester tester,
      _FakeAccountServer server,
    ) async {
      tester.view.physicalSize = const Size(1236, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final sample = (await tester.runAsync(
        () => const MockRepository().loadProfile(),
      ))!;
      final container = ProviderContainer(
        overrides: [
          FakeProfileServer().override,
          FakeReportServer().override,
          accountApiProvider.overrideWithValue(server.api),
          // 로그아웃(1-5)은 세션이 만료됐어도 단말 세션을 지운다.
          authApiProvider.overrideWithValue(
            AuthApi(
              baseUrl: 'http://api.test',
              client: MockClient((_) async {
                await server.logoutHold;
                return http.Response('', 401);
              }),
            ),
          ),
          googleAuthenticatorProvider.overrideWithValue(_FakeGoogle()),
          sessionStoreProvider.overrideWithValue(_MemoryStore()),
          profileSampleProvider.overrideWith((ref) async => sample),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).restore(_session());

      // 하단 탭처럼 홈 위에 설정을 연다.
      final router = buildRouter();
      addTearDown(router.dispose);
      router.go(AppRoutes.home);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: router,
            ),
          ),
        );
      });
      await settle(tester);
      router.push(AppRoutes.settings);
      await settle(tester);
      return router;
    }

    /// 그 동의 줄의 체크 상태.
    bool? checked(WidgetTester tester, String label) => tester
        .widget<Checkbox>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.textContaining(label, findRichText: true),
                  matching: find.byType(InkWell),
                )
                .first,
            matching: find.byType(Checkbox),
          ),
        )
        .value;

    testWidgets('바꾼 선택 동의만 서버에 저장하고 알린다', (tester) async {
      final server = _FakeAccountServer();
      await open(tester, server);

      await tester.tap(find.textContaining('서비스 개선 활용 동의', findRichText: true));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await settle(tester);

      final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.body, {
        'serviceImprovement': true,
      }, reason: '바꾸지 않은 항목은 보내지 않는다');
      expect(find.text('동의를 저장했어요.'), findsOneWidget);
      expect(
        find.text('계정 약관 동의'),
        findsOneWidget,
        reason: '설정은 탭 화면이라 저장해도 그대로 둔다',
      );
    });

    testWidgets('저장 중 화면을 떠나도 다시 열면 저장한 동의를 보여준다', (tester) async {
      final answer = Completer<void>();
      final server = _FakeAccountServer()..patchHold = answer.future;
      final router = await open(tester, server);

      await tester.tap(find.textContaining('서비스 개선 활용 동의', findRichText: true));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await tester.pump();
      // 응답이 오기 전에 뒤로 간다.
      router.pop();
      await settle(tester);
      expect(find.text('계정 약관 동의'), findsNothing);

      answer.complete();
      await settle(tester);
      expect(server.consent['serviceImprovement'], isTrue);

      router.push(AppRoutes.settings);
      await settle(tester);
      expect(checked(tester, '서비스 개선 활용 동의'), isTrue);
    });

    testWidgets('저장 중 연 회원탈퇴 화면은 저장을 마쳐도 닫지 않는다', (tester) async {
      final answer = Completer<void>();
      final server = _FakeAccountServer()..patchHold = answer.future;
      await open(tester, server);

      await tester.tap(find.textContaining('서비스 개선 활용 동의', findRichText: true));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await tester.pump();
      // 응답을 기다리는 동안 회원탈퇴 화면을 연다.
      await tester.tap(find.text('회원탈퇴'));
      await settle(tester);
      expect(find.textContaining('새록과 이별인가요?'), findsOneWidget);

      answer.complete();
      await settle(tester);

      expect(find.textContaining('새록과 이별인가요?'), findsOneWidget);
      expect(server.consent['serviceImprovement'], isTrue);
    });

    testWidgets('세션이 만료돼 계정을 읽지 못해도 로그아웃하고 다시 로그인할 수 있다', (tester) async {
      final server = _FakeAccountServer()..meRejected = true;
      final router = await open(tester, server);

      expect(find.text('계정 정보를 불러오지 못했어요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '로그아웃'));
      await settle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(sessionProvider), isNull);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Uri.parse(AppRoutes.signIn).path,
      );
    });

    testWidgets('로그아웃 응답이 늦어 화면이 바뀌어도 한 번에 로그인 화면으로 간다', (tester) async {
      final answer = Completer<void>();
      final server = _FakeAccountServer()
        ..meRejected = true
        ..logoutHold = answer.future;
      final router = await open(tester, server);

      await tester.tap(find.widgetWithText(TextButton, '로그아웃'));
      // 응답을 기다리는 동안 세션이 지워져 설정 화면이 다시 그려진다.
      await settle(tester);
      expect(find.text('계정 정보를 불러오지 못했어요.'), findsNothing);

      answer.complete();
      await settle(tester);

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Uri.parse(AppRoutes.signIn).path,
      );
    });

    testWidgets('바꾼 것이 없으면 서버에 보내지 않는다', (tester) async {
      final server = _FakeAccountServer();
      await open(tester, server);

      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await settle(tester);

      expect(server.requests.where((r) => r.method == 'PATCH'), isEmpty);
      expect(find.text('바꾼 동의가 없어요.'), findsOneWidget);
    });

    testWidgets('저장하지 못하면 알리고 화면에 남는다', (tester) async {
      final server = _FakeAccountServer()..patchOffline = true;
      await open(tester, server);

      await tester.tap(find.textContaining('알림 수신 동의', findRichText: true));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await settle(tester);

      expect(
        find.text('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.'),
        findsOneWidget,
      );
      expect(find.text('계정 약관 동의'), findsOneWidget);
      expect(server.consent['pushNotification'], isTrue, reason: '저장되지 않았다');
    });

    bool alertOn(WidgetTester tester) =>
        tester.widget<Switch>(find.byType(Switch)).value;

    const needsConsent = '아래 알림 수신 동의에 체크해야 알림을 켤 수 있어요.';

    testWidgets('알림 수신 동의 없이 알림을 켜려 하면 빨간 글로 알리고 켜지 않는다', (tester) async {
      final server = _FakeAccountServer();
      await open(tester, server);
      expect(alertOn(tester), isTrue, reason: '동의했으면 켜진 채로 시작한다');

      // 동의를 빼면 알림도 꺼진다.
      await tester.tap(find.textContaining('알림 수신 동의', findRichText: true));
      await tester.pump();
      expect(alertOn(tester), isFalse);
      expect(find.text(needsConsent), findsNothing);

      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(alertOn(tester), isFalse);
      expect(find.text(needsConsent), findsOneWidget);

      // 동의에 체크하면 안내가 사라지고 켤 수 있다. 안내 글에도 같은 이름이
      // 있어 아래의 동의 줄을 누른다.
      await tester.tap(
        find.textContaining('알림 수신 동의', findRichText: true).last,
      );
      await tester.pump();
      expect(find.text(needsConsent), findsNothing);
      expect(alertOn(tester), isTrue, reason: '동의에 체크하면 알림도 같이 켜진다');

      // 동의는 둔 채 스위치만 끄고 켤 수 있다.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(alertOn(tester), isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(alertOn(tester), isTrue);
    });

    testWidgets('계정 약관 동의에는 알림 쓰임새 문구를 두지 않는다', (tester) async {
      await open(tester, _FakeAccountServer());

      // 위 알림 설정에 한 번만 있다.
      expect(find.text('만남 리포트가 완성되면 알려드려요.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '로그아웃'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '회원탈퇴'), findsOneWidget);
    });
  });
}
