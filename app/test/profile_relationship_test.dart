// 관계는 서버에 보내지 않고 단말에만 두는지 확인한다.
//
// 서버는 `FakeProfileServer`, 단말 저장소는 `FakeProfileRelationshipStore` 다. 앱을
// 다시 켜는 것은 같은 서버와 저장소로 새 컨테이너를 만드는 것으로 대신한다. 값은
// 모두 합성이다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_relationship_store.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/selected_profile_store.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

import 'fake_profile_relationship_store.dart';
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

/// 앱을 켜고 [accountId] 로 로그인한 세션을 되살린다.
Future<ProviderContainer> _launch(
  FakeProfileServer server,
  FakeProfileRelationshipStore store, {
  String accountId = 'account-a',
}) async {
  final container = ProviderContainer(
    overrides: [
      server.override,
      selectedProfileStoreProvider.overrideWithValue(
        FakeSelectedProfileStore(),
      ),
      profileRelationshipStoreProvider.overrideWithValue(store),
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

FakeProfileServer _serverWith(List<String> ids) => FakeProfileServer(
  profiles: [
    for (final id in ids)
      FakeProfileServer.profile(id: id, setupStatus: 'completed'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('부르는 이름은 관계가 있으면 괄호로 붙이고 없으면 이름만 쓴다', () {
    expect(careDisplayName('김철수', '아버지'), '김철수님 (아버지)');
    expect(careDisplayName('김철수', null), '김철수님');
    expect(careDisplayName('김철수', '  '), '김철수님');
  });

  test('다시 켜면 단말에 둔 관계를 붙이고 다른 계정의 값은 쓰지 않는다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeProfileRelationshipStore()
      ..values['account-a'] = {'p1': '어머니'}
      ..values['account-b'] = {'p2': '아버지'};

    final container = await _launch(server, store);

    final entries = container.read(careProfilesProvider).entries;
    expect(entries.map((e) => e.basicInfo!.relationship), ['어머니', null]);
  });

  test('기본 정보를 서버에 만들면 관계는 보내지 않고 단말에 기억한다', () async {
    final server = FakeProfileServer();
    final store = FakeProfileRelationshipStore();
    final container = await _launch(server, store);
    final controller = container.read(setupControllerProvider.notifier);

    controller.updateDraft(
      const SetupDraft(
        name: '김새록',
        gender: 'female',
        relationship: ' 외할머니 ',
        birthYear: 1943,
        birthMonth: 3,
        birthDay: 12,
        stage: ConditionStage.mildDementia,
      ),
    );
    await controller.submitBasicInfo();
    await _settle();

    final created = server.requests.singleWhere((r) => r.method == 'POST');
    expect((created.body as Map).containsKey('relationship'), isFalse);
    expect(store.values['account-a'], {'server-1': '외할머니'});
  });

  test('관계는 적지 않아도 기본 정보를 마칠 수 있다', () {
    const draft = SetupDraft(
      name: '김새록',
      gender: 'female',
      birthYear: 1943,
      birthMonth: 3,
      birthDay: 12,
      stage: ConditionStage.mildDementia,
    );

    expect(draft.basicInfoFilled, isTrue);
    expect(draft.toBasicInfo()!.relationship, isNull);
    expect(
      draft.copyWith(relationship: '가' * 21).basicInfoFilled,
      isFalse,
      reason: '관계는 20자까지다',
    );
  });

  test('관계를 고치면 단말 값을 바꾸고 비우면 지운다', () async {
    final server = _serverWith(['p1']);
    final store = FakeProfileRelationshipStore()
      ..values['account-a'] = {'p1': '어머니'};
    final container = await _launch(server, store);
    final profiles = container.read(careProfilesProvider.notifier);
    final info = container.read(careProfilesProvider).byId('p1')!.basicInfo!;

    profiles.updateBasicInfo('p1', info.withRelationship('큰어머니'));
    await _settle();
    expect(store.values['account-a'], {'p1': '큰어머니'});

    profiles.updateBasicInfo('p1', info.withRelationship(null));
    await _settle();
    expect(store.values['account-a'], isEmpty);
  });

  test('프로필을 지우면 단말에 둔 관계도 지운다', () async {
    final server = _serverWith(['p1', 'p2']);
    final store = FakeProfileRelationshipStore()
      ..values['account-a'] = {'p1': '어머니', 'p2': '아버지'};
    final container = await _launch(server, store);

    container.read(careProfilesProvider.notifier).remove('p1');
    await _settle();

    expect(store.values['account-a'], {'p2': '아버지'});
  });
}
