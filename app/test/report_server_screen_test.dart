// 로그인한 상태의 홈 알림, 리포트, 리포트 기록과 변경 사항 확인이 서버
// (`api-spec.md` 5-4, 6-4, 7-1 ~ 7-4)의 값을 보여주는지 확인한다.
//
// 서버는 `FakeProfileServer` 와 `FakeReportServer` 다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// 실제 비동기 처리(가짜 서버)를 기다리고 화면을 맞춘다.
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

/// 마지막으로 연 화면의 라우터. 이동한 주소를 확인할 때 쓴다.
late GoRouter _router;

/// 로그인한 상태로 [location] 을 연다. 서버에는 등록을 마친 분이 한 분 있다.
Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeReportServer reports,
  String location,
) async {
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  // 목 데이터(asset)는 실제 시간에서 먼저 읽어 넣는다.
  final sample = (await tester.runAsync(
    () => const MockRepository().loadProfile(),
  ))!;
  final container = ProviderContainer(
    overrides: [
      FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(id: 'p1', setupStatus: 'completed'),
        ],
      ).override,
      reports.override,
      // 평가 이어서 하기 화면이 쓸 카드 묶음을 묻는다(4-3).
      cardApiProvider.overrideWithValue(FakeCardApi()),
      profileSampleProvider.overrideWith((ref) async => sample),
      // 홈을 띄운 채로 테스트가 끝나므로 폴링이 길게 남지 않게 한다.
      reportPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 10),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).restore(_session());

  final router = _router = buildRouter();
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
  return container;
}

FakeReportServer _completed({String? imageUrl}) => FakeReportServer(
  sessions: {
    'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
  },
  reports: {'s1': FakeReportServer.report(sessionId: 's1', imageUrl: imageUrl)},
  evaluations: {'s1': FakeReportServer.evaluation('s1')},
  proposals: {'s1': FakeReportServer.proposal('s1')},
);

void main() {
  group('홈', () {
    testWidgets('도착한 리포트를 눌러 서버의 리포트를 연다', (tester) async {
      final server = _completed();
      await _open(tester, server, AppRoutes.home);

      expect(find.text('10월 13일 만남'), findsOneWidget);
      await _tap(tester, find.text('리포트가 도착했어요'));

      expect(server.count('/api/v1/visit-sessions/s1/report'), 1);
      expect(find.text('재봉 일 이야기를 나눈 날'), findsOneWidget);
      expect(find.text('오늘은 재봉 일을 하시던 시절 이야기를 나눴어요.'), findsOneWidget);
      expect(find.text('수선집 시절'), findsOneWidget);
      expect(find.text('한복을 주로 만드셨다고 하셨어요.'), findsOneWidget);
      // 6-4 에서 쓰지 않았다고 답한 카드다.
      expect(find.text('이번 면회에서 다루지 않았어요'), findsOneWidget);
      // 사진 없이 한 면회에는 목 그림을 채우지 않는다.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('리포트를 만들지 못했으면 실패를 알리고 누를 곳을 두지 않는다', (tester) async {
      final server = FakeReportServer(
        sessions: {
          'p1': [FakeReportServer.session(id: 's1', status: 'failed')],
        },
      );
      await _open(tester, server, AppRoutes.home);

      expect(find.text('리포트를 만들지 못했어요'), findsOneWidget);
      expect(find.text('리포트가 도착했어요'), findsNothing);
      expect(find.text('눌러서 확인하기'), findsNothing);
    });
  });

  group('앱을 떠난 사이 멈춘 면회', () {
    for (final (status, title, location) in [
      ('evaluationPending', '평가 이어서 하기', '/visit/review?session=s1'),
      ('audioPending', '음성 다시 보내기', '/visit/upload?session=s1'),
    ]) {
      testWidgets('$status 이면 $title 를 눌러 그 회차로 간다', (tester) async {
        final server = FakeReportServer(
          sessions: {
            'p1': [FakeReportServer.session(id: 's1', status: status)],
          },
        );
        await _open(tester, server, AppRoutes.home);

        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text(title));
        await _settle(tester);

        expect(_router.state.uri.toString(), location);
      });
    }
  });

  testWidgets('리포트 기록은 서버의 기록을 보여주고 회차로 연다', (tester) async {
    final server = _completed();
    await _open(tester, server, AppRoutes.reports);

    expect(server.count('/api/v1/profiles/p1/reports'), 1);
    expect(find.text('지난 만남 1개'), findsOneWidget);

    await _tap(tester, find.text('재봉 일 이야기를 나눈 날'));

    expect(server.count('/api/v1/visit-sessions/s1/report'), 1);
    expect(find.text('오늘의 만남'), findsOneWidget);
    expect(find.text('변경 사항 확인하기'), findsNothing);
  });

  group('변경 사항 확인', () {
    testWidgets('서버의 제안을 보여주고 반영하면 보낸 뒤 알림을 지운다', (tester) async {
      final server = _completed();
      final container = await _open(tester, server, AppRoutes.reportOf('s1'));

      await _tap(tester, find.text('변경 사항 확인하기'));
      expect(find.text('한복을 주로 만드셨어요.'), findsOneWidget);

      await _tap(tester, find.text('이대로 반영하기'));

      final sent = server.requests.lastWhere((r) => r.method == 'POST');
      expect(sent.path, '/api/v1/visit-sessions/s1/proposals/review');
      expect(container.read(reportNoticeProvider), isNull);
      expect(find.text('리포트가 도착했어요'), findsNothing);
    });

    testWidgets('보내지 못하면 알리고 이 화면에 남는다', (tester) async {
      final server = _completed()
        ..failures['POST /api/v1/visit-sessions/s1/proposals/review'] = (
          status: 409,
          errorCode: 'PROPOSAL_ALREADY_REVIEWED',
        );
      await _open(tester, server, AppRoutes.reportOf('s1'));

      await _tap(tester, find.text('변경 사항 확인하기'));
      await _tap(tester, find.text('이대로 반영하기'));

      expect(find.text('이미 확인을 마친 변경 사항이에요.'), findsOneWidget);
      expect(find.text('이대로 반영하기'), findsOneWidget);
    });
  });
}
