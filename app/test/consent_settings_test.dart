// 프로필 설정의 계정 약관 동의가 서버(`api-spec.md` 1-3, 1-6)와 이어지는지
// 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성이다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        if (request.method == 'PATCH') {
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

  group('프로필 설정의 동의 저장', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, _FakeAccountServer server) async {
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
          profileSampleProvider.overrideWith((ref) async => sample),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).restore(_session());

      // 저장한 뒤 이전 화면으로 돌아가는지 보려고 홈 위에 연다.
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
      router.push(AppRoutes.profile);
      await settle(tester);
    }

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
      expect(find.text('계정 약관 동의'), findsNothing, reason: '저장하면 화면을 닫는다');
    });

    testWidgets('바꾼 것이 없으면 서버에 보내지 않는다', (tester) async {
      final server = _FakeAccountServer();
      await open(tester, server);

      await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
      await settle(tester);

      expect(server.requests.where((r) => r.method == 'PATCH'), isEmpty);
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
  });
}
