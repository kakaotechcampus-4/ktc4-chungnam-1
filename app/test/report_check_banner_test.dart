// 홈과 알림 화면의 `리포트 상태를 확인하지 못했어요` 배너를 확인한다
// (2026-11-10 UX 점검 17번).
//
// 만드는 중에 다시 시도할 수 없는 실패가 오면 `리포트를 만들고 있어요` 가 끝없이
// 돌았고, `눌러서 다시 확인하기` 를 누르면 배너가 먼저 사라졌다가 최대 15초 뒤
// 다시 나타났다. 이제 누를 수 있는 배너로 바꾸고, 다시 묻는 동안에는 배너를 두고
// 도는 표시를 보인다.
//
// 서버는 `FakeProfileServer` 와 `FakeReportServer` 다. 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';

import 'fake_card_api.dart';
import 'fake_profile_server.dart';
import 'fake_report_server.dart';

const _title = '리포트 상태를 확인하지 못했어요';
const _tapHint = '눌러서 다시 확인하기';
const _checkingHint = '다시 확인하고 있어요';
const _sessionsPath = '/api/v1/profiles/p1/visit-sessions';

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

/// 가짜 서버의 실제 비동기 처리를 기다리고 화면을 맞춘다. 만드는 중 배너는
/// 계속 돌아서 pumpAndSettle 을 쓰지 않는다.
Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 로그인한 상태로 [location] 을 연다. 기준 화면은 412 x 917 dp 다.
Future<void> _open(
  WidgetTester tester,
  FakeReportServer server, {
  String location = AppRoutes.home,
}) async {
  tester.view.physicalSize = const Size(412, 917) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final sample = (await tester.runAsync(
    () => const MockRepository().loadProfile(),
  ))!;
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(id: 'p1', setupStatus: 'completed'),
        ],
      ).override,
      server.override,
      cardApiProvider.overrideWithValue(FakeCardApi()),
      profileSampleProvider.overrideWith((ref) async => sample),
      reportPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 10),
      ),
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
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await _settle(tester);
}

/// [text] 를 담은 배너 안의 도는 표시.
Finder _spinnerNear(String text) => find.descendant(
  of: find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first,
  matching: find.byType(CircularProgressIndicator),
);

void main() {
  group('홈 배너', () {
    testWidgets('누르면 다시 묻는 동안 배너를 두고 도는 표시를 보이며 다시 누르지 않는다', (tester) async {
      final server = FakeReportServer(
        sessions: {
          'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
        },
      )..offline = true;
      await _open(tester, server);
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_tapHint), findsOneWidget);

      server
        ..offline = false
        ..hold = Completer<void>();
      await tester.tap(find.text(_title));
      await _settle(tester, rounds: 2);

      expect(find.text(_title), findsOneWidget, reason: '묻는 동안 배너를 지우지 않는다');
      expect(find.text(_checkingHint), findsOneWidget);
      expect(_spinnerNear(_title), findsOneWidget);
      final asked = server.count(_sessionsPath);
      await tester.tap(find.text(_title));
      await _settle(tester, rounds: 2);
      expect(server.count(_sessionsPath), asked, reason: '묻는 중에는 누름을 받지 않는다');

      server.hold!.complete();
      await _settle(tester);
      expect(find.text('리포트가 도착했어요'), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('다시 물어도 실패하면 다시 누를 수 있는 배너로 돌아온다', (tester) async {
      final server = FakeReportServer(
        sessions: {
          'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
        },
      )..offline = true;
      await _open(tester, server);

      await tester.tap(find.text(_title));
      await _settle(tester);

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_tapHint), findsOneWidget);
      expect(find.text(_checkingHint), findsNothing);
      expect(_spinnerNear(_title), findsNothing);
    });

    testWidgets('만드는 중에 다시 시도할 수 없는 실패가 오면 누를 수 있는 배너로 바꾼다', (tester) async {
      final server = FakeReportServer(
        sessions: {
          'p1': [
            FakeReportServer.session(
              id: 's1',
              status: 'processing',
              analysisId: 'a1',
            ),
          ],
        },
        analyses: {
          'a1': ['transcribing'],
        },
      );
      await _open(tester, server);
      expect(find.text('리포트를 만들고 있어요'), findsOneWidget);

      server.failures['GET /api/v1/speech-analyses/a1'] = (
        status: 500,
        errorCode: 'INTERNAL_ERROR',
      );
      await _settle(tester);

      expect(find.text('리포트를 만들고 있어요'), findsNothing, reason: '끝없이 돌지 않는다');
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_tapHint), findsOneWidget);
      expect(find.text('10월 13일 만남'), findsOneWidget, reason: '어느 만남인지 둔다');

      server.failures.clear();
      server.analyses['a1'] = ['completed'];
      await tester.tap(find.text(_title));
      await _settle(tester);
      expect(find.text('리포트가 도착했어요'), findsOneWidget);
    });
  });

  testWidgets('알림 화면도 다시 묻는 동안 알림을 두고 누르지 않는다', (tester) async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    )..offline = true;
    await _open(tester, server, location: AppRoutes.notifications);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_tapHint), findsOneWidget);

    server
      ..offline = false
      ..hold = Completer<void>();
    await tester.tap(find.text(_title));
    await _settle(tester, rounds: 2);

    expect(find.text(_title), findsOneWidget);
    expect(find.text(_checkingHint), findsOneWidget);
    expect(find.text('아직 새 알림이 없어요.'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    server.hold!.complete();
    await _settle(tester);
    expect(find.text('리포트가 도착했어요'), findsOneWidget);
  });
}
