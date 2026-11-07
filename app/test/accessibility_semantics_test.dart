// 화면 낭독기(TalkBack)가 읽을 의미 정보를 확인한다(#180, 접근성 보고서 6~14쪽).
//
// 핵심 흐름인 카드 고르기, 녹음, 소감, 리포트를 본다. 의미 트리만 확인하며
// 실제 TalkBack 낭독은 확인하지 않는다. 실기기와 에뮬레이터 확인은 따로 한다.
// 값은 모두 합성이다.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/app_locale.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/data/card_api.dart';
import 'package:saerok/data/mock_repository.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/providers.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/design/tokens.dart';
import 'package:saerok/features/cards/card_generation_controller.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart';
import 'package:saerok/features/home/my_page_menu.dart';
import 'package:saerok/features/profile_setup/basic_info_step.dart';
import 'package:saerok/features/profile_setup/setup_controller.dart';
import 'package:saerok/features/report/report_screen.dart';
import 'package:saerok/features/review/review_screen.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/widgets/app_surfaces.dart';
import 'package:saerok/widgets/app_text_field.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';
import 'fake_visit_recorder.dart';
import 'sample_profile.dart';

/// 기준 화면 412 x 917 dp 다(`app/README.md`).
void _useReferenceScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 2751);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// WCAG 2.x 의 대비. 불투명한 두 색만 다룬다.
double _contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 화면 낭독기가 지금 화면을 옮겨 다니는 순서대로 이름을 모은다.
List<String> _traversalLabels(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty) node.label,
];

/// 목 묶음을 미리 읽어 두고 그대로 돌려준다. asset 을 화면 안에서 읽으면 가짜
/// 시간에서 끝나지 않는다.
class _PreloadedCardApi extends FakeCardApi {
  _PreloadedCardApi(this.set);

  final CardSet set;

  @override
  Future<CardSet> current(String profileId) async => set;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('카드 고르기 (보고서 10쪽, 14쪽)', () {
    late CardSet mockSet;

    setUpAll(() async {
      mockSet = await const MockRepository().loadCardSet();
    });

    Future<void> openCards(WidgetTester tester) async {
      _useReferenceScreen(tester);
      final container = ProviderContainer(
        overrides: [
          withSampleProfile,
          serverProfileIdProvider.overrideWith((ref) async => 'server-1'),
          cardApiProvider.overrideWithValue(_PreloadedCardApi(mockSet)),
          cardPollIntervalProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.cards,
        routes: [
          GoRoute(
            path: AppRoutes.cards,
            builder: (context, state) => const CardsScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('고르기 표시는 카드 제목과 선택 여부를 읽고, 펼치기와 따로 있다', (tester) async {
      final handle = tester.ensureSemantics();
      await openCards(tester);
      final title = mockSet.cards.first.cardTitle;
      final toggle = find.bySemanticsLabel(cardSelectLabel(title));

      expect(toggle, findsOneWidget);
      expect(
        tester.getSemantics(toggle),
        matchesSemantics(
          label: cardSelectLabel(title),
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );

      // 카드 본문은 펼침 여부를 가진 버튼이다. 고르기 표시와 다른 항목이다.
      final body = tester.getSemantics(find.text(title));
      expect(
        body,
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );
      expect(body.label, isNot(contains('고르기')));

      // 화면 낭독기의 두 번 누르기로 고른다.
      tester.semantics.tap(find.semantics.byLabel(cardSelectLabel(title)));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(toggle), isSemantics(isChecked: true));
      expect(find.text('1개 선택함'), findsOneWidget);
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(isExpanded: false),
        reason: '고르기가 카드를 펼치지 않는다',
      );

      // 본문을 누르면 펼쳐지고 선택은 그대로다.
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(RegExp.escape(title))).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(isExpanded: true),
      );
      expect(tester.getSemantics(toggle), isSemantics(isChecked: true));
      handle.dispose();
    });

    testWidgets('카드 본문은 두 번 탭하면 질문을 펼치거나 접는다고 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openCards(tester);
      final title = mockSet.cards.first.cardTitle;
      String? hint() =>
          tester.getSemantics(find.text(title)).hintOverrides?.onTapHint;

      // Android 15 의 TalkBack 은 펼침 여부를 읽지 않아 두 번 탭 안내로 알린다.
      expect(hint(), '질문 펼치기');
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(RegExp.escape(title))).first,
      );
      await tester.pumpAndSettle();
      expect(hint(), '질문 접기');
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(isExpanded: true),
        reason: 'Android 16 이상을 위한 펼침 여부도 그대로 둔다',
      );
      handle.dispose();
    });

