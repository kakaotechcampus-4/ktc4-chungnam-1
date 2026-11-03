// 앱을 다시 켜면 마지막으로 고른 어르신으로 여는지 확인한다(이슈 144).
//
// 서버는 `FakeProfileServer`, 단말 저장소는 `FakeSelectedProfileStore` 다. 앱을 다시
// 켜는 것은 같은 서버와 저장소로 새 컨테이너를 만드는 것으로 대신한다. 값은
// 모두 합성이다.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/selected_profile_store.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';

import 'fake_profile_server.dart';
import 'fake_selected_profile_store.dart';

AuthSession _sessionOf(String accountId) => AuthSession(
  accessToken: 'token-$accountId',
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

FakeProfileServer _serverWith(List<String> ids) => FakeProfileServer(
  profiles: [
    for (final id in ids)
      FakeProfileServer.profile(id: id, setupStatus: 'completed'),
  ],
);

/// 앱을 켜고 [accountId] 로 로그인한 세션을 되살린다.
Future<ProviderContainer> _launch(
  FakeProfileServer server,
  FakeSelectedProfileStore store, {
  String accountId = 'account-a',
}) async {
  final container = ProviderContainer(
    overrides: [
      server.override,
      selectedProfileStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  container.listen(careProfilesProvider, (_, _) {});
  container.read(sessionProvider.notifier).restore(_sessionOf(accountId));
  await _settle();
  return container;
}

/// 서버와 저장소에 다녀올 때까지 기다린다.
Future<void> _settle() => Future<void>.delayed(
  Duration.zero,
).then((_) => Future<void>.delayed(const Duration(milliseconds: 10)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('다시 켜면 마지막으로 고른 분으로 연다', () async {
    final server = _serverWith(['p1', 'p2', 'p3']);
    final store = FakeSelectedProfileStore();

    final first = await _launch(server, store);
    expect(first.read(careProfilesProvider).selected?.remoteId, 'p1');
    first.read(careProfilesProvider.notifier).select('p3');
    await _settle();
    expect(store.values['account-a'], 'p3');
    first.dispose();

    final again = await _launch(server, store);
    expect(again.read(careProfilesProvider).selected?.remoteId, 'p3');
  });

  test('다음 분으로 넘긴 것도 기억한다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore();

    final container = await _launch(server, store);
    container.read(careProfilesProvider.notifier).selectNext();
    await _settle();

    expect(store.values['account-a'], 'p2');
  });

  test('기억한 분을 읽기 전에는 목록을 내보내지 않는다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p2';
    store.readGate = Completer<void>();

    final container = await _launch(server, store);
    expect(
      container.read(careProfilesProvider).isLoading,
      isTrue,
      reason: '첫 분이 잠깐 골라지면 다른 어르신으로 면회를 시작할 수 있다',
    );
    expect(container.read(careProfilesProvider).selected, isNull);

    store.readGate!.complete();
    await _settle();
    expect(container.read(careProfilesProvider).selected?.remoteId, 'p2');
  });

  test('다른 계정이 고른 분은 가져오지 않는다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p2';

    final container = await _launch(server, store, accountId: 'account-b');

    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
    expect(store.values['account-a'], 'p2', reason: '앞 계정의 기억은 그대로다');
  });

  test('로그아웃 뒤 다른 계정으로 바꿔도 계정마다 따로 기억한다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore();

    final container = await _launch(server, store);
    container.read(careProfilesProvider.notifier).select('p2');
    await _settle();

    await container.read(sessionProvider.notifier).discard();
    container.read(sessionProvider.notifier).restore(_sessionOf('account-b'));
    await _settle();
    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
    expect(store.values['account-b'], 'p1');

    await container.read(sessionProvider.notifier).discard();
    container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));
    await _settle();
    expect(container.read(careProfilesProvider).selected?.remoteId, 'p2');
  });

  test('기억한 분이 지워졌으면 첫 분으로 열고 기억을 바꾼다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p-gone';

    final container = await _launch(server, store);

    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
    expect(store.values['account-a'], 'p1');
  });

  test('기억한 분이 입력 중이면 고를 수 있는 첫 분으로 연다', () async {
    final server = FakeProfileServer(
      profiles: [
        FakeProfileServer.profile(id: 'p1', setupStatus: 'completed'),
        FakeProfileServer.profile(id: 'p-half'),
      ],
    );
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p-half';

    final container = await _launch(server, store);

    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
  });

  test('고른 분을 지우면 남은 첫 분을 기억한다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore();

    final container = await _launch(server, store);
    container.read(careProfilesProvider.notifier).select('p2');
    await _settle();
    container.read(careProfilesProvider.notifier).remove('p2');
    await _settle();

    expect(store.values['account-a'], 'p1');
  });

  test('마지막 분까지 지우면 기억을 지우고 빈 목록으로 연다', () async {
    final server = _serverWith(['p1']);
    final store = FakeSelectedProfileStore();

    final container = await _launch(server, store);
    expect(store.values['account-a'], 'p1');
    container.read(careProfilesProvider.notifier).remove('p1');
    await _settle();
    expect(store.values, isEmpty);

    server.profiles.clear();
    final again = await _launch(server, store);
    final profiles = again.read(careProfilesProvider);
    expect(profiles.load, CareProfilesLoad.loaded);
    expect(profiles.entries, isEmpty);
    expect(profiles.hasSelected, isFalse);
  });

  test('목록이 비어 있으면 남은 기억을 지운다', () async {
    final server = _serverWith([]);
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p-gone';

    final container = await _launch(server, store);

    expect(container.read(careProfilesProvider).hasSelected, isFalse);
    expect(store.values, isEmpty);
  });

  test('서버에 닿지 못하면 기억을 지우지 않는다', () async {
    final server = _serverWith(['p1', 'p2'])..offline = true;
    final store = FakeSelectedProfileStore()..values['account-a'] = 'p2';

    final container = await _launch(server, store);
    expect(container.read(careProfilesProvider).loadFailed, isTrue);
    expect(store.values['account-a'], 'p2');

    server.offline = false;
    await container.read(careProfilesProvider.notifier).reload();
    expect(container.read(careProfilesProvider).selected?.remoteId, 'p2');
  });

  test('저장소를 읽지 못해도 첫 분으로 연다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore()..broken = true;

    final container = await _launch(server, store);

    final profiles = container.read(careProfilesProvider);
    expect(profiles.load, CareProfilesLoad.loaded);
    expect(profiles.selected?.remoteId, 'p1');
  });

  test('계정을 바꾸는 사이 늦게 온 앞 계정의 결과는 버린다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeSelectedProfileStore()
      ..values['account-a'] = 'p2'
      ..readGate = Completer<void>();

    final container = await _launch(server, store);
    await container.read(sessionProvider.notifier).discard();
    store.readGate!.complete();
    store.readGate = null;
    container.read(sessionProvider.notifier).restore(_sessionOf('account-b'));
    await _settle();

    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
    expect(store.values['account-a'], 'p2');
    expect(store.values['account-b'], 'p1');
  });

  test('로그인하지 않았으면 기억하지 않는다', () async {
    final store = FakeSelectedProfileStore();
    final container = ProviderContainer(
      overrides: [selectedProfileStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.listen(careProfilesProvider, (_, _) {});

    container.read(careProfilesProvider.notifier).beginAdding();
    await _settle();

    expect(store.values, isEmpty);
  });
}
