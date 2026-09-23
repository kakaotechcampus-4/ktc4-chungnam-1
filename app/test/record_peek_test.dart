// E-2 녹음 화면 아래에 둔 대화 카드 자리를 확인한다.
//
// 리뷰 미팅 피드백으로 '대화 카드 살펴보기' 주 버튼을 없애고, 카드를 화면 아래에
// 내어 두고 끌어올려 꺼내는 자리로 바꿨다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 [cardCount] 장을 고르고 녹음이 시작된 상태로 화면을 띄운다.
  ///
  /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
  Future<void> openRecording(
    WidgetTester tester, {
    required int cardCount,
    Size logical = const Size(412, 917),
    EdgeInsets systemBars = EdgeInsets.zero,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = FakeViewPadding(
      top: systemBars.top * dpr,
      bottom: systemBars.bottom * dpr,
    );
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
      ],
    );
    addTearDown(container.dispose);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      final cards = await container.read(cardsControllerProvider.future);
      final selector = container.read(cardsControllerProvider.notifier);
      for (final card in cards.cards.take(cardCount)) {
        selector.toggleSelected(card.cardId);
      }

      await container.read(visitControllerProvider.future);
      final visit = container.read(visitControllerProvider.notifier);
      visit.confirmCareRecipient(confirmed: true);
      await visit.startRecording();

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

  /// 시트가 올라올 시간을 준다.
  Future<void> settleSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder fanCards() => find.descendant(
    of: find.byKey(const Key('cardPeekFan')),
    matching: find.byType(DecoratedBox),
  );

  group('대화 카드 자리', () {
    testWidgets('주 버튼 대신 끌어올리는 안내가 있다', (tester) async {
      await openRecording(tester, cardCount: 2);

      expect(find.text('위로 올려서 대화 카드 꺼내기'), findsOneWidget);
      expect(find.text('대화 카드 살펴보기'), findsNothing);
    });

    testWidgets('녹음 컨트롤은 그대로 있다', (tester) async {
      await openRecording(tester, cardCount: 2);

      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(find.text('잠시 멈춤'), findsOneWidget);
      expect(find.text('만남 끝내기'), findsOneWidget);
    });

    testWidgets('고른 카드가 두 장이어도 세 장으로 그린다', (tester) async {
      await openRecording(tester, cardCount: 2);

      expect(fanCards(), findsNWidgets(3));
    });

    testWidgets('고른 카드가 다섯 장이어도 세 장으로 그린다', (tester) async {
      await openRecording(tester, cardCount: 5);

      expect(
        fanCards(),
        findsNWidgets(3),
        reason: '장수를 세는 자리가 아니라 꺼낼 것이 있다고 알리는 자리다',
      );
    });
  });

  group('짧은 기기', () {
    /// 녹음 컨트롤이 스크롤 영역 안에 다 들어오는지 본다.
    ///
    /// 기준 화면 412 x 917 은 시스템 바를 뺀 크기가 아니다. 카드 자리 높이를 못
    /// 박았더니 실제 기기에서 `만남 끝내기` 가 스크롤 밖으로 밀려 잘렸다.
    Future<void> expectControlsVisible(WidgetTester tester) async {
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      final stop = tester.getRect(find.text('만남 끝내기'));

      expect(
        stop.bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: '컨트롤이 스크롤 밖으로 밀리면 안 된다',
      );
      expect(find.text('위로 올려서 대화 카드 꺼내기'), findsOneWidget);
    }

    testWidgets('상태바와 제스처 바가 있는 기기에서 컨트롤이 잘리지 않는다', (tester) async {
      await openRecording(
        tester,
        cardCount: 2,
        logical: const Size(411, 891),
        systemBars: const EdgeInsets.only(top: 24, bottom: 24),
      );

      await expectControlsVisible(tester);
    });

    testWidgets('내비게이션 바가 큰 작은 기기에서도 컨트롤이 잘리지 않는다', (tester) async {
      await openRecording(
        tester,
        cardCount: 2,
        logical: const Size(360, 780),
        systemBars: const EdgeInsets.only(top: 24, bottom: 48),
      );

      await expectControlsVisible(tester);
    });
  });

  group('꺼내는 방법', () {
    testWidgets('눌러서 꺼낸다', (tester) async {
      await openRecording(tester, cardCount: 2);

      await tester.tap(find.text('위로 올려서 대화 카드 꺼내기'));
      await settleSheet(tester);

      expect(find.text('대화 카드 추가'), findsOneWidget);
    });

    testWidgets('천천히 끌어올려도 꺼낸다', (tester) async {
      await openRecording(tester, cardCount: 2);

      // 속도를 남기지 않는 드래그다. 속도만 보면 이 손짓은 열리지 않는다.
      await tester.drag(find.text('위로 올려서 대화 카드 꺼내기'), const Offset(0, -80));
      await settleSheet(tester);

      expect(find.text('대화 카드 추가'), findsOneWidget);
    });

    testWidgets('위로 그어 올려도 꺼낸다', (tester) async {
      await openRecording(tester, cardCount: 2);

      await tester.fling(
        find.text('위로 올려서 대화 카드 꺼내기'),
        const Offset(0, -120),
        800,
      );
      await settleSheet(tester);

      expect(find.text('대화 카드 추가'), findsOneWidget);
    });

    testWidgets('아래로 그으면 꺼내지 않는다', (tester) async {
      await openRecording(tester, cardCount: 2);

      await tester.fling(
        find.text('위로 올려서 대화 카드 꺼내기'),
        const Offset(0, 120),
        800,
      );
      await settleSheet(tester);

      expect(find.text('대화 카드 추가'), findsNothing);
      expect(find.text('위로 올려서 대화 카드 꺼내기'), findsOneWidget);
    });
  });
}
