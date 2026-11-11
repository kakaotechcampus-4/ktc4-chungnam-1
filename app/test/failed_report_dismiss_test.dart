// 홈의 `리포트를 만들지 못했어요` 알림을 × 로 지우는 것을 확인한다
// (2026-11-11 FE 결정, 확인 창 문구는 PM 확인 전).
//
// 실패 배너는 화살표 대신 오른쪽 위에 × 를 둔다. × 를 누르면 한 번 더 묻고,
// 지우면 홈과 알림 화면에서 사라진다. 지운 회차는 단말에 남겨 앱을 다시 켜도
// 띄우지 않는다. 다른 배너는 지금처럼 화살표를 둔다.
//
// 서버는 `FakeProfileServer` 와 `FakeReportServer`, 단말 기억은 이 파일의
// `FakeDismissedFailedReportStore` 다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/dismissed_failed_report_store.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_dismissed_failed_report_store.dart';
import 'fake_pending_uploads.dart';
import 'fake_profile_server.dart';
import 'fake_report_server.dart';

const _sessionId = 's1';
const _account = 'account-a';
const _retryPath = '/api/v1/speech-analyses/a1/retry';

AuthSession _session() => AuthSession(
  accessToken: 'token',
  tokenType: 'Bearer',
  expiresAt: DateTime(2100),
  account: const AuthAccount(
    accountId: _account,
    authProvider: 'google',
    displayName: '테스트 보호자',
    email: null,
    consentVersion: null,
    createdAt: null,
  ),
);

FakeReportServer _server({String status = 'failed'}) => FakeReportServer(
  sessions: {
    'p1': [
      FakeReportServer.session(
        id: _sessionId,
        status: status,
        analysisId: 'a1',
      ),
    ],
  },
);

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

late GoRouter _router;

/// 로그인한 상태로 홈을 연다. 기준 화면은 412 x 917 dp 다. 매번 새로 만들어
/// 앱을 다시 켠 것과 같다.
Future<void> _open(
  WidgetTester tester, {
  required FakeReportServer server,
  required DismissedFailedReportStore store,
  PendingUploads? uploads,
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
      profileSampleProvider.overrideWith((ref) async => sample),
      reportPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 10),
      ),
      pendingUploadsProvider.overrideWith(
        (ref) => uploads ?? FakePendingUploads(),
      ),
      dismissedFailedReportStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider.notifier).restore(_session());

  final router = _router = buildRouter();
  addTearDown(router.dispose);
  router.go(AppRoutes.home);

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

Finder get _banner => find.text('리포트를 만들지 못했어요');

Finder get _close => find.byTooltip('알림 지우기');

Finder get _dialog => find.byType(Dialog);

