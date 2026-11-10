// 어르신 등록 세부 정보의 단말 초안을 확인한다(2026-11-10 UX 점검 15).
//
// 하시던 일, 고향, 취미, 가족은 사진 단계를 마칠 때만 서버에 저장한다. 그 전에
// 앱이 꺼지면 다시 열었을 때 빈 칸부터 다시 해야 했다. 입력하는 동안 단말에
// 초안을 남기고, 다시 열면 멈춘 단계부터 이어서 여는지 본다. 등록을 마치거나
// 그만두면 초안을 지운다.
//
// 서버는 `FakeProfileServer`, 단말 저장소는 `FakeSetupDraftStore` 다. 앱을 다시
// 켜는 것은 같은 서버와 저장소로 새 컨테이너를 만드는 것으로 대신한다. 값은
// 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_relationship_store.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/selected_profile_store.dart';
import 'package:saerok/data/setup_draft_store.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile_setup/photo_picker.dart';
import 'package:saerok/features/profile_setup/photo_uploader.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/profile_setup/setup_draft_keeper.dart';

import 'fake_card_api.dart';
import 'fake_profile_relationship_store.dart';
import 'fake_profile_server.dart';
import 'fake_report_server.dart';
import 'fake_selected_profile_store.dart';
import 'fake_setup_draft_store.dart';

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

const _filled = SetupDraft(
  name: '김새록',
  gender: 'female',
  relationship: '어머니',
  birthYear: 1943,
  birthMonth: 3,
  birthDay: 12,
  stage: ConditionStage.mildDementia,
);

const _job = '30년 동안 초등학교 선생님을 하셨어요.';
const _hometown = '태어나신 곳은 부산 영도구예요.';

/// 올리면 바로 성공한다. 파일을 읽지 않는다.
class _OkUploader implements PhotoUploader {
  int uploads = 0;

  @override
  Future<void> upload(PickedPhoto photo, {String? profileId}) async =>
      uploads += 1;
}

/// 화면 테스트는 카드 대역([withMockCards])을 따로 넣으므로 [cards] 를 끈다.
List<Override> _overrides(
  FakeProfileServer server,
  SetupDraftStore store, {
  PhotoUploader? uploader,
  bool cards = true,
}) => [
  server.override,
  setupDraftStoreProvider.overrideWithValue(store),
  selectedProfileStoreProvider.overrideWithValue(FakeSelectedProfileStore()),
  profileRelationshipStoreProvider.overrideWithValue(
    FakeProfileRelationshipStore(),
  ),
  if (cards) cardApiProvider.overrideWithValue(FakeCardApi()),
  photoUploaderProvider.overrideWithValue(uploader ?? _OkUploader()),
];

/// 앱을 켜고 [accountId] 로 로그인한 세션을 되살린다. 어르신 목록을 서버에서
/// 다 불러올 때까지 기다린다.
Future<ProviderContainer> _launch(
  FakeProfileServer server,
  SetupDraftStore store, {
  String accountId = 'account-a',
  PhotoUploader? uploader,
  bool signedIn = true,
}) async {
  final container = ProviderContainer(
    overrides: _overrides(server, store, uploader: uploader),
  );
  addTearDown(container.dispose);
  container.listen(careProfilesProvider, (_, _) {});
  if (signedIn) {
    container.read(sessionProvider.notifier).restore(_sessionOf(accountId));
  }
  await _settle();
  return container;
}

/// 서버와 저장소에 다녀올 때까지 기다린다.
Future<void> _settle() => Future<void>.delayed(
  Duration.zero,
).then((_) => Future<void>.delayed(const Duration(milliseconds: 10)));

