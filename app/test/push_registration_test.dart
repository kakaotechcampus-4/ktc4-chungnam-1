// 이 기기를 로그인과 알림 수신 동의에 맞춰 푸시에 등록하고 등록을 푸는지 확인한다.
//
// FCM 대신 [_FakePush], 서버 기기 등록(1-7, 1-8) 대신 [_FakeDeviceApi] 를 쓴다.
// 등록 ID, 회차 ID 와 계정은 모두 합성이다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/data/push_device_api.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/auth/google_authenticator.dart';
import 'package:saerok/features/auth/session_store.dart';
import 'package:saerok/features/push/push_messaging.dart';
import 'package:saerok/features/push/push_registration.dart';

AuthSession _session(String accountId) => AuthSession(
  accessToken: 'session',
  tokenType: 'Bearer',
  expiresAt: DateTime(2100),
  account: AuthAccount(
    accountId: accountId,
    authProvider: 'google',
    displayName: '테스트 보호자',
    email: null,
    consentVersion: null,
    createdAt: null,
  ),
);

Account _account(String accountId, {required bool push}) => Account(
  accountId: accountId,
  authProvider: 'google',
  displayName: '테스트 보호자',
  email: null,
  consentVersion: '2026-09-06',
  consent: {
    'serviceData': const ConsentItem(granted: true),
    'sensitiveData': const ConsentItem(granted: true),
    'serviceImprovement': const ConsentItem(granted: false),
    'pushNotification': ConsentItem(granted: push),
  },
  createdAt: '2026-09-06T00:00:00Z',
);

/// FCM 대역. [register] 하면 [nextId] 를 [registrations] 로 보낸다.
class _FakePush implements PushMessaging {
  _FakePush({this.enabled = true});

  @override
  final bool enabled;

  int permissionRequests = 0;
  int registerCalls = 0;
  int unregisterCalls = 0;
  String nextId = 'fid-1';

  /// 채워 두면 [register] 가 이것을 기다린 뒤 ID 를 보낸다.
  Completer<void>? holdRegister;

  final _ids = StreamController<String>.broadcast();

  /// 앱을 켤 때의 동기화처럼 FCM 이 스스로 보내는 ID.
  void sync(String id) => _ids.add(id);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> register() async {
    registerCalls++;
    await holdRegister?.future;
    _ids.add(nextId);
  }

  @override
  Stream<String> get registrations => _ids.stream;

  @override
  Future<void> unregister() async => unregisterCalls++;

  /// 알림을 눌러 앱을 켰을 때의 회차 ID.
  String? initialSession;
  final _opened = StreamController<String>.broadcast();

  /// 앱이 뒤에 있을 때 알림을 누른다.
  void tap(String sessionId) => _opened.add(sessionId);

  @override
  Future<String?> initialReportSession() async {
    final sessionId = initialSession;
    initialSession = null;
    return sessionId;
  }

  @override
  Stream<String> get openedReportSessions => _opened.stream;

  Future<void> close() async {
    await _ids.close();
    await _opened.close();
  }
}

/// 서버의 기기 등록(1-7, 1-8) 대역. 받은 요청을 차례로 남긴다.
class _FakeDeviceApi implements PushDeviceApi {
  final calls = <String>[];

  /// 채워 두면 그 실패로 거절한다.
  ApiFailure? failure;

  /// 채워 두면 해제(1-8)가 이것을 기다린다.
  Completer<void>? holdUnregister;

  /// 요청이 나갈 때 세션이 있었는지.
  bool Function()? signedIn;
  final signedInAtCall = <bool>[];

  @override
  Future<void> register(String fid) async {
    calls.add('PUT $fid');
    signedInAtCall.add(signedIn?.call() ?? true);
    if (failure case final failure?) throw failure;
  }

  @override
  Future<void> unregister(String fid) async {
    calls.add('DELETE $fid');
    signedInAtCall.add(signedIn?.call() ?? true);
    await holdUnregister?.future;
    if (failure case final failure?) throw failure;
  }
}

class _NoGoogle implements GoogleAuthenticator {
  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> silentIdToken() async => null;

  @override
  Future<void> signOut() async {}
}

class _MemoryStore implements SessionStore {
  @override
  Future<AuthSession?> read() async => null;

