// 리포트를 만들지 못한 회차의 `녹음 파일 공유` 를 확인한다(2026-11-10 PM 결정).
//
// 홈 배너와 알림 화면의 실패 알림을 누르면, 이 기기에 녹음이 남아 있을 때만
// `분석 다시 요청하기` 와 `녹음 파일 공유` 를 고르는 시트를 띄운다. 녹음이 없으면
// 지금처럼 바로 분석 다시 요청하기 화면으로 간다. 그 화면에서 다시 요청하지
// 못했을 때도 녹음이 남았으면 공유를 둔다.
//
// 서버는 `FakeProfileServer` 와 `FakeReportServer`, 기기 기록은
// `FakePendingUploads`, 공유 창은 `FakeRecordingShare` 다. 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/recording_share.dart';

import 'fake_pending_uploads.dart';
import 'fake_profile_server.dart';
import 'fake_recording_share.dart';
import 'fake_report_server.dart';

const _sessionId = 's1';
const _analysisId = 'a1';
const _audioPath = '/fake/visit_recordings/visit-1.wav';
const _retryPath = '/api/v1/speech-analyses/$_analysisId/retry';

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

/// 리포트를 만들지 못한 회차가 하나 있는 서버.
FakeReportServer _failedServer() => FakeReportServer(
  sessions: {
    'p1': [
      FakeReportServer.session(
        id: _sessionId,
        status: 'failed',
        analysisId: _analysisId,
      ),
    ],
  },
);

/// 서버가 받은 뒤에도 기기에 남은 녹음.
FakePendingUploads _keptRecording() => FakePendingUploads()
  ..uploaded[_sessionId] = const PendingUpload(
    sessionId: _sessionId,
    audioPath: _audioPath,
    participantCount: 2,
  );

/// 녹음을 찾는 동안 멈춰 둘 수 있는 기기 기록. 두 번 누르기를 흉내 낸다.
class _GatedUploads extends FakePendingUploads {
  /// 채워 두면 끝날 때까지 찾기를 멈춘다.
  Completer<void>? gate;

  @override
  Future<PendingUpload?> find(
    String sessionId, {
    bool includeUploaded = false,
  }) async {
    await gate?.future;
    return super.find(sessionId, includeUploaded: includeUploaded);
  }
}

/// 실제 비동기 처리(가짜 서버)를 기다리고 화면을 맞춘다. 시트는 올라온 뒤
/// 잠시 누름을 받지 않으므로 그 시간도 흘린다.
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
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

late GoRouter _router;

/// 로그인한 상태로 [location] 을 연다. 기준 화면은 412 x 917 dp 다.
/// [systemBars] 면 위 24, 아래 48 dp 를 시스템 표시줄이 차지한다.
Future<void> _open(
  WidgetTester tester, {
  required FakeReportServer server,
  required PendingUploads uploads,
  RecordingShare? share,
  String location = AppRoutes.home,
  Size size = const Size(412, 917),
  double textScale = 1,
  bool systemBars = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  if (systemBars) {
    tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 48 * 3);
    tester.view.viewPadding = const FakeViewPadding(
      top: 24 * 3,
      bottom: 48 * 3,
    );
  }
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
      pendingUploadsProvider.overrideWith((ref) => uploads),
      recordingShareProvider.overrideWithValue(share ?? FakeRecordingShare()),
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
  if (settle) await _settle(tester);
}

Finder get _sheet => find.byType(BottomSheet);

Finder get _banner => find.text('리포트를 만들지 못했어요');

Finder get _shareButton => find.widgetWithText(OutlinedButton, '녹음 파일 공유');

