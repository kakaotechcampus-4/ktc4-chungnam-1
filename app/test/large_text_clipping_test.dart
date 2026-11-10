// 시스템 글자를 크게 키워도 버튼과 줄이 글자를 자르지 않는지 확인한다.
//
// 2026-11-10 UX 점검 12번: 높이를 56으로 못 박은 주 버튼과 줄바꿈 없는 줄에서
// 글자가 잘렸고, 360x640 홈은 작은 스크롤 창 둘로 갈렸다. 값은 모두 합성이다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/home/home_screen.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/report/report_screen.dart';
import 'package:saerok/widgets/app_buttons.dart';

import 'fake_card_api.dart';
import 'sample_profile.dart';

void _useScreen(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 글이 필요한 높이를 다 받았고 줄여 그려지지도 않았는지 본다.
void _expectWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(needed - 0.5),
    reason: '$text 의 아래 줄이 잘리지 않는다',
  );
  expect(
    tester.getRect(finder).height,
    moreOrLessEquals(paragraph.size.height, epsilon: 0.5),
    reason: '$text 를 줄여 그리지 않는다',
  );
}

/// 홈 본문(상단바 아래)의 세로 스크롤 창.
Finder _homeScrollables() => find.descendant(
  of: find.byType(HomeScreen),
  matching: find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  ),
);

class _PhotoChoiceApi extends FakeCardApi implements PhotoPreparationApi {
  @override
  Future<CardGenerationSnapshot> snapshot(String profileId) async =>
      CardGenerationSnapshot(
        CardGenerationStatus.running,
        CardPhotoPreparation.fromJson(const {
          'setId': 'set-1',
          'state': 'choice',
          'total': 5,
          'completed': 3,
          'failed': 2,
          'pending': 0,
          'reason': 'consentRequired',
        }),
      );

  @override
  Future<CardGenerationSnapshot> resolvePhotos(
    String profileId,
    String setId,
    String action,
  ) async => const CardGenerationSnapshot(CardGenerationStatus.ready, null);
}

