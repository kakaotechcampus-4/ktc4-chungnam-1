// 프로필 설정(MYPAGE)에서 어르신 정보를 보여주는 자리를 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/profile/profile_basic_edit_screen.dart';
import 'package:saerok/features/profile/profile_screen.dart';

import 'sample_profile.dart';

/// 세부 정보를 적어 둔 어르신 한 분을 등록한 상태다. 값은 모두 합성이다.
class _WithDetails extends CareProfilesNotifier {
  @override
  CareProfiles build() => const CareProfiles(
    entries: [
      CareProfileEntry(
        id: sampleProfileId,
        basicInfo: sampleBasicInfo,
        details: EnteredDetails(
          occupation: '재봉 일을 오래 하셨어요.',
          family: '자녀는 2남 1녀를 두셨어요.',
        ),
      ),
    ],
    selectedId: sampleProfileId,
  );
}

/// 어르신 한 분을 등록한 상태로 프로필 설정을 띄운다.
Future<ProviderContainer> _open(
  WidgetTester tester, {
  bool withDetails = false,
}) async {
  // 기준 화면 412 x 917 dp 를 길게 늘려 스크롤 없이 모든 항목을 본다.
  tester.view.physicalSize = const Size(1236, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      if (withDetails)
        careProfilesProvider.overrideWith(_WithDetails.new)
      else
        withSampleProfile,
    ],
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

  // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
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
  return container;
}

void main() {
  testWidgets('어르신 정보 칸이 보이고 내용 추가하기 버튼은 없다', (tester) async {
    await _open(tester);

    for (final shown in ['기본 정보', '세부 정보', '갤러리']) {
      expect(find.text(shown), findsOneWidget, reason: shown);
    }
    expect(
      find.text('내용 추가하기'),
      findsNothing,
      reason: '생애 정보 추가는 일대기에서 한다',
    );
  });

  group('세부 정보', () {
    testWidgets('입력한 항목만 이름과 함께 보여준다', (tester) async {
      await _open(tester, withDetails: true);

      expect(find.text('하시던 일'), findsOneWidget);
      expect(find.text('재봉 일을 오래 하셨어요.'), findsOneWidget);
      expect(find.text('가족'), findsOneWidget);
      expect(find.text('자녀는 2남 1녀를 두셨어요.'), findsOneWidget);
      expect(find.text('고향'), findsNothing, reason: '적지 않은 항목은 감춘다');
      expect(find.text('취미'), findsNothing);
    });

    testWidgets('하나도 적지 않았으면 비어 있다고 알린다', (tester) async {
      await _open(tester);

      expect(find.text('아직 담긴 이야기가 없어요.'), findsOneWidget);
    });
  });

  group('기본 정보 수정', () {
    Finder saveButton() => find.widgetWithText(FilledButton, '저장하기');

    bool enabled(WidgetTester tester) =>
        tester.widget<FilledButton>(saveButton()).onPressed != null;

    Future<void> openEdit(WidgetTester tester) async {
      await tester.tap(find.text('수정하기').first);
      await tester.pumpAndSettle();
    }

    testWidgets('수정하기를 누르면 지금 값이 채워진 채로 열린다', (tester) async {
      await _open(tester);
      await openEdit(tester);

      expect(find.text('기본 정보 수정'), findsOneWidget);
      expect(find.widgetWithText(TextField, sampleBasicInfo.name), findsOneWidget);
      expect(find.text('1943년'), findsOneWidget);
      expect(enabled(tester), isFalse, reason: '고치지 않았으면 저장할 것이 없다');
    });

    testWidgets('이름 옆 연필로도 열린다', (tester) async {
      await _open(tester);

      await tester.tap(find.byTooltip('이름 수정'));
      await tester.pumpAndSettle();

      expect(find.text('기본 정보 수정'), findsOneWidget);
    });

    testWidgets('고쳐 저장하면 프로필 설정에 바로 보이고 세부 정보는 그대로다', (tester) async {
      final container = await _open(tester, withDetails: true);
      await openEdit(tester);

      await tester.enterText(find.byType(TextField), '김새봄');
      await tester.pump();
      await tester.tap(find.text(ConditionStage.unknown.label));
      await tester.pump();
      expect(enabled(tester), isTrue);

      await tester.tap(saveButton());
      // 바뀐 어르신 정보로 프로필을 다시 만든다. 목 데이터를 읽으므로 화면을 몇 번
      // 그리며 실제 비동기 처리를 기다린다.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('기본 정보를 저장했어요.'), findsOneWidget);
      expect(find.text('김새봄 어르신'), findsOneWidget);
      expect(find.text(ConditionStage.unknown.label), findsOneWidget);

      final entry = container.read(careProfilesProvider).selected!;
      expect(entry.basicInfo!.name, '김새봄');
      expect(entry.basicInfo!.birthDate, sampleBasicInfo.birthDate);
      expect(entry.details.occupation, '재봉 일을 오래 하셨어요.');
    });

    testWidgets('이름을 지우거나 50자를 넘기면 저장할 수 없다', (tester) async {
      await _open(tester);
      await openEdit(tester);

      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(enabled(tester), isFalse, reason: '이름은 필수다');

      await tester.enterText(find.byType(TextField), '가' * 51);
      await tester.pump();
      expect(find.text('이름은 50자까지 적을 수 있어요.'), findsOneWidget);
      expect(enabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), '가' * 50);
      await tester.pump();
      expect(find.text('이름은 50자까지 적을 수 있어요.'), findsNothing);
      expect(enabled(tester), isTrue);
    });
  });
}