  @override
  Future<void> write(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

/// 계정 응답(1-3)을 대신한다. [failing] 이면 연결 실패처럼 던진다.
class _AccountServer {
  bool push = true;
  bool failing = false;
  int reads = 0;

  Future<Account> read(String accountId) async {
    reads++;
    if (failing) throw Exception('연결 실패');
    return _account(accountId, push: push);
  }
}

({
  ProviderContainer container,
  _FakePush push,
  _AccountServer server,
  _FakeDeviceApi devices,
})
_setUp({bool enabled = true}) {
  final push = _FakePush(enabled: enabled);
  final server = _AccountServer();
  final devices = _FakeDeviceApi();
  final container = ProviderContainer(
    overrides: [
      pushMessagingProvider.overrideWithValue(push),
      pushDeviceApiProvider.overrideWithValue(devices),
      sessionStoreProvider.overrideWithValue(_MemoryStore()),
      googleAuthenticatorProvider.overrideWithValue(_NoGoogle()),
      // 로그아웃(1-4)은 서버가 받은 것으로 둔다.
      authApiProvider.overrideWith(
        (ref) =>
            AuthApi(client: MockClient((_) async => http.Response('', 204))),
      ),
      accountProvider.overrideWith((ref) {
        final id = ref.watch(
          sessionProvider.select((s) => s?.account.accountId),
        );
        if (id == null) throw StateError('로그인하지 않으면 읽지 않는다');
        return server.read(id);
      }),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(push.close);
  devices.signedIn = () => container.read(sessionProvider) != null;
  container.listen(pushRegistrationProvider, (_, _) {});
  return (container: container, push: push, server: server, devices: devices);
}

/// 프로필 설정의 로그아웃 버튼과 같은 순서로 로그아웃한다.
Future<void> _signOut(ProviderContainer container) async {
  await container.read(pushRegistrationProvider.notifier).releaseForSignOut();
  await container.read(sessionProvider.notifier).signOut();
}

void main() {
  test('알림 수신에 동의한 로그인 계정은 권한을 묻고 등록해 ID 를 받는다', () async {
    final (:container, :push, :server, devices: _) = _setUp();

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(push.permissionRequests, 1);
    expect(push.registerCalls, 1);
    expect(container.read(pushRegistrationProvider), 'fid-1');
    expect(server.reads, 1);
  });

  test('로그인하지 않았으면 계정도 읽지 않고 등록하지 않는다', () async {
    final (:container, :push, :server, devices: _) = _setUp();

    await pumpEventQueue();

    expect(server.reads, 0);
    expect(push.permissionRequests, 0);
    expect(push.registerCalls, 0);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('알림 수신에 동의하지 않았으면 권한을 묻지 않고 등록하지 않는다', () async {
    final (:container, :push, :server, devices: _) = _setUp();
    server.push = false;

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(push.permissionRequests, 0);
    expect(push.registerCalls, 0);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('푸시를 쓰지 않는 빌드는 계정을 읽지 않는다', () async {
    final (:container, :push, :server, devices: _) = _setUp(enabled: false);

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(server.reads, 0);
    expect(push.registerCalls, 0);
  });

  test('로그아웃하면 등록을 푼다', () async {
    final (:container, :push, server: _, devices: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    await container.read(sessionProvider.notifier).discard();
    await pumpEventQueue();

    expect(push.unregisterCalls, 1);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('알림 수신 동의를 거두면 등록을 풀고, 다시 동의하면 다시 등록한다', () async {
    final (:container, :push, :server, devices: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    server.push = false;
    container.invalidate(accountProvider);
    await pumpEventQueue();
    expect(push.unregisterCalls, 1);
    expect(container.read(pushRegistrationProvider), isNull);

    server.push = true;
    push.nextId = 'fid-2';
    container.invalidate(accountProvider);
    await pumpEventQueue();
    expect(push.registerCalls, 2);
    expect(container.read(pushRegistrationProvider), 'fid-2');
    // 권한은 앱을 켤 때마다 한 번만 묻는다.
    expect(push.permissionRequests, 1);
  });

  test('계정을 다시 읽지 못해도 등록을 풀지 않는다', () async {
    final (:container, :push, :server, devices: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    server.failing = true;
    container.invalidate(accountProvider);
    await pumpEventQueue();

    expect(push.unregisterCalls, 0);
    expect(container.read(pushRegistrationProvider), 'fid-1');
  });

  test('FCM 이 새 ID 를 보내면 새 값으로 바꾼다', () async {
    final (:container, :push, server: _, devices: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    push.sync('fid-changed');
    await pumpEventQueue();

    expect(container.read(pushRegistrationProvider), 'fid-changed');
  });

  test('등록을 기다리는 사이 로그아웃하면 늦게 온 ID 를 남기지 않고 등록을 푼다', () async {
    final (:container, :push, server: _, devices: _) = _setUp();
    push.holdRegister = Completer<void>();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();
    expect(push.registerCalls, 1);

    await container.read(sessionProvider.notifier).discard();
    await pumpEventQueue();
    push.holdRegister!.complete();
    await pumpEventQueue();

    expect(container.read(pushRegistrationProvider), isNull);
    expect(push.unregisterCalls, 1);
  });

  test('다른 계정으로 바뀌면 그 계정의 동의를 다시 읽는다', () async {
    final (:container, :push, :server, devices: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    server.push = false;
    container.read(sessionProvider.notifier).restore(_session('account-b'));
    await pumpEventQueue();

    expect(server.reads, 2);
    expect(push.unregisterCalls, 1);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  group('서버 등록(1-7, 1-8)', () {
    test('받은 ID 를 서버에 등록하고, 같은 ID 가 다시 와도 한 번만 보낸다', () async {
      final (:container, :push, server: _, :devices) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      push.sync('fid-1');
      push.sync('fid-changed');
      await pumpEventQueue();

      expect(devices.calls, ['PUT fid-1', 'PUT fid-changed']);
    });

    test('서버에 등록하지 못해도 받은 ID 는 그대로 둔다', () async {
      final (:container, push: _, server: _, :devices) = _setUp();
      devices.failure = const ApiNetworkFailure();

      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      expect(devices.calls, ['PUT fid-1']);
      expect(container.read(pushRegistrationProvider), 'fid-1');
    });

    test('로그아웃은 세션을 지우기 전에 서버 등록을 지우고, 그 뒤 FCM 등록을 푼다', () async {
      final (:container, :push, server: _, :devices) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      await _signOut(container);
      await pumpEventQueue();

      expect(devices.calls, ['PUT fid-1', 'DELETE fid-1']);
      // 1-8 은 세션이 있을 때 나간다.
      expect(devices.signedInAtCall, [true, true]);
      expect(container.read(sessionProvider), isNull);
      expect(push.unregisterCalls, 1);
    });

    test('서버 등록을 지우지 못해도 로그아웃한다', () async {
      final (:container, push: _, server: _, :devices) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();
      devices.failure = const ApiNetworkFailure();

      await _signOut(container);

      expect(devices.calls.last, 'DELETE fid-1');
      expect(container.read(sessionProvider), isNull);
    });

    test('서버가 답하지 않아도 로그아웃은 짧게만 기다린다', () async {
      final (:container, push: _, server: _, :devices) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();
      devices.holdUnregister = Completer<void>();

      // 서버가 끝내 답하지 않는다. 로그아웃은 3초만 기다리고 이어간다.
      final watch = Stopwatch()..start();
      await _signOut(container);

      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(devices.calls.last, 'DELETE fid-1');
      expect(container.read(sessionProvider), isNull);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('등록하지 않았으면 로그아웃 때 서버를 부르지 않는다', () async {
      final (:container, push: _, :server, :devices) = _setUp();
      server.push = false;
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      await _signOut(container);

      expect(devices.calls, isEmpty);
    });
  });

  group('알림을 눌러 리포트 열기', () {
    test('앱이 뒤에 있을 때 누른 리포트를 열 차례로 둔다', () async {
      final (:container, :push, server: _, devices: _) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      push.tap('session-1');
      await pumpEventQueue();

      expect(container.read(pendingReportOpenProvider), 'session-1');
      expect(
        container.read(pendingReportOpenProvider.notifier).take(),
        'session-1',
      );
      expect(container.read(pendingReportOpenProvider), isNull);
    });

    test('알림을 눌러 앱을 켰으면 로그인을 확인한 뒤 그 리포트를 열 차례로 둔다', () async {
      final (:container, :push, server: _, devices: _) = _setUp();
      push.initialSession = 'session-cold';

      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();

      expect(container.read(pendingReportOpenProvider), 'session-cold');
    });

    test('로그아웃한 뒤에 누른 알림은 열지 않는다', () async {
      final (:container, :push, server: _, devices: _) = _setUp();
      container.read(sessionProvider.notifier).restore(_session('account-a'));
      await pumpEventQueue();
      await container.read(sessionProvider.notifier).discard();
      await pumpEventQueue();

      push.tap('session-1');
      await pumpEventQueue();

      expect(container.read(pendingReportOpenProvider), isNull);
    });

    test('리포트 완료 알림만 회차 ID 를 꺼낸다', () {
      expect(
        reportSessionOf({
          'type': 'reportReady',
          'sessionId': 's-1',
          'analysisId': 'a-1',
        }),
        's-1',
      );
      expect(reportSessionOf({'type': 'other', 'sessionId': 's-1'}), isNull);
      expect(reportSessionOf({'type': 'reportReady'}), isNull);
      expect(reportSessionOf({'type': 'reportReady', 'sessionId': ''}), isNull);
    });
  });
}
