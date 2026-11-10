// 생년월일 입력 규칙을 확인한다(감사 16번, 2026-11-10 PM 결정 방법 1).
//
// 없는 날짜를 고르지 못하고, 해 목록이 서버 기준(만 10세 이상, 미래 아님)과
// 같으며, 나이로 입력하면 오늘에서 그 나이만큼 뺀 날을 보내고 화면에는
// `82세(나이로 입력)` 로 보이는지 본다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/auth_api.dart';
import 'package:saerok/data/birth_date.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_api.dart';
import 'package:saerok/data/profile_birth_input_store.dart';
import 'package:saerok/data/profile_relationship_store.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/data/selected_profile_store.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/auth/auth_providers.dart';
import 'package:saerok/features/auth/auth_session.dart';
import 'package:saerok/features/life_story/life_story.dart';
import 'package:saerok/features/profile/profile_basic_edit_screen.dart';
import 'package:saerok/features/profile/profile_screen.dart';
import 'package:saerok/features/profile_setup/basic_info_step.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';

import 'fake_profile_birth_input_store.dart';
import 'fake_profile_relationship_store.dart';
import 'fake_profile_server.dart';
import 'fake_selected_profile_store.dart';

const _base = SetupDraft(
  name: '김새록',
  gender: 'female',
  stage: ConditionStage.mildDementia,
);

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

/// 오늘 82세가 되는, 나이로 입력한 분이다.
EnteredBasicInfo _byAgeInfo() => EnteredBasicInfo(
  name: '김새록',
  gender: 'female',
  birthDate: isoDate(birthDateForAge(82, DateTime.now())),
  stage: ConditionStage.mildDementia,
  birthByAge: true,
);

class _ByAgeProfiles extends CareProfilesNotifier {
  @override
  CareProfiles build() => CareProfiles(
    entries: [CareProfileEntry(id: 'p1', basicInfo: _byAgeInfo())],
    selectedId: 'p1',
  );
}

