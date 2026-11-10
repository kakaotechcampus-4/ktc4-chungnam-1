// 로그인한 상태의 홈 리포트 알림이 서버의 회차 상태(`api-spec.md` 5-4)와
// 분석 작업 상태(6-3)를 따르는지 확인한다.
//
// 서버는 `FakeProfileServer` 와 `FakeReportServer` 다. 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/providers.dart';
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

FakeProfileServer _profiles() => FakeProfileServer(
  profiles: [FakeProfileServer.profile(id: 'p1', setupStatus: 'completed')],
);

/// [check] 가 참이 될 때까지 기다린다. 서버 응답과 폴링은 실제 시간에 흐른다.
Future<void> _until(bool Function() check) async {
  for (var i = 0; i < 200; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('기다린 상태가 오지 않았다');
}

/// 로그인하고 어르신 목록을 불러온 컨테이너다. 홈처럼 알림을 지켜본다.
Future<ProviderContainer> _signedIn(FakeReportServer reports) async {
  final container = ProviderContainer(
    overrides: [
      _profiles().override,
      reports.override,
      reportPollIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 1),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(careProfilesProvider, (_, _) {});
  container.read(sessionProvider.notifier).restore(_session());
  await _until(() => container.read(careProfilesProvider).hasSelected);
  container.listen(reportNoticeInfoProvider, (_, _) {});
  return container;
}

ReportNoticeInfo? _info(ProviderContainer c) =>
    c.read(reportNoticeInfoProvider);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('가장 최근 회차의 리포트가 있으면 도착을 띄운다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    );
    final container = await _signedIn(server);

    await _until(() => _info(container) != null);

    final info = _info(container)!;
    expect(info.notice, ReportNotice.ready);
    expect(info.reportId, 's1');
    expect(info.visitDate, '2026-10-13');
  });

  test('만드는 중이면 분석 작업이 끝날 때까지 묻고 도착으로 바꾼다', () async {
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
        'a1': ['transcribing', 'generatingReport', 'completed'],
      },
    );
    final container = await _signedIn(server);

    await _until(() => _info(container)?.notice == ReportNotice.generating);
    await _until(() => _info(container)?.notice == ReportNotice.ready);

    expect(_info(container)!.reportId, 's1');
    expect(server.count('/api/v1/speech-analyses/a1'), 3);
  });

  test('분석이 실패하면 실패를 띄운다', () async {
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
        'a1': ['queued', 'failed'],
      },
    );
    final container = await _signedIn(server);

    await _until(() => _info(container)?.notice == ReportNotice.failed);
    expect(_info(container)!.reportId, 's1');
    expect(_info(container)!.analysisId, 'a1');
  });

  test('분석이 실패하면 6-3 의 실패 이유를 함께 남긴다', () async {
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
        'a1': ['queued', 'failed'],
      },
    )..analysisErrors['a1'] = 'AI_SERVER_TIMEOUT';
    final container = await _signedIn(server);

    await _until(() => _info(container)?.notice == ReportNotice.failed);
    expect(_info(container)!.failureCode, 'AI_SERVER_TIMEOUT');
  });

  test('회차 목록이 실패라고 하면 6-3 에 한 번 물어 실패 이유를 붙인다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [
          FakeReportServer.session(
            id: 's1',
            status: 'failed',
            analysisId: 'a1',
          ),
        ],
      },
      analyses: {
        'a1': ['failed'],
      },
    )..analysisErrors['a1'] = 'EMPTY_TRANSCRIPT';
    final container = await _signedIn(server);

    await _until(() => _info(container)?.failureCode != null);
    expect(_info(container)!.notice, ReportNotice.failed);
    expect(_info(container)!.failureCode, 'EMPTY_TRANSCRIPT');
    expect(server.count('/api/v1/speech-analyses/a1'), 1);
  });

  test('실패 이유를 묻지 못해도 실패는 띄운다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [
          FakeReportServer.session(
            id: 's1',
            status: 'failed',
            analysisId: 'a1',
          ),
        ],
      },
    );
    server.failures['GET /api/v1/speech-analyses/a1'] = (
      status: 503,
      errorCode: 'SERVICE_UNAVAILABLE',
    );
    final container = await _signedIn(server);

    await _until(() => server.count('/api/v1/speech-analyses/a1') > 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_info(container)!.notice, ReportNotice.failed);
    expect(_info(container)!.failureCode, isNull);
  });

  test('서버가 실패로 계산한 회차는 바로 실패를 띄운다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'failed')],
      },
    );
    final container = await _signedIn(server);

    await _until(() => _info(container) != null);
    expect(_info(container)!.notice, ReportNotice.failed);
  });

  test('회차가 없으면 알림을 띄우지 않는다', () async {
    final server = FakeReportServer();
    final container = await _signedIn(server);

    await _until(() => server.count('/api/v1/profiles/p1/visit-sessions') > 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_info(container), isNull);
  });

  test('평가 전이나 음성을 보내기 전에 떠났으면 이어갈 회차를 띄운다', () async {
    for (final (status, notice) in [
      ('evaluationPending', ReportNotice.evaluationPending),
      ('audioPending', ReportNotice.audioPending),
    ]) {
      final server = FakeReportServer(
        sessions: {
          'p1': [FakeReportServer.session(id: 's1', status: status)],
        },
      );
      final container = await _signedIn(server);

      await _until(() => _info(container) != null);
      expect(_info(container)!.notice, notice);
      expect(_info(container)!.reportId, 's1');
      // 이어갈 일이 있을 뿐 리포트는 아직 없다. 분석 작업을 묻지 않는다.
      expect(server.requests.where((r) => r.path.contains('speech')), isEmpty);
    }
  });

  test('변경 사항을 확인한 리포트는 다시 물어도 띄우지 않는다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    );
    final container = await _signedIn(server);
    await _until(() => _info(container) != null);

    container.read(reportNoticeProvider.notifier).dismiss();
    expect(_info(container), isNull);

    // 서버는 확인 여부를 저장하지 않아 같은 회차를 계속 completed 로 준다.
    container.read(reportNoticeProvider.notifier).startGenerating();
    await _until(() => server.count('/api/v1/profiles/p1/visit-sessions') > 1);
    await _until(() => _info(container) == null);
  });

  test('음성을 보낸 뒤 받은 분석 작업으로 진행 상태를 찾는다', () async {
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
        'a-new': ['completed'],
      },
    );
    final container = await _signedIn(server);

    container
        .read(reportNoticeProvider.notifier)
        .startGenerating(analysisId: 'a-new');

    await _until(() => _info(container)?.notice == ReportNotice.ready);
    expect(server.count('/api/v1/speech-analyses/a-new'), 1);
    expect(server.count('/api/v1/speech-analyses/a1'), 0);
  });

  test('만드는 중에 연결이 끊겨도 기다렸다가 다시 묻는다', () async {
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
    final container = await _signedIn(server);
    await _until(() => _info(container)?.notice == ReportNotice.generating);
    server.offline = true;
    final before = server.requests.length;
    await _until(() => server.requests.length > before + 2);
    expect(_info(container)!.notice, ReportNotice.generating);

    server.analyses['a1'] = ['completed'];
    server.offline = false;
    await _until(() => _info(container)?.notice == ReportNotice.ready);
  });

  test('처음 묻지 못하면 확인하지 못했다고 띄우고, 다시 물을 수 있다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    )..offline = true;
    final container = await _signedIn(server);

    await _until(() => _info(container) != null);
    expect(_info(container)!.notice, ReportNotice.checkFailed);
    expect(_info(container)!.reportId, isNull, reason: '리포트를 지어내지 않는다');

    server.offline = false;
    container.read(reportNoticeProvider.notifier).retry();

    await _until(() => _info(container)?.notice == ReportNotice.ready);
    expect(_info(container)!.reportId, 's1');
  });

  test('이미 띄운 알림은 다시 묻다 실패해도 그대로 둔다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    );
    final container = await _signedIn(server);
    await _until(() => _info(container)?.notice == ReportNotice.ready);

    server.offline = true;
    container.read(reportNoticeProvider.notifier).startGenerating();
    await _until(() => server.requests.length > 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_info(container)!.notice, isNot(ReportNotice.checkFailed));
  });

  // 2026-11-10 UX 점검 17번. 다시 시도할 수 없는 실패가 오면 묻기를 멈추고
  // 만드는 중 배너가 끝없이 돌았다.
  group('만드는 중에 묻지 못하면', () {
    FakeReportServer processing({String? analysisId = 'a1'}) =>
        FakeReportServer(
          sessions: {
            'p1': [
              FakeReportServer.session(
                id: 's1',
                status: 'processing',
                analysisId: analysisId,
              ),
            ],
          },
          analyses: {
            'a1': ['transcribing'],
          },
        );

    const analysisPath = '/api/v1/speech-analyses/a1';

    test('분석 작업을 다시 시도할 수 없는 실패면 확인하지 못했다고 바꾼다', () async {
      final server = processing();
      final container = await _signedIn(server);
      await _until(() => _info(container)?.notice == ReportNotice.generating);

      server.failures['GET $analysisPath'] = (
        status: 500,
        errorCode: 'INTERNAL_ERROR',
      );
      await _until(() => _info(container)?.notice == ReportNotice.checkFailed);
      expect(_info(container)!.visitDate, '2026-10-13', reason: '어느 만남인지 둔다');

      final asked = server.count(analysisPath);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.count(analysisPath), asked, reason: '눌러서 다시 묻기 전에는 묻지 않는다');
    });

    test('회차를 다시 시도할 수 없는 실패면 확인하지 못했다고 바꾼다', () async {
      // 작업 ID 를 몰라 회차부터 다시 묻는 중이다.
      final server = processing(analysisId: null);
      final container = await _signedIn(server);
      await _until(() => _info(container)?.notice == ReportNotice.generating);

      server.failures['GET /api/v1/profiles/p1/visit-sessions'] = (
        status: 500,
        errorCode: 'INTERNAL_ERROR',
      );
      await _until(() => _info(container)?.notice == ReportNotice.checkFailed);
    });

    test('본문 없는 5xx 는 다시 시도할 수 있는 실패로 보고 계속 묻는다', () async {
      final server = processing();
      final container = await _signedIn(server);
      await _until(() => _info(container)?.notice == ReportNotice.generating);

      // 앞단 프록시가 공통 오류 본문 없이 돌려주는 502 다.
      server.bareFailures['GET $analysisPath'] = 502;
      final before = server.count(analysisPath);
      await _until(() => server.count(analysisPath) > before + 2);
      expect(_info(container)!.notice, ReportNotice.generating);

      server.bareFailures.clear();
      server.analyses['a1'] = ['completed'];
      await _until(() => _info(container)?.notice == ReportNotice.ready);
    });
  });

  test('확인하지 못한 알림을 눌러 다시 묻는 동안 알림을 지우지 않는다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    )..offline = true;
    final container = await _signedIn(server);
    await _until(() => _info(container)?.notice == ReportNotice.checkFailed);

    server
      ..offline = false
      ..hold = Completer<void>();
    container.read(reportNoticeProvider.notifier).retry();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      _info(container)?.notice,
      ReportNotice.checkFailed,
      reason: '지우면 사라졌다가 다시 나타난다',
    );

    server.hold!.complete();
    await _until(() => _info(container)?.notice == ReportNotice.ready);
  });

  test('다시 묻다 또 실패하면 다시 누를 수 있는 알림으로 돌아온다', () async {
    final server = FakeReportServer(
      sessions: {
        'p1': [FakeReportServer.session(id: 's1', status: 'completed')],
      },
    )..offline = true;
    final container = await _signedIn(server);
    await _until(() => _info(container)?.notice == ReportNotice.checkFailed);
    final before = server.requests.length;

    container.read(reportNoticeProvider.notifier).retry();
    await _until(() => server.requests.length > before);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_info(container)!.notice, ReportNotice.checkFailed);
  });
}
