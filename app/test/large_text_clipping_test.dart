// 시스템 글자를 크게 키워도 버튼과 줄이 글자를 자르지 않는지 확인한다.
//
// 2026-11-10 UX 점검 12번: 높이를 56으로 못 박은 주 버튼과 줄바꿈 없는 줄에서
// 글자가 잘렸고, 360x640 홈은 작은 스크롤 창 둘로 갈렸다. 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
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
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/home/home_screen.dart';
import 'package:saerok/features/profile_setup/profile_setup_screen.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/profile_setup/speech_input.dart';
import 'package:saerok/features/report/report_screen.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/widgets/app_buttons.dart';

import 'fake_card_api.dart';
import 'fake_screen_awake.dart';
import 'fake_visit_recorder.dart';
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

/// 보내기가 늘 연결 문제로 실패하는 음성 입력. 다시 보낸 횟수를 센다.
class _UnsentSpeech implements SpeechInput {
  int resent = 0;

  @override
  Future<SpeechRecording> start({
    required String category,
    required int attempt,
  }) async => _UnsentRecording(this);
}

class _UnsentRecording implements SpeechRecording {
  _UnsentRecording(this._speech);

  final _UnsentSpeech _speech;

  @override
  Future<void> get limitReached => Completer<void>().future;

  @override
  Future<SpeechOutcome> finish() async => const SpeechFailed(canResend: true);

  @override
  Future<SpeechOutcome> resend() {
    _speech.resent += 1;
    return finish();
  }

  @override
  Future<void> cancel() async {}
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
      expect(find.text('준비된 설명으로 카드 만들기').hitTestable(), findsOneWidget);
      expect(find.text('설정에서 동의 켜기').hitTestable(), findsOneWidget);
      expect(find.text('사진 분석 다시 시도'), findsNothing);
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