    testWidgets('고르기 표시의 누르는 자리는 48 x 48 이상이다', (tester) async {
      await openCards(tester);
      final size = tester.getSize(find.byType(SelectionToggle).first);

      expect(size.width, greaterThanOrEqualTo(AppSizes.minTouch));
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouch));
    });
  });

  group('선택 표시 대비 (보고서 14쪽)', () {
    testWidgets('고르지 않은 빈 원의 테두리는 흰 면과 3:1 이상이다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: SelectionMark(selected: false))),
      );
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(SelectionMark),
          matching: find.byType(Container),
        ),
      );
      final border = (box.decoration! as BoxDecoration).border! as Border;

      expect(
        _contrast(border.top.color, AppColors.background),
        greaterThanOrEqualTo(3.0),
      );
      // 카드 테두리 같은 다른 선은 바꾸지 않는다.
      expect(AppColors.line, const Color(0xFFE0E0E0));
    });

    testWidgets('현재 상태의 빈 동그라미도 3:1 이상이고 선택 여부를 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      _useReferenceScreen(tester);
      var draft = const SetupDraft();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => BasicInfoStep(
                  draft: draft,
                  onChanged: (next) => setState(() => draft = next),
                ),
              ),
            ),
          ),
        ),
      );

      final stage = ConditionStage.values.first.label;
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .toList();
      expect(circles, hasLength(ConditionStage.values.length));
      for (final circle in circles) {
        expect(
          _contrast((circle.border! as Border).top.color, AppColors.background),
          greaterThanOrEqualTo(3.0),
        );
      }

      expect(
        tester.getSemantics(find.text(stage)),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      await tester.ensureVisible(find.text(stage));
      await tester.tap(find.text(stage));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(stage)),
        isSemantics(isChecked: true),
      );
      handle.dispose();
    });
  });

  group('녹음 (보고서 11쪽)', () {
    Future<void> openRecording(WidgetTester tester) async {
      _useReferenceScreen(tester);
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
          ...withMockCards,
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        final cards = await container.read(cardsControllerProvider.future);
        final selector = container.read(cardsControllerProvider.notifier);
        for (final card in cards.cards.take(2)) {
          selector.toggleSelected(card.cardId);
        }
        await container.read(visitControllerProvider.future);
        await container.read(visitControllerProvider.notifier).startRecording();

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

    testWidgets('멈춤 버튼은 이름을 한 번 읽고, 멈춘 뒤에는 이어서 녹음으로 바뀐다', (tester) async {
      final handle = tester.ensureSemantics();
      await openRecording(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('잠시 멈춤')),
        matchesSemantics(label: '잠시 멈춤', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('만남 끝내기')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      // 버튼 이름이 따로 한 번 더 읽히지 않는다.
      final labels = _traversalLabels(tester);
      expect(labels.where((l) => l.contains('잠시 멈춤')), hasLength(1));
      expect(
        tester.getSemantics(find.text('녹음 중이에요')),
        isSemantics(isLiveRegion: true),
      );

      await tester.runAsync(() async {
        tester.semantics.tap(find.semantics.byLabel('잠시 멈춤'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();

      expect(find.bySemanticsLabel('잠시 멈춤'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('이어서 녹음')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(find.text('잠시 멈췄어요'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('대화 카드 자리는 끌어올리지 않고 두 번 눌러 꺼내는 버튼으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openRecording(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('대화 카드 꺼내기')),
        matchesSemantics(
          label: '대화 카드 꺼내기',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        _traversalLabels(tester).any((l) => l.contains('위로 올려서')),
        isFalse,
      );

      // 순서: 상태, 시간, 멈춤, 끝내기, 카드 꺼내기.
      final labels = _traversalLabels(tester);
      expect(labels.indexOf('잠시 멈춤'), lessThan(labels.indexOf('만남 끝내기')));
      expect(labels.indexOf('만남 끝내기'), lessThan(labels.indexOf('대화 카드 꺼내기')));

      tester.semantics.tap(find.semantics.byLabel('대화 카드 꺼내기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 시트: 메인 질문, 꼬리 질문, 다음 카드 순서로 읽는다.
      final sheet = _traversalLabels(tester);
      final next = sheet.indexOf('다음 카드');
      final followUp = sheet.indexWhere((l) => l.contains('다음 꼬리 질문 보기'));
      final main = sheet.indexWhere((l) => l.startsWith('[ '));
      expect(next, isNot(-1));
      expect(main, lessThan(followUp));
      expect(followUp, lessThan(next));
      expect(
        tester.getSemantics(find.bySemanticsLabel('다음 카드')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(
        find.semantics.byLabel('대화 카드 닫기'),
        findsOne,
        reason: '시트 바깥 영역을 영어 Scrim 대신 한국어로 읽는다',
      );
      handle.dispose();
    });

    testWidgets('카드 시트를 닫은 뒤에도 두 번 눌러 다시 꺼낼 수 있다', (tester) async {
      final handle = tester.ensureSemantics();
      await openRecording(tester);

      for (var round = 1; round <= 3; round++) {
        tester.semantics.tap(find.semantics.byLabel('대화 카드 꺼내기'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.semantics.byLabel('다음 카드'),
          findsOne,
          reason: '$round 번째에도 시트가 열린다',
        );

        // 화면 낭독기 사용자가 닫는 방법인 바깥 영역 두 번 누르기로 닫는다.
        tester.semantics.tap(find.semantics.byLabel('대화 카드 닫기'));
        await tester.pump();
        // 닫기는 Navigator.maybePop 을 거쳐 한 프레임 늦게 시작한다.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.semantics.byLabel('다음 카드'), findsNothing);
      }
      handle.dispose();
    });
  });

  group('소감 (보고서 6쪽, 13쪽과 같은 문제)', () {
    const sessionId = 'session_demo_001';

    Future<void> openReview(WidgetTester tester) async {
      _useReferenceScreen(tester);
      final uploads = FakePendingUploads()
        ..saved[sessionId] = const PendingUpload(
          sessionId: sessionId,
          audioPath: '/synthetic/visit.wav',
          participantCount: 2,
        );
      final container = ProviderContainer(
        overrides: [
          withSampleProfile,
          ...mockCardsWith(visitApi: FakeVisitApi(), pendingUploads: uploads),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const ReviewScreen(sessionId: sessionId),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('필수 물음은 별표 대신 필수 응답을 읽고 제목으로 옮겨 다닌다', (tester) async {
      final handle = tester.ensureSemantics();
      await openReview(tester);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Q1. 오늘 나눈 대화는 어떠셨나요?, 필수 응답'),
        ),
        isSemantics(isHeader: true),
      );
      expect(
        find.bySemanticsLabel('Q4. 남기고 싶은 말이 있으신가요?'),
        findsOneWidget,
        reason: '필수가 아닌 물음은 필수라고 읽지 않는다',
      );
      expect(_traversalLabels(tester).any((l) => l.contains('*')), isFalse);
      handle.dispose();
    });

    testWidgets('점수와 반응은 뜻과 고른 상태를 함께 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openReview(tester);

      final four = find.bySemanticsLabel('4점, 좋았어요');
      expect(
        tester.getSemantics(four),
        isSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('4점, 좋았어요'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(four), isSemantics(isSelected: true));
      expect(
        tester.getSemantics(find.bySemanticsLabel('3점, 보통이었어요')),
        isSemantics(isSelected: false),
      );

      final calm = find.text(CareRecipientReaction.calm.label);
      expect(
        tester.getSemantics(calm),
        isSemantics(
          isButton: true,
          isInMutuallyExclusiveGroup: true,
          isSelected: false,
        ),
      );
      await tester.tap(calm);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(calm), isSemantics(isSelected: true));

      // Q3 카드별 평가의 칸도 고른 상태를 알린다.
      final notUsed = find.text('이 카드는 쓰지 않았어요').first;
      await tester.ensureVisible(notUsed);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(notUsed), isSemantics(isSelected: false));
      await tester.tap(notUsed);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(notUsed), isSemantics(isSelected: true));
      handle.dispose();
    });

    testWidgets('남기고 싶은 말 칸은 쓰기 전후 모두 이름을 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openReview(tester);
      final field = find.byKey(const Key('reviewFreeNote'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(field),
        isSemantics(isTextField: true, label: '남기고 싶은 말\n오늘 기억에 남는 순간을 적어보세요.'),
      );
      await tester.enterText(field, '합성 소감입니다');
      await tester.pumpAndSettle();
      final node = tester.getSemantics(field);
      expect(node.label, startsWith('남기고 싶은 말'));
      expect(node.value, '합성 소감입니다');
      handle.dispose();
    });
  });

  group('리포트', () {
    Future<void> openReport(WidgetTester tester) async {
      _useReferenceScreen(tester);
      await tester.runAsync(() async {
        final session = await const MockRepository().loadVisitSession();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              visitSessionProvider.overrideWith((ref) async => session),
            ],
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
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('쉬운 모드는 켜짐과 꺼짐을 알리는 버튼 하나로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openReport(tester);
      final easy = find.bySemanticsLabel('쉬운 모드');

      expect(
        tester.getSemantics(easy),
        matchesSemantics(
          label: '쉬운 모드',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('쉬운 모드'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(easy), isSemantics(isToggled: true));
      handle.dispose();
    });

    testWidgets('소제목은 제목으로 읽고 카드 반응은 제목과 한 항목으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await openReport(tester);

      for (final title in ['오늘의 만남', '대화 카드별 반응']) {
        expect(
          tester.getSemantics(find.text(title)),
          isSemantics(isHeader: true),
          reason: title,
        );
      }

      final summary = find.textContaining('한복을 주로 만드셨고');
      await tester.ensureVisible(summary);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(summary);
      expect(node.label, contains('한복을 주로 만드셨고'));
      expect(
        node.label.split('\n').length,
        greaterThan(1),
        reason: '카드 제목과 반응이 한 항목에 함께 있다',
      );
      handle.dispose();
    });
  });

  group('입력칸 이름 (보고서 6쪽, 13쪽)', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );

    testWidgets('필수 입력칸은 이름과 필수 입력을 칸에 붙여 한 번만 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          AppTextField(
            label: '이름',
            required: true,
            hintText: '합성 이름',
            controller: controller,
          ),
        ),
      );

      final field = find.byType(TextField);
      expect(
        tester.getSemantics(field),
        isSemantics(isTextField: true, label: '이름, 필수 입력\n합성 이름'),
      );
      expect(
        _traversalLabels(tester).where((l) => l.contains('이름')),
        hasLength(1),
        reason: '위의 이름표를 따로 다시 읽지 않는다',
      );

      await tester.enterText(field, '김새록');
      await tester.pump();
      expect(tester.getSemantics(field).label, startsWith('이름, 필수 입력'));
      handle.dispose();
    });

    testWidgets('따로 쓰는 이름표도 별표 대신 필수 입력을 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [FieldLabel('성별', required: true), FieldLabel('메모')],
          ),
        ),
      );

      expect(find.bySemanticsLabel('성별, 필수 입력'), findsOneWidget);
      expect(find.bySemanticsLabel('메모'), findsOneWidget);
      expect(_traversalLabels(tester).any((l) => l.contains('*')), isFalse);
      handle.dispose();
    });
  });

  group('앱 언어 (보고서 8쪽, 12쪽)', () {
    testWidgets('앱 언어는 한국어이고 메뉴 손잡이를 영어 Dismiss 로 읽지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            locale: appLocale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showMyPageMenu(context),
                    child: const Text('메뉴 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.text('메뉴 열기'));
      expect(Localizations.localeOf(context), const Locale('ko', 'KR'));

      await tester.tap(find.text('메뉴 열기'));
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Dismiss'), findsNothing);
      expect(
        find.semantics.byLabel(
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
        ),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('마이페이지 메뉴 (보고서 8쪽, 일부)', () {
    testWidgets('메뉴 바깥 영역은 영어 Scrim 대신 한국어로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      _useReferenceScreen(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showMyPageMenu(context),
                    child: const Text('메뉴 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('메뉴 열기'));
      await tester.pumpAndSettle();

      expect(find.text('프로필 설정'), findsOneWidget);
      expect(find.semantics.byLabel('메뉴 닫기'), findsOne);
      expect(find.semantics.byLabel('Scrim'), findsNothing);

      tester.semantics.tap(find.semantics.byLabel('메뉴 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('프로필 설정'), findsNothing);
      handle.dispose();
    });
  });
}
