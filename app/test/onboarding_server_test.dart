// 로그인한 상태의 프로필 입력이 서버(`api-spec.md` 2-2, 2-4)에 저장되는지 확인한다.
//
// 서버는 `FakeProfileServer` 다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

import 'fake_card_api.dart';
import 'fake_profile_server.dart';

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

const _filled = SetupDraft(
  name: '김새록',
  gender: 'female',
  birthYear: 1943,
  birthMonth: 3,
  birthDay: 12,
  stage: ConditionStage.mildDementia,
);

/// 4-1 이 늘 네트워크 오류로 실패한다.
class _OfflineCardApi extends FakeCardApi {
  @override
  Future<CardGenerationStatus> requestGeneration(String profileId) async {
    calls.add('request');
    throw const ApiNetworkFailure();
  }
}

/// 로그인한 상태의 컨테이너다. 어르신 목록은 서버에서 빈 목록으로 온다.
/// 카드 API 를 넘기지 않으면 요청을 받아들이는 대역을 쓴다.
Future<ProviderContainer> _signedIn(
  FakeProfileServer server, {
  CardApi? cardApi,
}) async {
  final container = ProviderContainer(
    overrides: [
      server.override,
      cardApiProvider.overrideWithValue(cardApi ?? FakeCardApi()),
    ],
  );
  addTearDown(container.dispose);
  container.listen(careProfilesProvider, (_, _) {});
  container.read(sessionProvider.notifier).restore(_session());
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('기본 정보를 마치면', () {
    test('서버에 프로필을 만들고 다음 단계로 간다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();

      final created = server.requests.where((r) => r.method == 'POST');
      expect(created, hasLength(1));
      expect(created.single.body, {
        'name': '김새록',
        'gender': 'female',
        'birthDate': '1943-03-12',
        'condition': {'stage': 'mildDementia', 'symptomNote': null},
      });
      final state = container.read(setupControllerProvider);
      expect(state.remoteId, 'server-1');
      expect(state.stepIndex, 1);
    });

    test('돌아와 다시 마치면 새로 만들지 않고 고친다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      controller.back();
      controller.updateDraft(_filled.copyWith(name: '김새봄'));
      await controller.submitBasicInfo();

      expect(server.requests.where((r) => r.method == 'POST'), hasLength(1));
      final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/api/v1/profiles/server-1');
      expect((patch.body as Map)['name'], '김새봄');
      expect(server.profiles, hasLength(1));
    });

    test('어르신을 더 등록하는 중이면 그 슬롯에 서버 ID 를 붙인다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final slot = container.read(careProfilesProvider.notifier).beginAdding()!;
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo(addingId: slot);

      final entry = container.read(careProfilesProvider).byId(slot)!;
      expect(entry.remoteId, 'server-1');
      expect(entry.pending, isTrue, reason: '마치기 전이라 아직 입력 중이다');
    });
  });

  group('마치면', () {
    test('세부 정보를 저장하고 그 분을 서버 ID 로 고른다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      controller.recordFact('occupation', '재봉 일을 오래 하셨어요.');
      await controller.finish();

      final patch = server.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.body, {
        'occupation': '재봉 일을 오래 하셨어요.',
        'hometown': null,
        'hobby': null,
        'family': null,
      });
      final selected = container.read(careProfilesProvider).selected!;
      expect(selected.remoteId, 'server-1');
      expect(selected.details.occupation, '재봉 일을 오래 하셨어요.');
    });

    test('저장하지 못하면 목록에 넣지 않는다', () async {
      final server = FakeProfileServer();
      final container = await _signedIn(server);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      server.offline = true;

      await expectLater(controller.finish(), throwsA(isA<Object>()));
      expect(container.read(careProfilesProvider).entries, isEmpty);
    });

    test('세부 정보를 저장한 뒤 그 분의 첫 카드 생성을 요청한다', () async {
      final server = FakeProfileServer();
      final cards = FakeCardApi();
      final container = await _signedIn(server, cardApi: cards);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      await controller.finish();

      expect(cards.calls, ['request']);
      expect(cards.profileIds, ['server-1']);
    });

    test('세부 정보를 저장하지 못하면 카드 생성을 요청하지 않는다', () async {
      final server = FakeProfileServer();
      final cards = FakeCardApi();
      final container = await _signedIn(server, cardApi: cards);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      server.offline = true;

      await expectLater(controller.finish(), throwsA(isA<Object>()));
      expect(cards.calls, isEmpty);
    });

    test('카드 생성 요청이 실패해도 등록은 마친다', () async {
      final server = FakeProfileServer();
      final cards = _OfflineCardApi();
      final container = await _signedIn(server, cardApi: cards);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      await controller.finish();

      expect(cards.calls, ['request']);
      final selected = container.read(careProfilesProvider).selected!;
      expect(selected.remoteId, 'server-1');
      expect(selected.pending, isFalse);
    });
  });

  group('로그인하지 않았으면', () {
    test('서버를 부르지 않고 그대로 넘어간다', () async {
      final server = FakeProfileServer();
      final cards = FakeCardApi();
      final container = ProviderContainer(
        overrides: [server.override, cardApiProvider.overrideWithValue(cards)],
      );
      addTearDown(container.dispose);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(_filled);
      await controller.submitBasicInfo();
      await controller.finish();

      expect(server.requests, isEmpty);
      expect(cards.calls, isEmpty);
      expect(container.read(careProfilesProvider).selected?.remoteId, isNull);
    });
  });

  testWidgets('기본 정보 저장이 거절되면 이유를 알리고 그 단계에 남는다', (tester) async {
    tester.view.physicalSize = const Size(1236, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final server = FakeProfileServer()
      ..failures['POST /api/v1/profiles'] = (
        status: 409,
        errorCode: 'PROFILE_LIMIT_EXCEEDED',
      );
    final container = ProviderContainer(overrides: [server.override]);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).restore(_session());
    container.read(setupControllerProvider.notifier).updateDraft(_filled);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ProfileSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '다음'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('어르신은 세 분까지 등록할 수 있어요.'), findsOneWidget);
    expect(find.text('기본 정보 입력'), findsOneWidget, reason: '다음 단계로 가지 않는다');
    expect(container.read(setupControllerProvider).remoteId, isNull);
  });
}