void main() {
  group('홈의 실패 알림 지우기', () {
    testWidgets('실패 배너는 화살표 대신 × 를 둔다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(
        tester,
        server: _server(),
        store: FakeDismissedFailedReportStore(),
      );

      expect(_banner, findsOneWidget);
      expect(_close, findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      final button = find.ancestor(
        of: _close,
        matching: find.byType(IconButton),
      );
      // 화면 읽기에서 × 를 무엇인지 읽어 준다. 뒤로 버튼(`AppTopBar`)과 같이
      // 툴팁으로 읽힌다.
      expect(
        tester.getSemantics(button),
        isSemantics(tooltip: '알림 지우기', isButton: true, hasTapAction: true),
      );
      // 누르는 영역이 48 이상이다.
      final box = tester.getSize(button);
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    testWidgets('× 를 누르면 다시 요청하지 않고 한 번 더 묻는다', (tester) async {
      final server = _server();
      await _open(
        tester,
        server: server,
        store: FakeDismissedFailedReportStore(),
      );

      await _tap(tester, _close);

      expect(_dialog, findsOneWidget);
      expect(find.text('이 알림을 지울까요?'), findsOneWidget);
      expect(find.text('지우면 이 면회의 리포트를\n다시 요청할 수 없어요.'), findsOneWidget);
      expect(server.count(_retryPath), 0);
      expect(_router.state.uri.toString(), AppRoutes.home);
    });

    testWidgets('취소하면 알림이 그대로 남는다', (tester) async {
      final store = FakeDismissedFailedReportStore();
      await _open(tester, server: _server(), store: store);

      await _tap(tester, _close);
      await _tap(tester, find.text('취소'));

      expect(_dialog, findsNothing);
      expect(_banner, findsOneWidget);
      expect(store.values, isEmpty);
    });

    testWidgets('지우면 홈과 알림 화면에서 사라지고 그 회차를 단말에 남긴다', (tester) async {
      final server = _server();
      final store = FakeDismissedFailedReportStore();
      await _open(tester, server: server, store: store);

      await _tap(tester, _close);
      await _tap(tester, find.text('지우기'));

      expect(_banner, findsNothing);
      expect(store.values[_account], {_sessionId});
      expect(server.count(_retryPath), 0);

      _router.push(AppRoutes.notifications);
      await _settle(tester);
      expect(find.text('아직 새 알림이 없어요.'), findsOneWidget);
    });

    testWidgets('지운 회차는 앱을 다시 켜도 띄우지 않는다', (tester) async {
      final store = FakeDismissedFailedReportStore()
        ..values[_account] = {_sessionId};
      await _open(tester, server: _server(), store: store);

      expect(_banner, findsNothing);
    });

    testWidgets('다른 회차를 지웠으면 이 회차의 실패는 띄운다', (tester) async {
      final store = FakeDismissedFailedReportStore()..values[_account] = {'s0'};
      await _open(tester, server: _server(), store: store);

      expect(_banner, findsOneWidget);
    });

    testWidgets('다른 계정이 지운 회차는 이 계정에서 띄운다', (tester) async {
      final store = FakeDismissedFailedReportStore()
        ..values['account-b'] = {_sessionId};
      await _open(tester, server: _server(), store: store);

      expect(_banner, findsOneWidget);
    });

    testWidgets('평가 이어서 하기 배너는 × 없이 화살표를 둔다', (tester) async {
      await _open(
        tester,
        server: _server(status: 'evaluationPending'),
        store: FakeDismissedFailedReportStore(),
      );

      expect(find.text('평가 이어서 하기'), findsOneWidget);
      expect(_close, findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('보안 저장소', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Map<String, String> values;

    setUp(() {
      values = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final args = (call.arguments as Map).cast<String, Object?>();
              final key = args['key'] as String?;
              switch (call.method) {
                case 'read':
                  return values[key];
                case 'write':
                  values[key!] = args['value']! as String;
                  return null;
                case 'delete':
                  values.remove(key);
                  return null;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    SecureDismissedFailedReportStore store() =>
        SecureDismissedFailedReportStore(storage: const FlutterSecureStorage());

    test('계정마다 나눠 기억하고 탈퇴하면 지운다', () async {
      await store().add('a', 's1');
      await store().add('a', 's2');
      await store().add('b', 's3');

      expect(await store().read('a'), {'s1', 's2'});
      expect(await store().read('b'), {'s3'});

      await store().clear('a');
      expect(await store().read('a'), isEmpty);
      expect(await store().read('b'), {'s3'});
    });

    test('오래된 것부터 50개만 남긴다', () async {
      for (var i = 0; i < 55; i++) {
        await store().add('a', 's$i');
      }

      final ids = await store().read('a');
      expect(ids, hasLength(50));
      expect(ids, isNot(contains('s0')));
      expect(ids, contains('s54'));
    });

    test('깨진 값은 비어 있다고 읽고 다음에 새로 적는다', () async {
      values['saerok.report.dismissedFailed.a'] = '{not json';

      expect(await store().read('a'), isEmpty);
      await store().add('a', 's1');
      expect(await store().read('a'), {'s1'});
    });
  });
}
