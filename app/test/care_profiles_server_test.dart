// 로그인하면 어르신 목록을 서버(`api-spec.md` 2-1, 2-3)에서 불러오는지 확인한다.
//
// 서버는 `FakeProfileServer` 다. 값은 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';

import 'fake_profile_server.dart';

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

ProviderContainer _container(FakeProfileServer server) {
  final container = ProviderContainer(overrides: [server.override]);
  addTearDown(container.dispose);
  // 목록을 계속 지켜보는 화면이 있는 것처럼 둔다.
  container.listen(careProfilesProvider, (_, _) {});
  return container;
}

/// 서버에 다녀올 때까지 기다린다.
Future<void> _settle() => Future<void>.delayed(Duration.zero).then(
  (_) => Future<void>.delayed(const Duration(milliseconds: 10)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('로그인하지 않았으면 서버를 부르지 않고 앱 안에서만 기억한다', () async {
    final server = FakeProfileServer();
    final container = _container(server);

    await _settle();

    expect(container.read(careProfilesProvider).load, CareProfilesLoad.local);
    expect(server.requests, isEmpty);
  });

  test('로그인하면 서버 목록을 불러오고 입력 중인 분은 고를 수 없다', () async {
    final server = FakeProfileServer(
      profiles: [
        FakeProfileServer.profile(
          id: 'p-done',
          setupStatus: 'completed',
          occupation: '재봉 일을 오래 하셨어요.',
        ),
        FakeProfileServer.profile(id: 'p-half', name: '박새봄'),
      ],
    );
    final container = _container(server);

    container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));
    expect(container.read(careProfilesProvider).isLoading, isTrue);
    await _settle();

    final profiles = container.read(careProfilesProvider);
    expect(profiles.load, CareProfilesLoad.loaded);
    expect(profiles.entries.map((e) => e.remoteId), ['p-done', 'p-half']);
    expect(profiles.entries.last.pending, isTrue, reason: 'inProgress 는 입력 중이다');
    expect(profiles.selected?.id, 'p-done');
    expect(profiles.selected?.details.occupation, '재봉 일을 오래 하셨어요.');

    final bundle = await container.read(profileProvider.future);
    expect(bundle!.profile.profileId, 'p-done', reason: '카드 생성에 서버 ID 를 쓴다');
  });

  test('서버에 닿지 못하면 실패로 두고 다시 불러올 수 있다', () async {
    final server = FakeProfileServer(
      profiles: [FakeProfileServer.profile(id: 'p1', setupStatus: 'completed')],
    )..offline = true;
    final container = _container(server);

    container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));
    await _settle();

    final failed = container.read(careProfilesProvider);
    expect(failed.loadFailed, isTrue);
    expect(failed.hasSelected, isFalse);

    server.offline = false;
    await container.read(careProfilesProvider.notifier).reload();

    expect(container.read(careProfilesProvider).load, CareProfilesLoad.loaded);
    expect(container.read(careProfilesProvider).selected?.remoteId, 'p1');
  });

  test('로그아웃하면 목록을 비우고 서버를 다시 부르지 않는다', () async {
    final server = FakeProfileServer(
      profiles: [FakeProfileServer.profile(id: 'p1', setupStatus: 'completed')],
    );
    final container = _container(server);
    container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));
    await _settle();
    final before = server.requests.length;

    container.read(sessionProvider.notifier).discard();
    await _settle();

    final profiles = container.read(careProfilesProvider);
    expect(profiles.entries, isEmpty);
    expect(profiles.load, CareProfilesLoad.local);
    expect(server.requests.length, before);
  });

  test('서버에 저장한 분은 마치면 그 자리를 채우고 새로 만들지 않는다', () async {
    final server = FakeProfileServer(
      profiles: [FakeProfileServer.profile(id: 'p-half')],
    );
    final container = _container(server);
    container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));
    await _settle();

    container
        .read(careProfilesProvider.notifier)
        .startWith(
          const EnteredBasicInfo(
            name: '김새록',
            gender: 'female',
            birthDate: '1943-03-12',
            stage: ConditionStage.mildDementia,
          ),
          remoteId: 'p-half',
        );

    final profiles = container.read(careProfilesProvider);
    expect(profiles.entries, hasLength(1));
    expect(profiles.selected?.remoteId, 'p-half');
    expect(profiles.selected?.pending, isFalse);
  });
}
