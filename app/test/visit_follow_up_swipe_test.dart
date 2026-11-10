// E-3, E-4 면회 중 대화 카드 시트에서 꼬리 질문을 옆으로 밀어 넘기는 동작을
// 확인한다.
//
// 꼬리 질문은 왼쪽으로 밀려 나가고 오른쪽에서 들어와 밀 수 있어 보이는데, 눌러야만
// 넘어가 PM 이 밀어 봤을 때 아무 일도 없었다(2026-11-10).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 [cardCount] 장을 고르고 녹음을 시작한 뒤 대화 카드 시트를 꺼낸다.
  ///
  /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    int cardCount = 2,
    bool reduceMotion = false,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = const Size(412, 917) * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ...withMockCards,
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
      await container.read(visitControllerProvider.notifier).startRecording();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: const RecordScreen(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    await tester.tap(find.text('위로 올려서 대화 카드 꺼내기'));
    await settle(tester);
    expect(find.text('대화 카드 추가'), findsOneWidget);
    return container;
  }

  VisitState visitOf(ProviderContainer container) =>
      container.read(visitControllerProvider).value!;

  List<String> followUpsOf(ProviderContainer container) =>
      visitOf(container).currentCard!.followUpQuestions;

  group('꼬리 질문을 옆으로 밀기', () {
    testWidgets('왼쪽으로 밀면 다음 질문, 오른쪽으로 밀면 앞 질문이 보인다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);
      expect(questions, hasLength(3));

      await tester.drag(find.text(questions[0]), const Offset(-200, 0));
      await settle(tester);
      expect(find.text(questions[1]), findsOneWidget);
      expect(find.text(questions[0]), findsNothing);

      await tester.drag(find.text(questions[1]), const Offset(200, 0));
      await settle(tester);
      expect(find.text(questions[0]), findsOneWidget);
      expect(find.text(questions[1]), findsNothing);

      // 누를 때 마지막 다음이 첫 질문인 것처럼 첫 질문의 앞은 마지막 질문이다.
      await tester.drag(find.text(questions[0]), const Offset(200, 0));
      await settle(tester);
      expect(find.text(questions[2]), findsOneWidget);

      await tester.drag(find.text(questions[2]), const Offset(-200, 0));
      await settle(tester);
      expect(find.text(questions[0]), findsOneWidget);
    });

    testWidgets('짧아도 빠르게 그으면 넘어간다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);

      // 넘기는 거리(48)보다 짧은 40을 0.032초에 긋는다(초당 약 1250).
      // tester.fling 은 움직임을 50번으로 쪼개 속도 추적기에 남는 거리가
      // 너무 짧아져 그은 것으로 잡히지 않는다.
      Future<void> flick(Finder target, double step) async {
        final gesture = await tester.createGesture();
        await gesture.down(tester.getCenter(target));
        for (var i = 1; i <= 4; i++) {
          await gesture.moveBy(
            Offset(step, 0),
            timeStamp: Duration(milliseconds: 8 * i),
          );
        }
        await gesture.up(timeStamp: const Duration(milliseconds: 32));
      }

      await flick(find.text(questions[0]), -10);
      await settle(tester);
      expect(find.text(questions[1]), findsOneWidget);

      await flick(find.text(questions[1]), 10);
      await settle(tester);
      expect(find.text(questions[0]), findsOneWidget);
    });

    testWidgets('옆으로 조금 끌다 놓으면 넘어가지 않는다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);

      await tester.drag(find.text(questions[0]), const Offset(-40, 0));
      await settle(tester);
      await tester.drag(find.text(questions[0]), const Offset(40, 0));
      await settle(tester);

      expect(find.text(questions[0]), findsOneWidget);
      expect(visitOf(container).followUpIndex, 0);
    });

    testWidgets('위아래로 끌면 질문은 그대로이고 시트가 움직인다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);

      // 조금 끌어내렸다 놓으면 시트가 다시 올라온다.
      await tester.drag(find.text(questions[0]), const Offset(0, 120));
      await settle(tester);
      // 옆으로 조금 비껴가도 위아래로 크게 움직이면 넘기지 않는다.
      await tester.drag(find.text(questions[0]), const Offset(30, -150));
      await settle(tester);
      await tester.drag(find.text(questions[0]), const Offset(-30, 150));
      await settle(tester);

      expect(find.text(questions[0]), findsOneWidget);
      expect(find.text('대화 카드 추가'), findsOneWidget);
      expect(visitOf(container).followUpIndex, 0);

      // 꼬리 질문 칸에서 아래로 그어도 시트를 내려 닫을 수 있다.
      await tester.fling(find.text(questions[0]), const Offset(0, 300), 1500);
      await settle(tester);
      expect(find.text('대화 카드 추가'), findsNothing);
      expect(find.text('위로 올려서 대화 카드 꺼내기'), findsOneWidget);
      expect(visitOf(container).followUpIndex, 0);
    });

    testWidgets('눌러도 그대로 다음 질문으로 넘어간다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);

      await tester.tap(find.text(questions[0]));
      await settle(tester);
      expect(find.text(questions[1]), findsOneWidget);
      expect(find.text(questions[0]), findsNothing);
    });

    testWidgets('미는 쪽으로 질문이 밀려 나가고 반대쪽에서 들어온다', (tester) async {
      final container = await openSheet(tester);
      final questions = followUpsOf(container);
      final rest = tester.getCenter(find.text(questions[0])).dx;

      // 왼쪽으로 밀면 앞 질문은 왼쪽으로 나가고 다음 질문은 오른쪽에서 온다.
      await tester.drag(find.text(questions[0]), const Offset(-200, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getCenter(find.text(questions[0])).dx, lessThan(rest - 10));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getCenter(find.text(questions[1])).dx,
        greaterThan(rest + 10),
      );
      await settle(tester);
      expect(tester.getCenter(find.text(questions[1])).dx, closeTo(rest, 1));

      // 오른쪽으로 밀면 거꾸로다.
      await tester.drag(find.text(questions[1]), const Offset(200, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.getCenter(find.text(questions[1])).dx,
        greaterThan(rest + 10),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getCenter(find.text(questions[0])).dx, lessThan(rest - 10));
      await settle(tester);
      expect(tester.getCenter(find.text(questions[0])).dx, closeTo(rest, 1));
    });

    testWidgets('움직임 줄이기를 켜면 밀어도 바로 바뀐다', (tester) async {
      final container = await openSheet(tester, reduceMotion: true);
      final questions = followUpsOf(container);

      await tester.drag(find.text(questions[0]), const Offset(200, 0));
      await tester.pump();
      await tester.pump();
      expect(find.text(questions[2]), findsOneWidget);
      expect(find.text(questions[0]), findsNothing);
    });

    testWidgets('밀어서 넘긴 뒤에도 카드 버튼과 카드 막대가 그대로 움직인다', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await openSheet(tester);
      final first = followUpsOf(container);

      await tester.drag(find.text(first[0]), const Offset(-200, 0));
      await settle(tester);
      expect(find.text(first[1]), findsOneWidget);

      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(visitOf(container).currentIndex, 1);
      final second = followUpsOf(container);
      expect(find.text(second[0]), findsOneWidget, reason: '새 카드는 첫 질문부터');

      await tester.drag(find.text(second[0]), const Offset(200, 0));
      await settle(tester);
      expect(find.text(second[2]), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('1번 카드'));
      await settle(tester);
      expect(visitOf(container).currentIndex, 0);
      expect(find.text(first[0]), findsOneWidget);

      await tester.tap(find.text('이전'));
      await settle(tester);
      expect(visitOf(container).currentIndex, 1);
      handle.dispose();
    });

    testWidgets('화면 낭독기는 동작 메뉴로 다음, 이전 질문을 고른다', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await openSheet(tester);
      final questions = followUpsOf(container);
      const next = CustomSemanticsAction(label: '다음 꼬리 질문');
      const previous = CustomSemanticsAction(label: '이전 꼬리 질문');

      FinderBase<SemanticsNode> followUpNode() =>
          find.semantics.byLabel(RegExp('다음 꼬리 질문 보기'));

      expect(
        tester.getSemantics(find.text(questions[0])),
        isSemantics(hasTapAction: true, customActions: [next, previous]),
        reason: '두 번 누르면 다음 질문, 옆으로 미는 손짓 대신 동작 메뉴로 앞뒤를 고른다',
      );

      tester.semantics.customAction(followUpNode(), previous);
      await settle(tester);
      expect(find.text(questions[2]), findsOneWidget);

      tester.semantics.customAction(followUpNode(), next);
      await settle(tester);
      expect(find.text(questions[0]), findsOneWidget);

      tester.semantics.tap(followUpNode());
      await settle(tester);
      expect(find.text(questions[1]), findsOneWidget);
      handle.dispose();
    });
  });
}

/// 시트가 올라오거나 꼬리 질문이 넘어갈 시간을 준다.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