/// [BasicInfoStep] 만 띄운다. 고친 값은 [onDraft] 로 알린다.
Future<void> _pumpStep(
  WidgetTester tester,
  SetupDraft initial, {
  required DateTime now,
  void Function(SetupDraft draft)? onDraft,
}) async {
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  var draft = initial;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => BasicInfoStep(
              draft: draft,
              now: now,
              onChanged: (next) {
                setState(() => draft = next);
                onDraft?.call(next);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// 세 칸 중 [index] 번째(0 = 년, 1 = 월, 2 = 일)에서 고를 수 있는 값.
List<int> _choices(WidgetTester tester, int index) => [
  for (final item
      in tester
          .widget<DropdownButton<int>>(
            find.byType(DropdownButton<int>).at(index),
          )
          .items!)
    item.value!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('날짜 계산', () {
    test('그달의 날 수는 윤년을 따른다', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2023, 2), 28);
      expect(daysInMonth(1900, 2), 28, reason: '100으로 나눠지면 평년');
      expect(daysInMonth(2000, 2), 29, reason: '400으로 나눠지면 윤년');
      expect(daysInMonth(1943, 4), 30);
      expect(isRealDate(1943, 2, 30), isFalse);
      expect(isRealDate(1943, 4, 31), isFalse);
      expect(isRealDate(1944, 2, 29), isTrue);
    });

    test('나이를 날짜로 바꾸면 오늘과 같은 월, 일이고 오늘 그 나이다', () {
      final today = DateTime(2026, 11, 10);
      final birth = birthDateForAge(82, today);
      expect(birth, DateTime(1944, 11, 10));
      expect(ageOn(birth, today), 82);
      expect(ageOn(birth, DateTime(2027, 11, 9)), 82, reason: '생일 전날');
      expect(ageOn(birth, DateTime(2027, 11, 10)), 83, reason: '해마다 한 살 는다');
    });

    test('2월 29일에 나이로 입력하면 평년은 2월 28일로 둔다', () {
      final today = DateTime(2028, 2, 29);
      expect(birthDateForAge(82, today), DateTime(1946, 2, 28));
      expect(ageOn(birthDateForAge(82, today), today), 82);
      expect(birthDateForAge(80, today), DateTime(1948, 2, 29), reason: '윤년');
      expect(ageOn(birthDateForAge(80, today), today), 80);
    });

    test('해가 바뀌는 날에도 나이가 맞다', () {
      final newYear = DateTime(2027, 1, 1);
      expect(birthDateForAge(82, newYear), DateTime(1945, 1, 1));
      expect(ageOn(DateTime(1945, 1, 1), newYear), 82);
      final lastDay = DateTime(2026, 12, 31);
      expect(birthDateForAge(82, lastDay), DateTime(1944, 12, 31));
      expect(ageOn(DateTime(1944, 12, 31), lastDay), 82);
      expect(ageOn(DateTime(1944, 12, 31), newYear), 82);
    });

    test('가장 늦은 생년월일은 오늘 만 10세가 되는 날이다', () {
      expect(
        latestBirthDate(DateTime.utc(2026, 11, 10, 12)),
        DateTime(2016, 11, 10),
      );
      expect(
        latestBirthDate(DateTime.utc(2028, 2, 29, 12)),
        DateTime(2018, 2, 28),
        reason: '서버의 latest_birth_date 와 같다',
      );
    });

    test('나이로 입력한 분은 날짜 대신 나이를 보여준다', () {
      final today = DateTime(2026, 11, 10);
      expect(
        birthDateText('1944-11-10', byAge: true, today: today),
        '82세(나이로 입력)',
      );
      expect(
        birthDateText('1944-11-10', byAge: true, today: DateTime(2027, 11, 10)),
        '83세(나이로 입력)',
      );
      expect(birthDateText('1943-03-12', byAge: false), '1943년 3월 12일');
      expect(birthDateLabel('1943-03-12'), '1943년 3월 12일');
    });
  });

  group('입력값', () {
    final now = DateTime(2026, 11, 10, 12);

    test('2월 29일을 고른 뒤 평년으로 바꾸면 일을 비운다', () {
      final draft = _base
          .withBirthPart(year: 1944, now: now)
          .withBirthPart(month: 2, now: now)
          .withBirthPart(day: 29, now: now);
      expect(draft.birthDay, 29);
      final changed = draft.withBirthPart(year: 1943, now: now);
      expect(changed.birthYear, 1943);
      expect(changed.birthMonth, 2);
      expect(changed.birthDay, isNull, reason: '1943년 2월 29일은 없다');
      expect(changed.basicInfoFilled, isFalse);
    });

    test('31일을 고른 뒤 4월로 바꾸면 일을 비운다', () {
      final draft = _base
          .withBirthPart(year: 1943, now: now)
          .withBirthPart(month: 3, now: now)
          .withBirthPart(day: 31, now: now)
          .withBirthPart(month: 4, now: now);
      expect(draft.birthDay, isNull);
    });

    test('없는 날짜는 마칠 수 없다', () {
      final draft = _base.copyWith(
        birthYear: 1943,
        birthMonth: 2,
        birthDay: 30,
      );
      expect(draft.basicInfoFilled, isFalse);
      expect(draft.toBasicInfo(), isNull);
    });

    test('만 10세가 안 된 날짜는 마칠 수 없다', () {
      final latest = latestBirthDate(DateTime.now());
      final ok = _base.copyWith(
        birthYear: latest.year,
        birthMonth: latest.month,
        birthDay: latest.day,
      );
      expect(ok.basicInfoFilled, isTrue);
      final tooYoung = latest.add(const Duration(days: 1));
      expect(
        _base
            .copyWith(
              birthYear: tooYoung.year,
              birthMonth: tooYoung.month,
              birthDay: tooYoung.day,
            )
            .basicInfoFilled,
        isFalse,
      );
    });

    test('나이로 입력하면 오늘에서 그 나이만큼 뺀 날을 보낸다', () {
      final draft = _base.copyWith(birthByAge: true).withAgeText('82');
      final info = draft.toBasicInfo(today: DateTime(2026, 11, 10))!;
      expect(info.birthDate, '1944-11-10');
      expect(info.birthByAge, isTrue);
    });

    test('나이는 50세부터 110세까지 받는다', () {
      final draft = _base.copyWith(birthByAge: true);
      expect(draft.basicInfoFilled, isFalse, reason: '나이를 적지 않았다');
      expect(draft.withAgeText('49').ageOutOfRange, isTrue);
      expect(draft.withAgeText('111').ageOutOfRange, isTrue);
      expect(draft.withAgeText('50').basicInfoFilled, isTrue);
      expect(draft.withAgeText('110').basicInfoFilled, isTrue);
      expect(draft.withAgeText('').age, isNull);
    });

    test('나이로 입력과 날짜로 입력을 오가도 값이 남는다', () {
      final dated = _base.copyWith(
        birthYear: 1943,
        birthMonth: 3,
        birthDay: 12,
      );
      final byAge = dated.copyWith(birthByAge: true).withAgeText('82');
      final back = byAge.copyWith(birthByAge: false);
      expect(back.toBasicInfo()!.birthDate, '1943-03-12');
      expect(back.toBasicInfo()!.birthByAge, isFalse);
      expect(back.copyWith(birthByAge: true).age, 82);
    });

    test('나이로 입력한 분을 고칠 때 나이를 그대로 두면 저장된 날짜를 보낸다', () {
      // 작년에 82세로 입력한 분은 올해 83세다.
      final info = EnteredBasicInfo(
        name: '김새록',
        gender: 'female',
        birthDate: '1943-11-10',
        stage: ConditionStage.mildDementia,
        birthByAge: true,
      );
      final today = DateTime(2026, 11, 10);
      final draft = SetupDraft.fromBasicInfo(info, today: today);
      expect(draft.birthByAge, isTrue);
      expect(draft.age, 83);
      expect(draft.birthYear, isNull, reason: '지어낸 날짜를 칸에 채우지 않는다');
      expect(draft.toBasicInfo(today: today)!.birthDate, '1943-11-10');
      expect(
        draft.withAgeText('84').toBasicInfo(today: today)!.birthDate,
        '1942-11-10',
      );
    });
  });

  group('기본 정보 화면', () {
    final now = DateTime(2026, 11, 10, 12);

    testWidgets('해 목록은 오늘 만 10세가 되는 해까지다', (tester) async {
      await _pumpStep(tester, _base, now: now);
      final years = _choices(tester, 0);
      expect(years.last, 2016);
      expect(years, contains(1990), reason: '1981년 이후 출생도 고른다');
      expect(years.first, lessThanOrEqualTo(1916), reason: '110세까지 고른다');
      expect(years, isNot(contains(2017)));
    });

    testWidgets('일 목록은 고른 달과 윤년을 따른다', (tester) async {
      await _pumpStep(
        tester,
        _base.copyWith(birthYear: 1943, birthMonth: 2),
        now: now,
      );
      expect(_choices(tester, 2).last, 28);

      await _pumpStep(
        tester,
        _base.copyWith(birthYear: 1944, birthMonth: 2),
        now: now,
      );
      expect(_choices(tester, 2).last, 29);

      await _pumpStep(
        tester,
        _base.copyWith(birthYear: 1943, birthMonth: 4),
        now: now,
      );
      expect(_choices(tester, 2).last, 30);
    });

    testWidgets('가장 늦은 해는 오늘까지의 월과 일만 고른다', (tester) async {
      await _pumpStep(
        tester,
        _base.copyWith(birthYear: 2016, birthMonth: 11),
        now: now,
      );
      expect(_choices(tester, 1).last, 11);
      expect(_choices(tester, 2).last, 10);
    });

    testWidgets('나이로 입력을 누르면 나이 칸이 나오고 적은 나이를 쓴다', (tester) async {
      SetupDraft? last;
      await _pumpStep(tester, _base, now: now, onDraft: (d) => last = d);

      await tester.tap(find.text('나이로 입력'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.text('나이'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '8');
      await tester.pump();
      expect(find.textContaining('50세에서 110세 사이'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '82');
      await tester.pump();
      expect(find.textContaining('50세에서 110세 사이'), findsNothing);
      expect(last!.birthByAge, isTrue);
      expect(last!.age, 82);

      await tester.tap(find.text('날짜로 입력'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<int>), findsNWidgets(3));
    });
  });

  testWidgets('글자를 두 배로 키우면 입력 방식 두 칸을 위아래로 쌓는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpStep(tester, _base, now: DateTime(2026, 11, 10, 12));

    final byDate = tester.getRect(find.text('날짜로 입력'));
    final byAge = tester.getRect(find.text('나이로 입력'));
    expect(byAge.top, greaterThan(byDate.bottom), reason: '낱자에서 꺾이지 않게');
    expect(tester.takeException(), isNull);
  });

  group('나이로 입력한 분 보여주기', () {
    Future<void> openProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1236, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [careProfilesProvider.overrideWith(_ByAgeProfiles.new)],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.profile,
        routes: [
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.profileEditBasic,
            builder: (context, state) => const ProfileBasicEditScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
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
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('프로필 설정은 지어낸 날짜 대신 나이를 보여준다', (tester) async {
      await openProfile(tester);

      expect(find.text('82세(나이로 입력)'), findsOneWidget);
      final made = birthDateForAge(82, DateTime.now());
      expect(
        find.text('${made.year}년 ${made.month}월 ${made.day}일'),
        findsNothing,
      );
    });

    testWidgets('기본 정보 수정은 나이 칸으로 열리고 고치지 않으면 저장을 막는다', (tester) async {
      await openProfile(tester);
      GoRouter.of(
        tester.element(find.byType(ProfileScreen)),
      ).push(AppRoutes.profileEditBasic);
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '82',
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '저장하기'),
      );
      expect(save.onPressed, isNull, reason: '고친 것이 없다');
    });
  });

  group('서버와 단말', () {
    Future<ProviderContainer> launch(
      FakeProfileServer server,
      FakeProfileBirthInputStore store,
    ) async {
      final container = ProviderContainer(
        overrides: [
          server.override,
          selectedProfileStoreProvider.overrideWithValue(
            FakeSelectedProfileStore(),
          ),
          profileRelationshipStoreProvider.overrideWithValue(
            FakeProfileRelationshipStore(),
          ),
          profileBirthInputStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      container.listen(careProfilesProvider, (_, _) {});
      container.read(sessionProvider.notifier).restore(_session());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return container;
    }

    test('나이로 입력하면 계산한 날짜만 보내고 표시는 단말에 둔다', () async {
      final server = FakeProfileServer();
      final store = FakeProfileBirthInputStore();
      final container = await launch(server, store);
      final controller = container.read(setupControllerProvider.notifier);

      controller.updateDraft(
        _base.copyWith(birthByAge: true).withAgeText('82'),
      );
      await controller.submitBasicInfo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final created = server.requests.singleWhere((r) => r.method == 'POST');
      final body = created.body as Map;
      expect(body['birthDate'], isoDate(birthDateForAge(82, DateTime.now())));
      expect(body.keys, isNot(contains('birthByAge')));
      expect(store.values['account-a'], {'server-1'});
    });

    test('다시 켜면 단말의 표시를 붙여 나이로 보여준다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(id: 'p1', setupStatus: 'completed'),
          FakeProfileServer.profile(id: 'p2', setupStatus: 'completed'),
        ],
      );
      final store = FakeProfileBirthInputStore()..values['account-a'] = {'p1'};
      final container = await launch(server, store);

      final entries = container.read(careProfilesProvider).entries;
      expect(entries.map((e) => e.basicInfo!.birthByAge), [true, false]);
    });

    test('지우면 표시도 지운다', () async {
      final server = FakeProfileServer(
        profiles: [
          FakeProfileServer.profile(id: 'p1', setupStatus: 'completed'),
        ],
      );
      final store = FakeProfileBirthInputStore()..values['account-a'] = {'p1'};
      final container = await launch(server, store);

      container.read(careProfilesProvider.notifier).remove('p1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(store.values['account-a'], isEmpty);
    });
  });

  group('서버 거절', () {
    test('기본 정보의 422 는 생년월일을 확인하라고 한다', () {
      const failure = ApiServerFailure(
        statusCode: 422,
        errorCode: 'INVALID_REQUEST',
      );
      expect(basicInfoFailureMessage(failure), startsWith('생년월일을 다시 확인해주세요'));
      expect(
        basicInfoFailureMessage(const ApiNetworkFailure()),
        profileFailureMessage(const ApiNetworkFailure()),
      );
    });

    testWidgets('기본 정보 저장이 422 로 거절되면 생년월일 안내를 보인다', (tester) async {
      tester.view.physicalSize = const Size(1236, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final server = FakeProfileServer()
        ..failures['POST /api/v1/profiles'] = (
          status: 422,
          errorCode: 'INVALID_REQUEST',
        );
      final container = ProviderContainer(overrides: [server.override]);
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).restore(_session());
      container
          .read(setupControllerProvider.notifier)
          .updateDraft(
            _base.copyWith(birthYear: 1943, birthMonth: 3, birthDay: 12),
          );

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

      expect(find.textContaining('생년월일을 다시 확인해주세요'), findsOneWidget);
      expect(find.textContaining('잠시 뒤 다시 시도'), findsNothing);
      expect(find.text('기본 정보 입력'), findsOneWidget);
    });
  });
}