/// 홈에서 첫 분 등록을 시작해 기본 정보를 마치고(2-2), 하시던 일과 고향을
/// 답한 뒤 취미 단계에 멈춘다. 앱에서 [startProfileSetup] 이 하는 대로
/// `입력 중` 슬롯을 연다.
Future<String> _stopAtHobby(ProviderContainer container) async {
  final slot = container.read(careProfilesProvider.notifier).beginAdding()!;
  final controller = container.read(setupControllerProvider.notifier);
  controller.updateDraft(_filled);
  await controller.submitBasicInfo(addingId: slot);
  controller.recordFact('occupation', _job);
  controller.next();
  controller.recordFact('hometown', _hometown);
  controller.next();
  await _settle();
  return slot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('입력하는 동안', () {
    test('첫 분의 세부 정보 답과 멈춘 단계를 단말에 남긴다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);

      await _stopAtHobby(container);

      final draft = store.draftOf('account-a', 'server-1');
      expect(draft, isNotNull, reason: '서버에 프로필을 만든 뒤부터 남긴다');
      expect(draft!.facts, {'occupation': _job, 'hometown': _hometown});
      expect(draft.reachedIndex, 3, reason: '취미 단계에 멈췄다');
      expect(draft.uploadedPhotos, 0);
    });

    test('글로 된 답만 남기고 기본 정보와 녹음은 두지 않는다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);

      await _stopAtHobby(container);

      final raw =
          store.values[FakeSetupDraftStore.keyOf('account-a', 'server-1')]!;
      expect(raw, contains(_job));
      expect(raw, isNot(contains('김새록')), reason: '기본 정보는 서버에 있다');
      expect(raw, isNot(contains('1943')));
      expect(raw, isNot(contains('.wav')));
    });

    test('기본 정보를 마치기 전에는 남기지 않는다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);

      container.read(careProfilesProvider.notifier).beginAdding();
      container.read(setupControllerProvider.notifier).updateDraft(_filled);
      await _settle();

      expect(store.values, isEmpty);
    });

    test('로그인하지 않았으면 단말에 남기지 않는다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store, signedIn: false);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      controller.recordFact('occupation', _job);
      await _settle();

      expect(store.values, isEmpty);
      expect(store.writes, 0);
    });
  });

  group('앱을 다시 켜면', () {
    test('서버의 기본 정보에 초안을 더해 멈춘 단계부터 연다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final first = await _launch(server, store);
      await _stopAtHobby(first);
      first.dispose();

      final second = await _launch(server, store);
      final entry = second.read(careProfilesProvider).entries.single;
      expect(entry.pending, isTrue, reason: '서버에는 입력 중으로 남아 있다');

      await second.read(setupControllerProvider.notifier).resume(entry.id);

      final state = second.read(setupControllerProvider);
      expect(state.stepIndex, 3, reason: '취미 단계부터 연다');
      expect(state.lifeFactStep?.category, 'hobby');
      expect(state.draft.facts, {'occupation': _job, 'hometown': _hometown});
      expect(state.draft.name, '김새록', reason: '기본 정보는 서버 값이다');
      expect(state.remoteId, 'server-1');
    });

    test('초안이 없으면 지금처럼 서버 값으로 세부 정보 첫 항목부터 연다', () async {
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1', occupation: '우체국 집배원')],
      );
      final container = await _launch(server, FakeSetupDraftStore());

      await container.read(setupControllerProvider.notifier).resume('p1');

      final state = container.read(setupControllerProvider);
      expect(state.stepIndex, 1);
      expect(state.draft.facts, {'occupation': '우체국 집배원'});
      expect(state.draft.uploadedBefore, 0);
    });

    test('다른 계정은 앞 계정의 초안을 읽지 않는다', () async {
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1')],
      );
      final store = FakeSetupDraftStore()
        ..values[FakeSetupDraftStore.keyOf(
          'account-a',
          'p1',
        )] = const SavedSetupDraft(
          facts: {'occupation': _job},
          reachedIndex: 3,
        ).encode();
      final container = await _launch(server, store, accountId: 'account-b');

      await container.read(setupControllerProvider.notifier).resume('p1');

      final state = container.read(setupControllerProvider);
      expect(state.stepIndex, 1);
      expect(state.draft.facts, isEmpty);
    });

    test('앱이 켜진 동안 남긴 입력이 있으면 그것을 먼저 쓴다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);
      final slot = await _stopAtHobby(container);
      container
          .read(pendingSetupsProvider.notifier)
          .save(slot, container.read(setupControllerProvider));
      // 기본 정보로 돌아가 나간 것처럼 둔다.
      final controller = container.read(setupControllerProvider.notifier);
      controller.back();
      controller.back();
      controller.back();
      // 단말 초안이 다른 값이어도 앱에 남은 입력을 쓴다.
      store.values[FakeSetupDraftStore.keyOf(
        'account-a',
        'server-1',
      )] = const SavedSetupDraft(
        facts: {'occupation': '다른 답'},
        reachedIndex: 1,
      ).encode();

      await controller.resume(slot);

      final state = container.read(setupControllerProvider);
      expect(state.stepIndex, 3);
      expect(state.draft.facts['occupation'], _job);
    });
  });

  group('사진', () {
    test('올린 사진 수를 남기고 다시 열면 그만큼 덜 고른다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final first = await _launch(server, store);
      await _stopAtHobby(first);
      final controller = first.read(setupControllerProvider.notifier);
      controller.next();
      controller.next();
      expect(first.read(setupControllerProvider).isPhoto, isTrue);
      controller.addPhotos(const [PickedPhoto('a.jpg'), PickedPhoto('b.jpg')]);
      await controller.uploadPhotos();
      await _settle();

      final draft = store.draftOf('account-a', 'server-1')!;
      expect(draft.uploadedPhotos, 2);
      expect(draft.reachedIndex, 5);
      expect(
        store.values.values.single,
        isNot(contains('a.jpg')),
        reason: '고른 사진의 경로는 남기지 않는다',
      );
      first.dispose();

      final second = await _launch(server, store);
      final resumed = second.read(setupControllerProvider.notifier);
      await resumed.resume('server-1');

      var state = second.read(setupControllerProvider);
      expect(state.isPhoto, isTrue, reason: '사진 단계부터 연다');
      expect(state.draft.uploadedBefore, 2);
      expect(state.draft.photos, isEmpty);

      resumed.addPhotos([
        for (var i = 0; i < 5; i++) PickedPhoto('more-$i.jpg'),
      ]);
      state = second.read(setupControllerProvider);
      expect(state.draft.photos, hasLength(3), reason: '앞서 올린 2장과 합쳐 5장까지다');
    });
  });

  group('초안을 지운다', () {
    test('등록을 마치면 지운다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);
      final slot = await _stopAtHobby(container);
      expect(store.values, isNotEmpty);

      await container
          .read(setupControllerProvider.notifier)
          .finish(addingId: slot);
      await _settle();

      expect(store.values, isEmpty);
    });

    test('세부 정보를 저장하지 못하면 남긴다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);
      final slot = await _stopAtHobby(container);
      server.failures['PATCH /api/v1/profiles/server-1'] = (
        status: 503,
        errorCode: 'SERVICE_UNAVAILABLE',
      );

      await expectLater(
        container.read(setupControllerProvider.notifier).finish(addingId: slot),
        throwsA(anything),
      );
      await _settle();

      expect(store.draftOf('account-a', 'server-1')?.facts, hasLength(2));
    });

    test('입력 중인 분을 그만두면 지운다', () async {
      final server = FakeProfileServer();
      final store = FakeSetupDraftStore();
      final container = await _launch(server, store);
      final slot = await _stopAtHobby(container);

      container
          .read(pendingSetupsProvider.notifier)
          .remove(slot, remoteId: 'server-1');
      await _settle();

      expect(store.values, isEmpty);
    });

    test('탈퇴하면 그 계정의 초안만 모두 지운다', () async {
      final store = FakeSetupDraftStore()
        ..values[FakeSetupDraftStore.keyOf('account-a', 'p1')] = '{}'
        ..values[FakeSetupDraftStore.keyOf('account-a', 'p2')] = '{}'
        ..values[FakeSetupDraftStore.keyOf('account-b', 'p3')] = '{}';

      await SetupDraftKeeper(store).clearAccount('account-a');

      expect(store.values.keys, [FakeSetupDraftStore.keyOf('account-b', 'p3')]);
    });
  });

  group('쓰는 차례', () {
    test('쓰는 동안 바뀐 값은 마지막 것 하나만 쓴다', () async {
      final store = _GatedStore();
      final keeper = SetupDraftKeeper(store);

      keeper.keep('a', 'p1', const SavedSetupDraft(facts: {'hobby': '등'}));
      await _settle();
      keeper.keep('a', 'p1', const SavedSetupDraft(facts: {'hobby': '등산'}));
      keeper.keep('a', 'p1', const SavedSetupDraft(facts: {'hobby': '등산을'}));
      store.release();
      await _settle();
      store.release();
      await _settle();

      expect(store.written, ['등', '등산을']);
    });

    test('마친 뒤 늦게 끝난 쓰기가 지운 초안을 되살리지 않는다', () async {
      final store = _GatedStore();
      final keeper = SetupDraftKeeper(store);

      keeper.keep('a', 'p1', const SavedSetupDraft(facts: {'hobby': '등'}));
      await _settle();
      keeper.keep('a', 'p1', const SavedSetupDraft(facts: {'hobby': '등산'}));
      final cleared = keeper.clear('a', 'p1');
      store.release();
      await cleared;

      expect(store.written, ['등'], reason: '지우기 전에 기다리던 쓰기는 버린다');
      expect(store.cleared, 1);
      expect(store.current, isNull);
    });
  });

  group('화면', () {
    /// 로그인한 상태로 앱을 띄운다. [store] 와 [server] 는 앱을 다시 켜도 같다.
    Future<ProviderContainer> openApp(
      WidgetTester tester,
      FakeProfileServer server,
      FakeSetupDraftStore store,
      String location,
    ) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final sample = (await tester.runAsync(
        () => const MockRepository().loadProfile(),
      ))!;
      final account = (await tester.runAsync(
        () => const MockRepository().loadAccount(),
      ))!;
      final container = ProviderContainer(
        overrides: [
          ..._overrides(server, store, cards: false),
          ...withMockCards,
          FakeReportServer().override,
          profileSampleProvider.overrideWith((ref) async => sample),
          accountProvider.overrideWith((ref) async => account),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).restore(_sessionOf('account-a'));

      final router = buildRouter();
      addTearDown(router.dispose);
      router.go(location);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: router,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 50; i++) {
        if (!container.read(careProfilesProvider).isLoading) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    /// 답하는 방법 버튼은 눌린 모습을 0.18초 보인 뒤 넘어간다.
    Future<void> chooseText(WidgetTester tester) async {
      await tester.tap(find.text('글로 답하기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    /// 앱을 끈다. 화면과 컨테이너를 버린다.
    Future<void> closeApp(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }

    testWidgets('글로 적던 답을 남기고 앱을 다시 켜 홈에서 누르면 그 항목부터 이어서 연다', (tester) async {
      // 기본 정보를 마쳐 서버에 입력 중으로 만든 첫 분이다.
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1')],
      );
      final store = FakeSetupDraftStore();

      final first = await openApp(tester, server, store, AppRoutes.home);
      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));
      expect(find.text('예전에 어떤 일을\n하셨나요?'), findsOneWidget);
      await chooseText(tester);
      await tester.enterText(find.byType(TextField), _job);
      await tester.pump();
      await tapAndSettle(tester, find.text('다음'));
      await chooseText(tester);
      await tester.enterText(find.byType(TextField), _hometown);
      await tester.pump();
      await tester.runAsync(_settle);
      expect(store.draftOf('account-a', 'p1')?.facts, {
        'occupation': _job,
        'hometown': _hometown,
      });

      // 고향을 적던 중 앱이 꺼졌다.
      await closeApp(tester, first);

      await openApp(tester, server, store, AppRoutes.home);
      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));

      expect(find.text('고향이나 사셨던\n동네는 어디인가요?'), findsOneWidget);
      expect(find.text(_hometown), findsOneWidget, reason: '적던 답이 입력칸에 남아 있다');

      await tapAndSettle(tester, find.byTooltip('뒤로'));
      expect(find.text('예전에 어떤 일을\n하셨나요?'), findsOneWidget);
      expect(find.text(_job), findsOneWidget);
    });

    testWidgets('앱을 다시 켜기 전에 올린 사진 수를 사진 단계에 보여준다', (tester) async {
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1')],
      );
      final store = FakeSetupDraftStore()
        ..values[FakeSetupDraftStore.keyOf(
          'account-a',
          'p1',
        )] = const SavedSetupDraft(
          facts: {'occupation': _job},
          reachedIndex: 5,
          uploadedPhotos: 2,
        ).encode();

      await openApp(tester, server, store, AppRoutes.home);
      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));

      expect(find.text('김새록님과 관련된 사진을\n올려주세요'), findsOneWidget);
      expect(find.text('2장을 올렸어요. 3장 더 올릴 수 있어요.'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget, reason: '올린 사진이 있으니 건너뛰기가 아니다');
      expect(find.text('건너뛰기'), findsNothing);
    });

    testWidgets('다섯 장을 다 올린 뒤 다시 켜면 더 고르는 자리를 두지 않는다', (tester) async {
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1')],
      );
      final store = FakeSetupDraftStore()
        ..values[FakeSetupDraftStore.keyOf('account-a', 'p1')] =
            const SavedSetupDraft(reachedIndex: 5, uploadedPhotos: 5).encode();

      await openApp(tester, server, store, AppRoutes.home);
      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));

      expect(find.text('사진 5장을 모두 올렸어요.'), findsOneWidget);
      expect(find.text('사진 추가하기'), findsNothing, reason: '눌러도 열리지 않는다');
      expect(find.text('홈으로'), findsOneWidget);
    });

    testWidgets('입력 중인 분을 지우면 단말 초안도 지운다', (tester) async {
      final server = FakeProfileServer(
        profiles: [FakeProfileServer.profile(id: 'p1')],
      );
      final store = FakeSetupDraftStore()
        ..values[FakeSetupDraftStore.keyOf(
          'account-a',
          'p1',
        )] = const SavedSetupDraft(
          facts: {'occupation': _job},
          reachedIndex: 2,
        ).encode();

      await openApp(tester, server, store, AppRoutes.profileSwitch);
      await tapAndSettle(tester, find.text('프로필 정보 지우기'));
      // 앱을 다시 켠 뒤라 이름은 앱에 남아 있지 않다.
      await tapAndSettle(tester, find.text('새로운 분'));
      await tapAndSettle(tester, find.text('지우기'));
      await tester.runAsync(_settle);

      expect(server.profiles, isEmpty, reason: '서버에서 먼저 지운다(2-8)');
      expect(store.values, isEmpty);
    });
  });
}

/// 쓰기를 [release] 할 때까지 붙잡는 저장소다. 느린 단말 저장소를 흉내 낸다.
class _GatedStore implements SetupDraftStore {
  final _gates = <Completer<void>>[];

  /// 다 쓴 초안의 취미 항목.
  final written = <String>[];
  int cleared = 0;
  SavedSetupDraft? current;

  void release() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<SavedSetupDraft?> read(String accountId, String profileId) async =>
      current;

  @override
  Future<void> write(
    String accountId,
    String profileId,
    SavedSetupDraft draft,
  ) async {
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    written.add(draft.facts['hobby'] ?? '');
    current = draft;
  }

  @override
  Future<void> clear(String accountId, String profileId) async {
    cleared += 1;
    current = null;
  }

  @override
  Future<void> clearAccount(String accountId) async => current = null;
}