Future<void> _openRoute(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  final router = buildRouter()..go(location);
  addTearDown(router.dispose);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await container.read(serverProfileIdProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('공통 버튼', () {
    Future<void> pumpButton(WidgetTester tester, Widget button) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.screen),
              child: Column(children: [button]),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    const long = '대화 카드를 만들고 있어요';

    testWidgets('주 버튼은 글자를 키우면 줄을 바꾸고 그만큼 높아진다', (tester) async {
      _useScreen(tester, const Size(360, 640), 2);
      await pumpButton(
        tester,
        const PrimaryButton(
          label: long,
          loading: true,
          color: HomeColors.accent,
          loadingColor: HomeColors.accentLoading,
          onPressed: null,
        ),
      );

      expect(tester.takeException(), isNull);
      _expectWhole(tester, long);
      final button = tester.getRect(find.byType(FilledButton));
      final text = tester.getRect(find.text(long));
      expect(button.top, lessThanOrEqualTo(text.top));
      expect(button.bottom, greaterThanOrEqualTo(text.bottom));
    });

    testWidgets('아이콘이 있는 보조 버튼은 글자를 줄이지 않고 줄을 바꾼다', (tester) async {
      _useScreen(tester, const Size(360, 640), 2);
      await pumpButton(
        tester,
        SecondaryButton(
          label: '녹음 파일 공유하기',
          icon: Icons.share_outlined,
          onPressed: () {},
        ),
      );

      expect(tester.takeException(), isNull);
      _expectWhole(tester, '녹음 파일 공유하기');
      final button = tester.getRect(find.byType(OutlinedButton));
      final text = tester.getRect(find.text('녹음 파일 공유하기'));
      expect(button.top, lessThanOrEqualTo(text.top));
      expect(button.bottom, greaterThanOrEqualTo(text.bottom));
    });

    // 모양 값이 아니라 하한만 본다(`app/README.md` 의 화면 테스트 원칙).
    testWidgets('기본 글자에서도 누르는 높이는 56 이상이다', (tester) async {
      _useScreen(tester, const Size(412, 917), 1);
      await pumpButton(
        tester,
        Column(
          children: [
            PrimaryButton(label: '대화 시작하기', onPressed: () {}),
            SecondaryButton(
              label: '공유하기',
              icon: Icons.share_outlined,
              onPressed: () {},
            ),
          ],
        ),
      );

      expect(
        tester.getSize(find.byType(PrimaryButton)).height,
        greaterThanOrEqualTo(AppSizes.control),
      );
      expect(
        tester.getSize(find.byType(SecondaryButton)).height,
        greaterThanOrEqualTo(AppSizes.control),
      );
    });
  });

  testWidgets('카드 고르기의 요약 줄은 넘치면 다음 줄로 내린다', (tester) async {
    _useScreen(tester, const Size(360, 640), 1.3);
    final container = ProviderContainer(
      overrides: [withSampleProfile, ...withMockCards],
    );
    addTearDown(container.dispose);
    await _openRoute(tester, container, AppRoutes.cards);

    expect(tester.takeException(), isNull);
    expect(find.text('아직 고르지 않았어요'), findsOneWidget);
    _expectWhole(tester, '최대 9개까지');
    final limit = tester.getRect(find.text('최대 9개까지'));
    expect(limit.right, lessThanOrEqualTo(360 - AppSpacing.screen + 0.5));
  });

  testWidgets('답하는 방법 버튼은 글자를 키워도 넘치지 않는다', (tester) async {
    _useScreen(tester, const Size(390, 844), 2);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(setupControllerProvider.notifier)
        .restore(
          const SetupState(
            reachedIndex: 1,
            draft: SetupDraft(
              name: '김새록',
              gender: 'female',
              relationship: '어머니',
              birthYear: 1943,
              birthMonth: 3,
              birthDay: 12,
              stage: ConditionStage.mildCognitiveImpairment,
            ),
          ),
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
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    for (final label in ['말로 답하기', '글로 답하기']) {
      _expectWhole(tester, label);
      await tester.ensureVisible(find.text(label));
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
  });

  testWidgets('리포트의 쉬운 모드 버튼은 높아진 변경 사항 버튼과 겹치지 않는다', (tester) async {
    _useScreen(tester, const Size(360, 640), 2);
    final session = (await tester.runAsync(
      () => const MockRepository().loadVisitSession(),
    ))!;
    final container = ProviderContainer(
      overrides: [visitSessionProvider.overrideWith((ref) async => session)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ReportScreen(reportId: 'r-001'),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container.read(reportProposalsProvider('r-001').future),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectWhole(tester, '변경 사항 확인하기');
    final easy = tester.getRect(
      find
          .ancestor(of: find.text('쉬운 모드'), matching: find.byType(Container))
          .first,
    );
    final primary = tester.getRect(find.byType(FilledButton).last);
    expect(
      primary.height,
      greaterThan(AppSizes.control),
      reason: '확인하려는 경우는 변경 사항 버튼이 두 줄로 높아진 때다',
    );
    expect(
      easy.bottom,
      lessThanOrEqualTo(primary.top),
      reason: '변경 사항 버튼 위에 선다',
    );
  });

  group('홈', () {
    testWidgets('낮은 화면에서 글자를 키우면 본문과 버튼을 한 스크롤로 잇는다', (tester) async {
      _useScreen(tester, const Size(360, 640), 2);
      final container = ProviderContainer(
        overrides: [
          withSampleProfile,
          cardApiProvider.overrideWithValue(_PhotoChoiceApi()),
          cardPollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      addTearDown(container.dispose);
      await _openRoute(tester, container, AppRoutes.home);

      expect(tester.takeException(), isNull);
      expect(_homeScrollables(), findsOneWidget, reason: '작은 창 둘로 가르지 않는다');
      _expectWhole(tester, '오늘은 김새록 님과\n무슨 주제로 대화를 나눠볼까요?');

      // 끝까지 내리면 사진 선택의 두 버튼이 모두 보인다.
      await tester.drag(_homeScrollables(), const Offset(0, -5000));
      await tester.pump();
      expect(find.text('사진 분석 다시 시도').hitTestable(), findsOneWidget);
      expect(find.text('완료된 사진으로 카드 만들기').hitTestable(), findsOneWidget);
    });

    testWidgets('기준 화면에서는 스크롤 없이 그림을 줄여 버튼까지 담는다', (tester) async {
      _useScreen(tester, const Size(412, 917), 1);
      final container = ProviderContainer(
        overrides: [
          withSampleProfile,
          cardApiProvider.overrideWithValue(FakeCardApi()),
        ],
      );
      addTearDown(container.dispose);
      await _openRoute(tester, container, AppRoutes.home);

      expect(tester.takeException(), isNull);
      expect(find.text('오늘의 대화카드 받기').hitTestable(), findsOneWidget);
      for (final element in _homeScrollables().evaluate()) {
        final position = (element as StatefulElement).state as ScrollableState;
        expect(position.position.maxScrollExtent, 0, reason: '본문이 넘치지 않는다');
      }
    });
  });
}
