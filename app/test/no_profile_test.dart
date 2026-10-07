// 등록한 어르신이 없을 때를 확인한다.
//
// 서버를 쓰면 회원가입에서 첫 분을 반드시 등록하므로, 어르신이 없는 경우는
// 보호자가 마지막 분을 지운 때다. 지금은 로그인만 하고 들어와도 이 상태다.
// 계정은 그대로 쓸 수 있고, 어르신이 있어야 하는 기능은 등록부터 안내한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';

import 'sample_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('어르신 목록', () {
    ProviderContainer makeContainer({bool withProfile = false}) {
      final container = ProviderContainer(
        overrides: [if (withProfile) withSampleProfile],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('처음에는 등록한 분이 없다', () async {
      final container = makeContainer();

      expect(container.read(careProfilesProvider).entries, isEmpty);
      expect(container.read(careProfilesProvider).hasSelected, isFalse);
      expect(await container.read(profileProvider.future), isNull);
    });

    test('마지막 분도 지울 수 있다', () async {
      final container = makeContainer(withProfile: true);

      container.read(careProfilesProvider.notifier).remove(sampleProfileId);

      expect(container.read(careProfilesProvider).entries, isEmpty);
      expect(container.read(careProfilesProvider).selected, isNull);
      expect(await container.read(profileProvider.future), isNull);
    });

    test('입력하다 멈춘 분은 고른 분으로 치지 않는다', () {
      final container = makeContainer();
      final profiles = container.read(careProfilesProvider.notifier);

      final id = profiles.beginAdding()!;
      expect(container.read(careProfilesProvider).hasSelected, isFalse);

      profiles.completeAdding(id, sampleBasicInfo);
      expect(container.read(careProfilesProvider).selected?.id, id);
    });

    test('고른 분이 없으면 리포트 알림을 만들지 않는다', () {
      final container = makeContainer();
      final notice = container.read(reportNoticeProvider.notifier);

      notice.arrive();
      notice.startGenerating();

      expect(container.read(reportNoticeProvider), isNull);
    });
  });

  /// [location] 에서 앱을 띄운다.
  Future<void> openAt(
    WidgetTester tester,
    String location, {
    bool withProfile = false,
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = buildRouter();
    router.go(location);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [if (withProfile) withSampleProfile],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  /// 누르고 화면이 자리 잡을 때까지 기다린다.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  const registerTitle = '어르신을 먼저 등록해주세요';

  group('홈', () {
    testWidgets('이름 없이 묻고 오른쪽 위에 어르신 등록을 둔다', (tester) async {
      await openAt(tester, AppRoutes.home);

      expect(find.text('오늘은 무슨 주제로\n대화를 나눠볼까요?'), findsOneWidget);
      expect(find.text('어르신 등록'), findsOneWidget);
      expect(find.byTooltip('다음 분 보기'), findsNothing);
    });

    testWidgets('어르신 등록을 누르면 함께하는 소중한 분 화면으로 간다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tapAndSettle(tester, find.text('어르신 등록'));

      expect(find.text('함께하는 소중한 분'), findsOneWidget);
      expect(find.text('소중한 분 더하기'), findsNWidgets(3));
      expect(find.text('소중한 분 정보 지우기'), findsNothing, reason: '지울 분이 없다');
    });

    final blocked = <String, Finder Function()>{
      '오늘의 대화카드 받기': () => find.text('오늘의 대화카드 받기'),
      '알림': () => find.byTooltip('알림'),
      '일대기': () => find.text('일대기'),
    };
    for (final entry in blocked.entries) {
      testWidgets('${entry.key}을 누르면 등록부터 안내한다', (tester) async {
        await openAt(tester, AppRoutes.home);

        await tapAndSettle(tester, entry.value());

        expect(find.text(registerTitle), findsOneWidget);
        expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
      });
    }

    testWidgets('안내창에서 닫기를 누르면 홈에 남는다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));
      await tapAndSettle(tester, find.text('닫기'));

      expect(find.text(registerTitle), findsNothing);
      expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
    });

    testWidgets('안내창에서 등록하러 가기를 누르면 소중한 분 화면으로 간다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tapAndSettle(tester, find.text('오늘의 대화카드 받기'));
      await tapAndSettle(tester, find.text('등록하러 가기'));

      expect(find.text('함께하는 소중한 분'), findsOneWidget);
    });
  });

  group('마이페이지', () {
    testWidgets('리포트 기록을 누르면 등록부터 안내한다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tapAndSettle(tester, find.text('마이페이지'));
      await tapAndSettle(tester, find.text('리포트 기록'));

      expect(find.text(registerTitle), findsOneWidget);
      expect(find.text('오늘의 대화카드 받기'), findsOneWidget);
    });

    testWidgets('프로필 설정에는 계정 항목만 보인다', (tester) async {
      await openAt(tester, AppRoutes.home);

      await tapAndSettle(tester, find.text('마이페이지'));
      await tapAndSettle(tester, find.text('프로필 설정'));

      expect(find.text('계정 약관 동의'), findsOneWidget);
      for (final hidden in ['기본 정보', '세부 정보', '갤러리', '내용 추가하기']) {
        expect(find.text(hidden), findsNothing, reason: '$hidden 은 어르신 항목이다');
      }
      for (final shown in ['계정 약관 동의', '저장하기', '로그아웃', '회원탈퇴']) {
        expect(find.text(shown), findsOneWidget, reason: '$shown 은 계정 항목이다');
      }
    });
  });

  group('마지막 분 지우기', () {
    testWidgets('같은 확인창으로 지우고 빈 슬롯만 남는다', (tester) async {
      await openAt(tester, AppRoutes.profileSwitch, withProfile: true);

      await tapAndSettle(tester, find.text('소중한 분 정보 지우기'));
      await tapAndSettle(tester, find.text('김새록 어르신'));

      expect(find.text('김새록 어르신의 정보를 지울까요?'), findsOneWidget);
      expect(find.textContaining('회원 탈퇴'), findsNothing);

      await tapAndSettle(tester, find.text('지우기'));

      expect(find.text('함께하는 소중한 분'), findsOneWidget);
      expect(find.text('소중한 분 더하기'), findsNWidgets(3));
      expect(find.text('김새록 어르신'), findsNothing);
    });
  });

  group('주소로 바로 들어오기', () {
    const gated = {
      AppRoutes.cards: '대화 카드',
      AppRoutes.visitRecord: '녹음',
      AppRoutes.reports: '리포트 기록',
      AppRoutes.notifications: '알림',
    };
    for (final entry in gated.entries) {
      testWidgets('${entry.value} 화면 대신 등록 안내를 보여준다', (tester) async {
        await openAt(tester, entry.key);

        expect(find.text('함께하는 소중한 분을 등록한 뒤\n이용할 수 있어요.'), findsOneWidget);
        expect(find.text('등록하러 가기'), findsOneWidget);
      });
    }
  });
}
