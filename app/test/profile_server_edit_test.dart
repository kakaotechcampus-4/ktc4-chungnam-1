// 로그인한 상태에서 프로필 수정과 어르신 지우기가 서버(`api-spec.md` 2-4,
// 2-8)에 저장되는지 확인한다.
//
// 서버는 `FakeProfileServer` 다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
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

/// 실제 비동기 처리(가짜 서버, asset 읽기)를 기다리고 화면을 맞춘다.
///
/// 로딩이 도는 동안에는 `pumpAndSettle` 이 끝나지 않으므로, 로딩이 사라질
/// 때까지 실제 시간을 조금씩 흘려보낸다.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (i >= 2 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

/// 로그인한 상태로 [location] 을 연다. 서버에는 등록을 마친 분이 한 분 있다.
Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeProfileServer server,
  String location,
) async {
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // 목 데이터(asset)는 실제 시간에서 먼저 읽어 넣는다. 화면 안에서 읽으면 가짜
  // 시간에서는 끝나지 않을 수 있다.
  final sample = (await tester.runAsync(
    () => const MockRepository().loadProfile(),
  ))!;
  final account = (await tester.runAsync(
    () => const MockRepository().loadAccount(),
  ))!;
  final container = ProviderContainer(
    overrides: [
      server.override,
      FakeReportServer().override,
      profileSampleProvider.overrideWith((ref) async => sample),
      accountProvider.overrideWith((ref) async => account),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).restore(_session());

  final router = buildRouter();
  addTearDown(router.dispose);
  router.go(location);

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
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  // 어르신 목록을 서버에서 다 불러올 때까지 기다린다. 그 전에는 로딩이 돈다.
  for (var i = 0; i < 50; i++) {
    if (!container.read(careProfilesProvider).isLoading) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await _settle(tester);
  return container;
}

FakeProfileServer _server() => FakeProfileServer(
  profiles: [
    FakeProfileServer.profile(
      id: 'p1',
      setupStatus: 'completed',
      occupation: '재봉 일을 오래 하셨어요.',
      family: '2남 1녀를 두셨어요.',
    ),
  ],
);

void main() {
  group('프로필 설정의 수정', () {
    testWidgets('기본 정보를 서버에 저장하고 바로 보여준다', (tester) async {
      final server = _server();
      await _open(tester, server, AppRoutes.profile);
      expect(find.text('김새록 어르신'), findsOneWidget);

      await _tap(tester, find.text('수정하기').first);
      await tester.enterText(find.byType(TextField), '김새봄');
      await tester.pump();
      await _tap(tester, find.widgetWithText(FilledButton, '저장하기'));

      final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/api/v1/profiles/p1');
      expect((patch.body as Map)['name'], '김새봄');
      expect(find.text('기본 정보를 저장했어요.'), findsOneWidget);
      expect(find.text('김새봄 어르신'), findsOneWidget);
    });

    testWidgets('세부 정보를 비우면 서버에 null 로 보내 지운다', (tester) async {
      final server = _server();
      final container = await _open(tester, server, AppRoutes.profile);

      await _tap(tester, find.text('수정하기').at(1));
      final family = find.descendant(
        of: find
            .ancestor(of: find.text('가족'), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      );
      await tester.enterText(family, '');
      await tester.pump();
      await _tap(tester, find.widgetWithText(FilledButton, '저장하기'));

      final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect((patch.body as Map)['family'], isNull);
      expect((patch.body as Map)['occupation'], '재봉 일을 오래 하셨어요.');
      expect(server.profiles.single['family'], isNull);
      expect(
        container.read(careProfilesProvider).selected!.details.family,
        isNull,
      );
      expect(find.text('2남 1녀를 두셨어요.'), findsNothing);
    });

    testWidgets('서버에 닿지 못하면 알리고 수정 화면에 남는다', (tester) async {
      final server = _server();
      final container = await _open(tester, server, AppRoutes.profile);

      await _tap(tester, find.text('수정하기').first);
      await tester.enterText(find.byType(TextField), '김새봄');
      await tester.pump();
      server.offline = true;
      await _tap(tester, find.widgetWithText(FilledButton, '저장하기'));

      expect(
        find.text('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.'),
        findsOneWidget,
      );
      expect(find.text('기본 정보 수정'), findsOneWidget);
      expect(
        container.read(careProfilesProvider).selected!.basicInfo!.name,
        '김새록',
        reason: '저장하지 못한 값을 반영하지 않는다',
      );
    });
  });

  group('어르신 지우기', () {
    Future<void> remove(WidgetTester tester) async {
      await _tap(tester, find.text('소중한 분 정보 지우기'));
      await _tap(tester, find.text('김새록 어르신'));
      await _tap(tester, find.text('지우기'));
    }

    testWidgets('서버에서 지운 뒤 슬롯을 비운다', (tester) async {
      final server = _server();
      final container = await _open(tester, server, AppRoutes.profileSwitch);

      await remove(tester);

      final delete = server.requests.lastWhere((r) => r.method == 'DELETE');
      expect(delete.path, '/api/v1/profiles/p1');
      expect(server.profiles, isEmpty);
      expect(container.read(careProfilesProvider).entries, isEmpty);
    });

    testWidgets('서버에서 지우지 못하면 알리고 그대로 둔다', (tester) async {
      final server = _server();
      final container = await _open(tester, server, AppRoutes.profileSwitch);
      server.offline = true;

      await remove(tester);

      expect(
        find.text('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해주세요.'),
        findsOneWidget,
      );
      expect(container.read(careProfilesProvider).entries, hasLength(1));
    });
  });

  group('어르신 목록을 불러오지 못하면', () {
    testWidgets('홈은 등록 안내 대신 다시 시도를 보여준다', (tester) async {
      final server = _server()..offline = true;
      final container = await _open(tester, server, AppRoutes.home);

      expect(
        find.text('어르신 정보를 불러오지 못했어요.\n인터넷 연결을 확인하고 다시 시도해주세요.'),
        findsOneWidget,
      );
      expect(find.text('어르신을 먼저 등록해주세요'), findsNothing);

      server.offline = false;
      await _tap(tester, find.text('다시 시도'));

      expect(container.read(careProfilesProvider).hasSelected, isTrue);
      expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
    });
  });
}
