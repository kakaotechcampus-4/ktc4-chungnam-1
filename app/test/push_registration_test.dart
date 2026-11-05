// 이 기기를 로그인과 알림 수신 동의에 맞춰 푸시에 등록하고 등록을 푸는지 확인한다.
//
// FCM 대신 [_FakePush] 를 쓴다. 등록 ID 와 계정은 모두 합성이다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
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

  Future<void> close() => _ids.close();
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

({ProviderContainer container, _FakePush push, _AccountServer server}) _setUp({
  bool enabled = true,
}) {
  final push = _FakePush(enabled: enabled);
  final server = _AccountServer();
  final container = ProviderContainer(
    overrides: [
      pushMessagingProvider.overrideWithValue(push),
      sessionStoreProvider.overrideWithValue(_MemoryStore()),
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
  container.listen(pushRegistrationProvider, (_, _) {});
  return (container: container, push: push, server: server);
}

void main() {
  test('알림 수신에 동의한 로그인 계정은 권한을 묻고 등록해 ID 를 받는다', () async {
    final (:container, :push, :server) = _setUp();

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(push.permissionRequests, 1);
    expect(push.registerCalls, 1);
    expect(container.read(pushRegistrationProvider), 'fid-1');
    expect(server.reads, 1);
  });

  test('로그인하지 않았으면 계정도 읽지 않고 등록하지 않는다', () async {
    final (:container, :push, :server) = _setUp();

    await pumpEventQueue();

    expect(server.reads, 0);
    expect(push.permissionRequests, 0);
    expect(push.registerCalls, 0);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('알림 수신에 동의하지 않았으면 권한을 묻지 않고 등록하지 않는다', () async {
    final (:container, :push, :server) = _setUp();
    server.push = false;

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(push.permissionRequests, 0);
    expect(push.registerCalls, 0);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('푸시를 쓰지 않는 빌드는 계정을 읽지 않는다', () async {
    final (:container, :push, :server) = _setUp(enabled: false);

    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    expect(server.reads, 0);
    expect(push.registerCalls, 0);
  });

  test('로그아웃하면 등록을 푼다', () async {
    final (:container, :push, server: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    await container.read(sessionProvider.notifier).discard();
    await pumpEventQueue();

    expect(push.unregisterCalls, 1);
    expect(container.read(pushRegistrationProvider), isNull);
  });

  test('알림 수신 동의를 거두면 등록을 풀고, 다시 동의하면 다시 등록한다', () async {
    final (:container, :push, :server) = _setUp();
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
    final (:container, :push, :server) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    server.failing = true;
    container.invalidate(accountProvider);
    await pumpEventQueue();

    expect(push.unregisterCalls, 0);
    expect(container.read(pushRegistrationProvider), 'fid-1');
  });

  test('FCM 이 새 ID 를 보내면 새 값으로 바꾼다', () async {
    final (:container, :push, server: _) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    push.sync('fid-changed');
    await pumpEventQueue();

    expect(container.read(pushRegistrationProvider), 'fid-changed');
  });

  test('등록을 기다리는 사이 로그아웃하면 늦게 온 ID 를 남기지 않고 등록을 푼다', () async {
    final (:container, :push, server: _) = _setUp();
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
    final (:container, :push, :server) = _setUp();
    container.read(sessionProvider.notifier).restore(_session('account-a'));
    await pumpEventQueue();

    server.push = false;
    container.read(sessionProvider.notifier).restore(_session('account-b'));
    await pumpEventQueue();

    expect(server.reads, 2);
    expect(push.unregisterCalls, 1);
    expect(container.read(pushRegistrationProvider), isNull);
  });
}