  group('세부 정보 음성 입력', () {
    // 2026-11-10 리뷰: 보내지 못했을 때의 `재시도` 가 잡아 둔 높이보다 커져
    // 글자 2.0배에서 아래 `글로 답할게요` 에 가려 눌리지 않았다.
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
        final tag = '${size.width.toInt()}x${size.height.toInt()} 글자 $scale';
        testWidgets('보내지 못했을 때 재시도가 다 보이고 눌린다 $tag', (tester) async {
          _useScreen(tester, size, scale);
          tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
          final speech = _UnsentSpeech();
          final container = ProviderContainer(
            overrides: [
              speechInputProvider.overrideWith((ref) async => speech),
              FakeScreenAwakePlatform().asOverride,
            ],
          );
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

          await tester.ensureVisible(find.text('말로 답하기'));
          await tester.tap(find.text('말로 답하기'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byIcon(Icons.mic));
          await tester.tap(find.byIcon(Icons.mic));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('다 말했어요'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('다 말했어요'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final retry = find.text('재시도');
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          _expectWhole(tester, '말씀을 글로 옮기지 못했어요.');
          _expectWhole(tester, '재시도');

          // 버튼 전체가 스크롤 창 안에 있고, 아래 `글로 답할게요` 와 겹치지 않는다.
          final button = tester.getRect(
            find.ancestor(of: retry, matching: find.byType(OutlinedButton)),
          );
          final viewport = tester.getRect(find.byType(Scrollable).first);
          expect(button.top, greaterThanOrEqualTo(viewport.top - 0.5));
          expect(button.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
          final pill = find.text('글로 답할게요');
          if (pill.evaluate().isNotEmpty) {
            final pillButton = find.ancestor(
              of: pill,
              matching: find.byWidgetPredicate((w) => w is InkWell),
            );
            final pillRect = tester.getRect(pillButton.first);
            expect(
              button.bottom,
              lessThanOrEqualTo(pillRect.top + 0.5),
              reason: '재시도가 글로 답할게요 아래로 들어가지 않는다',
            );
          }

          // 버튼 아래쪽 끝을 눌러도 재시도가 받는다.
          await tester.tapAt(Offset(button.center.dx, button.bottom - 4));
          await tester.pumpAndSettle();
          expect(speech.resent, 1);
        });
      }
    }
  });

  group('면회 녹음', () {
    /// 카드를 하나 고르고 녹음을 시작한(또는 잠시 멈춘) 화면을 띄운다.
    Future<void> openRecording(
      WidgetTester tester,
      Size size,
      double scale, {
      bool paused = false,
    }) async {
      _useScreen(tester, size, scale);
      // 상태 표시줄 24 와 아래 손짓 막대 16.
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
          ...withMockCards,
        ],
      );
      addTearDown(container.dispose);
      // 앞 테스트가 가짜 시간 안에서 읽은 목 카드 묶음이 자산 캐시에 남으면
      // 실제 시간에서 기다릴 때 끝나지 않는다. 캐시를 비우고 새로 읽는다.
      rootBundle.clear();
      await tester.runAsync(() async {
        final cards = await container.read(cardsControllerProvider.future);
        container
            .read(cardsControllerProvider.notifier)
            .toggleSelected(cards.cards.first.cardId);
        await container.read(visitControllerProvider.future);
        final visit = container.read(visitControllerProvider.notifier);
        await visit.startRecording();
        if (paused) await visit.pauseRecording();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const RecordScreen(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }

    /// 줄을 바꿔 보여도 같은 이름인 컨트롤 이름 글.
    Finder label(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data?.replaceAll('\n', ' ') == text,
    );

    /// 이름이 잘리지 않고 스크롤하지 않아도 녹음 상태 창 안에 다 보인다.
    void expectLabelsFit(WidgetTester tester, List<String> names) {
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      for (final name in names) {
        final finder = label(name);
        expect(finder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.5,
          ),
          reason: '$name 의 아래 줄이 잘리지 않는다',
        );
        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(viewport.bottom + 0.5),
          reason: '$name 이 스크롤 창 아래에 잘리지 않는다',
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(
          rect.right,
          lessThanOrEqualTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
          ),
        );
      }
    }

    // 2026-11-10 리뷰: 녹음 상태 높이를 410 으로 못 박아 360x640 기본 글자와
    // 390x844 글자 1.3배에서 컨트롤 이름이 녹음 상태 창 아래에 잘렸다.
    for (final (screen, scale) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
      (Size(390, 844), 1.0),
      (Size(390, 844), 1.3),
    ]) {
      final tag = '${screen.width.toInt()}x${screen.height.toInt()} 글자 $scale';
      testWidgets('컨트롤 이름이 스크롤 없이 다 보인다 $tag', (tester) async {
        await openRecording(tester, screen, scale);
        expect(tester.takeException(), isNull);
        expectLabelsFit(tester, ['잠시 멈춤', '만남 끝내기']);
        for (final icon in [Icons.pause, Icons.stop]) {
          final rect = tester.getRect(
            find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)),
          );
          expect(rect.width, greaterThanOrEqualTo(AppSizes.minTouch));
          expect(rect.height, greaterThanOrEqualTo(AppSizes.minTouch));
        }

        await tester.tap(find.byIcon(Icons.pause));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectLabelsFit(tester, ['이어서 녹음', '만남 끝내기']);
      });
    }

    for (final screen in const [Size(360, 640), Size(390, 844)]) {
      final tag = '${screen.width.toInt()}x${screen.height.toInt()}';
      testWidgets('글자 2.0배에서는 이름을 띄어쓰기에서 나누고 넘치지 않는다 $tag', (
        tester,
      ) async {
        await openRecording(tester, screen, 2, paused: true);
        expect(tester.takeException(), isNull, reason: '옆이나 아래로 넘치지 않는다');
        for (final name in ['이어서 녹음', '만남 끝내기']) {
          expect(find.text(name.replaceFirst(' ', '\n')), findsOneWidget);
          await tester.ensureVisible(label(name));
          await tester.pump();
          expect(label(name).hitTestable(), findsOneWidget);
        }
        expect(find.text('위로 올려서 대화 카드 꺼내기'), findsOneWidget);
        _expectWhole(tester, '위로 올려서 대화 카드 꺼내기');
      });
    }
  });
}