void main() {
  group('홈의 실패 알림', () {
    testWidgets('녹음이 남았으면 다시 요청과 공유를 고르는 시트를 띄운다', (tester) async {
      final server = _failedServer();
      await _open(tester, server: server, uploads: _keptRecording());

      await _tap(tester, _banner);

      expect(_sheet, findsOneWidget);
      // 2026-11-09 PM 결정: 공유에 대한 안내 문구를 더하지 않는다.
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: _sheet, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      expect(texts, ['리포트를 만들지 못했어요', '분석 다시 요청하기', '녹음 파일 공유']);
      expect(server.count(_retryPath), 0, reason: '고르기 전에는 다시 요청하지 않는다');
      expect(_router.state.uri.toString(), AppRoutes.home);
    });

    testWidgets('공유를 고르면 그 회차의 녹음 파일로 공유 창을 열고 다시 요청하지 않는다', (tester) async {
      final server = _failedServer();
      final share = FakeRecordingShare();
      await _open(
        tester,
        server: server,
        uploads: _keptRecording(),
        share: share,
      );

      await _tap(tester, _banner);
      await _tap(tester, find.descendant(of: _sheet, matching: _shareButton));

      expect(share.paths, [_audioPath]);
      expect(_sheet, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(server.count(_retryPath), 0);
      expect(_router.state.uri.toString(), AppRoutes.home);
    });

    testWidgets('다시 요청을 고르면 지금처럼 분석 다시 요청하기 화면으로 간다', (tester) async {
      final server = _failedServer();
      final share = FakeRecordingShare();
      await _open(
        tester,
        server: server,
        uploads: _keptRecording(),
        share: share,
      );

      await _tap(tester, _banner);
      await _tap(tester, find.text('분석 다시 요청하기'));

      expect(
        _router.state.uri.toString(),
        AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );
      expect(server.count(_retryPath), 1);
      expect(share.paths, isEmpty);
    });

    testWidgets('녹음이 없으면 시트 없이 바로 분석 다시 요청하기 화면으로 간다', (tester) async {
      final server = _failedServer();
      await _open(tester, server: server, uploads: FakePendingUploads());

      await _tap(tester, _banner);

      expect(_sheet, findsNothing);
      expect(
        _router.state.uri.toString(),
        AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );
      expect(server.count(_retryPath), 1);
    });

    testWidgets('공유 창을 열지 못하면 홈에서 알린다', (tester) async {
      await _open(
        tester,
        server: _failedServer(),
        uploads: _keptRecording(),
        share: FakeRecordingShare(result: RecordingShareResult.failed),
      );

      await _tap(tester, _banner);
      await _tap(tester, find.descendant(of: _sheet, matching: _shareButton));

      expect(find.text('녹음 파일을 공유하지 못했어요.'), findsOneWidget);
      expect(_router.state.uri.toString(), AppRoutes.home);
    });

    testWidgets('공유하는 사이 녹음이 사라졌으면 알리고 다음에는 바로 다시 요청한다', (tester) async {
      final server = _failedServer();
      final uploads = _keptRecording();
      await _open(
        tester,
        server: server,
        uploads: uploads,
        share: FakeRecordingShare(
          result: RecordingShareResult.missing,
          onShare: () => uploads.uploaded.remove(_sessionId),
        ),
      );

      await _tap(tester, _banner);
      await _tap(tester, find.descendant(of: _sheet, matching: _shareButton));

      expect(find.text('녹음 파일을 찾지 못했어요.'), findsOneWidget);
      expect(_router.state.uri.toString(), AppRoutes.home);
      expect(server.count(_retryPath), 0);

      await _tap(tester, _banner);

      expect(_sheet, findsNothing);
      expect(
        _router.state.uri.toString(),
        AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );
      expect(server.count(_retryPath), 1);
    });

    testWidgets('녹음을 찾는 사이 한 번 더 눌러도 시트는 한 장만 띄운다', (tester) async {
      final server = _failedServer();
      final uploads = _GatedUploads()
        ..uploaded[_sessionId] = const PendingUpload(
          sessionId: _sessionId,
          audioPath: _audioPath,
          participantCount: 2,
        );
      await _open(tester, server: server, uploads: uploads);

      final gate = uploads.gate = Completer<void>();
      await tester.tap(_banner);
      await tester.tap(_banner);
      gate.complete();
      await _settle(tester);

      expect(_sheet, findsOneWidget);
      expect(server.count(_retryPath), 0);
    });

    testWidgets('녹음이 없을 때 두 번 눌러도 다시 요청하기 화면은 하나만 연다', (tester) async {
      final server = _failedServer();
      final uploads = _GatedUploads();
      await _open(tester, server: server, uploads: uploads);

      final gate = uploads.gate = Completer<void>();
      await tester.tap(_banner);
      await tester.tap(_banner);
      gate.complete();
      await _settle(tester);

      expect(
        _router.state.uri.toString(),
        AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );
      expect(server.count(_retryPath), 1);
      // 한 번 돌아가면 홈이다. 화면이 두 번 열렸으면 다시 요청하기가 남는다.
      _router.pop();
      await _settle(tester);
      expect(_router.state.uri.toString(), AppRoutes.home);
    });

    testWidgets('배너를 다시 누른 손가락은 막 올라온 시트의 버튼을 누르지 않는다', (tester) async {
      final server = _failedServer();
      final share = FakeRecordingShare();
      await _open(
        tester,
        server: server,
        uploads: _keptRecording(),
        share: share,
      );
      final banner = tester.getCenter(_banner);

      await tester.tapAt(banner);
      await tester.pump();
      // 올라오는 중(0.1초)과 다 올라온 직후(0.3초)에 같은 자리를 누른다.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(banner);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tapAt(banner);
      await tester.pump(const Duration(milliseconds: 100));

      expect(_sheet, findsOneWidget);
      expect(share.paths, isEmpty);
      expect(server.count(_retryPath), 0);
      expect(_router.state.uri.toString(), AppRoutes.home);

      // 잠시 뒤에는 시트의 버튼을 누를 수 있다.
      await _settle(tester);
      await _tap(tester, find.descendant(of: _sheet, matching: _shareButton));
      expect(share.paths, [_audioPath]);
    });

    for (final (size, scale) in const [
      (Size(412, 917), 1.5),
      (Size(360, 800), 2.0),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} 글자 $scale배에서 '
          '시트가 넘치지 않는다', (tester) async {
        await _open(
          tester,
          server: _failedServer(),
          uploads: _keptRecording(),
          size: size,
          textScale: scale,
        );

        // 360x800 글자 2.0배 홈은 본문과 버튼, 알림을 한 스크롤로 이어 알림이
        // 첫 화면 아래에 있다.
        await tester.ensureVisible(_banner);
        await tester.pump();
        await _tap(tester, _banner);

        expect(tester.takeException(), isNull);
        final shareButton = find.descendant(of: _sheet, matching: _shareButton);
        expect(tester.getSize(shareButton).height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(find.text('녹음 파일 공유')).right,
          lessThanOrEqualTo(tester.getRect(shareButton).right),
        );
      });
    }
  });

  testWidgets('알림 화면의 실패 알림도 같은 시트로 공유한다', (tester) async {
    final server = _failedServer();
    final share = FakeRecordingShare();
    await _open(
      tester,
      server: server,
      uploads: _keptRecording(),
      share: share,
      location: AppRoutes.notifications,
    );

    await _tap(tester, _banner);
    expect(_sheet, findsOneWidget);
    await _tap(tester, find.descendant(of: _sheet, matching: _shareButton));

    expect(share.paths, [_audioPath]);
    expect(server.count(_retryPath), 0);
    expect(_router.state.uri.toString(), AppRoutes.notifications);
  });

  testWidgets('알림 화면의 실패 알림도 녹음이 없으면 바로 다시 요청한다', (tester) async {
    final server = _failedServer();
    await _open(
      tester,
      server: server,
      uploads: FakePendingUploads(),
      location: AppRoutes.notifications,
    );

    await _tap(tester, _banner);

    expect(_sheet, findsNothing);
    expect(
      _router.state.uri.toString(),
      AppRoutes.analysisRetryOf(_sessionId, _analysisId),
    );
    expect(server.count(_retryPath), 1);
  });

  group('분석을 다시 요청하지 못한 화면', () {
    FakeReportServer refusingServer() =>
        _failedServer()
          ..failures['POST $_retryPath'] = (status: 500, errorCode: 'INTERNAL');

    testWidgets('녹음이 남았으면 다시 시도와 홈으로 사이에 공유를 둔다', (tester) async {
      final share = FakeRecordingShare();
      await _open(
        tester,
        server: refusingServer(),
        uploads: _keptRecording(),
        share: share,
        location: AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );

      expect(find.text('분석을 요청하지 못했어요.'), findsOneWidget);
      final retry = tester.getRect(find.text('다시 시도하기'));
      final shareRect = tester.getRect(_shareButton);
      final home = tester.getRect(find.text('홈으로'));
      expect(retry.top, lessThan(shareRect.top));
      expect(shareRect.bottom, lessThan(home.top));

      await _tap(tester, _shareButton);

      expect(share.paths, [_audioPath]);
      expect(find.text('분석을 요청하지 못했어요.'), findsOneWidget);
    });

    testWidgets('녹음이 없으면 공유를 두지 않는다', (tester) async {
      await _open(
        tester,
        server: refusingServer(),
        uploads: FakePendingUploads(),
        location: AppRoutes.analysisRetryOf(_sessionId, _analysisId),
      );

      expect(find.text('분석을 요청하지 못했어요.'), findsOneWidget);
      expect(find.text('다시 시도하기'), findsOneWidget);
      expect(find.text('녹음 파일 공유'), findsNothing);
    });

    // 360 x 640 은 녹음 안내 화면의 작은 화면 확인(`record_intro_notice_test`)과,
    // 360 x 800 은 홈의 큰 글자 확인(`home_large_text_test`)과 같다.
    for (final (size, scale, bars) in const [
      (Size(412, 917), 1.5, false),
      (Size(360, 640), 1.3, false),
      (Size(360, 640), 2.0, false),
      (Size(360, 720), 1.5, true),
      (Size(360, 800), 2.0, false),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}'
          '${bars ? ' 시스템 표시줄' : ''} 글자 $scale배에서 '
          '안내와 버튼이 겹치지 않는다', (tester) async {
        final share = FakeRecordingShare();
        await _open(
          tester,
          server: refusingServer(),
          uploads: _keptRecording(),
          share: share,
          location: AppRoutes.analysisRetryOf(_sessionId, _analysisId),
          size: size,
          textScale: scale,
          systemBars: bars,
        );

        expect(tester.takeException(), isNull);
        final body = tester.getRect(find.text('잠시 후 다시 보내주세요.'));
        final retry = tester.getRect(
          find.widgetWithText(FilledButton, '다시 시도하기'),
        );
        final shareRect = tester.getRect(_shareButton);
        final home = tester.getRect(find.widgetWithText(OutlinedButton, '홈으로'));
        expect(body.bottom, lessThan(retry.top));
        expect(retry.bottom, lessThan(shareRect.top));
        expect(shareRect.bottom, lessThan(home.top));
        expect(shareRect.height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(find.text('녹음 파일 공유')).right,
          lessThanOrEqualTo(shareRect.right),
        );

        // 화면에 다 들어가지 않으면 내려서 누를 수 있다.
        await tester.ensureVisible(_shareButton);
        await _tap(tester, _shareButton);
        expect(share.paths, [_audioPath]);
      });
    }

    testWidgets('실패 안내가 처음 그려질 때 공유도 함께 있다', (tester) async {
      await _open(
        tester,
        server: refusingServer(),
        uploads: _keptRecording(),
        location: AppRoutes.analysisRetryOf(_sessionId, _analysisId),
        settle: false,
      );

      // 녹음은 들어오자마자 찾는다. 실패한 뒤에 찾기 시작하면 공유가 몇 장면
      // 늦게 나타나 `다시 시도하기` 가 자리를 옮긴다.
      for (var i = 0; i < 20; i++) {
        if (find.text('분석을 요청하지 못했어요.').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('분석을 요청하지 못했어요.'), findsOneWidget);
      expect(_shareButton, findsOneWidget);
    });
  });
}
