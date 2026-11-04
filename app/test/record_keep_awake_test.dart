// E-2 녹음 화면이 녹음하는 동안에만 화면을 켜 두는지 확인한다.
//
// 창 표시는 대역([FakeScreenAwakePlatform])이 받는다. 실기기에서 화면이 정말
// 꺼지지 않는지, 앱이 백그라운드로 내려간 뒤에도 녹음이 이어지는지는 이
// 테스트가 보지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_screen_awake.dart';
import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 한 장을 고른 회차를 만들고 녹음 화면을 띄운다. [start] 면 녹음을
  /// 시작한 뒤 띄운다.
  ///
  /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
  Future<(ProviderContainer, VisitController)> open(
    WidgetTester tester, {
    required FakeScreenAwakePlatform screen,
    FakeVisitRecorder? recorder,
    bool start = true,
  }) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(
          recorder ?? FakeVisitRecorder(),
        ),
        screen.asOverride,
        ...withMockCards,
      ],
    );
    addTearDown(container.dispose);

    late VisitController visit;
    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      final cards = await container.read(cardsControllerProvider.future);
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(cards.cards.first.cardId);

      await container.read(visitControllerProvider.future);
      visit = container.read(visitControllerProvider.notifier);
      if (start) await visit.startRecording();

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
    return (container, visit);
  }

  /// 화면을 다시 그리고 바뀐 녹음 상태가 대역에 닿게 한다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// 시간 표시 타이머가 남지 않게 녹음을 끝내고 화면을 내린다.
  Future<void> leave(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await settle(tester);
  }

  testWidgets('녹음 전 안내에서는 화면을 켜 두지 않는다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    await open(tester, screen: screen, start: false);

    expect(find.text('네, 좋아요'), findsOneWidget);
    expect(screen.calls, isEmpty);
  });

  testWidgets('녹음 중에는 켜 두고 잠시 멈추면 놓고 이어 가면 다시 켠다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final (container, _) = await open(tester, screen: screen);

    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(screen.calls, [true]);

    await tester.tap(find.byIcon(Icons.pause));
    await settle(tester);
    expect(find.text('잠시 멈췄어요'), findsOneWidget);
    expect(screen.calls, [true, false]);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(screen.calls, [true, false, true]);

    await leave(tester, container);
  });

  testWidgets('끝내기 확인 창에서는 놓고, 이어서 녹음을 고르면 다시 켠다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final (container, _) = await open(tester, screen: screen);

    await tester.tap(find.byIcon(Icons.stop));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(screen.calls, [true, false], reason: '창을 보는 동안 녹음은 멈춰 있다');

    // 창의 `이어서 녹음` 이다. 뒤 화면의 같은 이름 버튼은 녹음 중이라 없다.
    await tester.tap(find.text('이어서 녹음').last);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(screen.calls, [true, false, true]);

    await leave(tester, container);
  });

  testWidgets('녹음을 끝내면 놓는다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final (_, visit) = await open(tester, screen: screen);

    await visit.stopRecording(participantCount: 2);
    await settle(tester);

    expect(screen.calls, [true, false]);
    expect(screen.isOn, isFalse);
  });

  testWidgets('끝내기 없이 화면을 떠나도 놓는다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final recorder = FakeVisitRecorder();
    final (container, _) = await open(
      tester,
      screen: screen,
      recorder: recorder,
    );
    expect(screen.calls, [true]);

    await leave(tester, container);

    expect(screen.calls, [true, false]);
    expect(recorder.calls, contains('stop'));
  });

  testWidgets('녹음을 시작하지 못하면 켜지 않는다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final (container, _) = await open(
      tester,
      screen: screen,
      recorder: FakeVisitRecorder(permitted: false),
      start: false,
    );

    await tester.tap(find.text('네, 좋아요'));
    await settle(tester);

    expect(
      container.read(visitControllerProvider).value!.problem,
      VisitRecordingProblem.permissionDenied,
    );
    expect(screen.calls, isEmpty);
  });

  testWidgets('앱이 엔진에서 떨어지면 녹음 중이어도 끄고 돌아오면 다시 켠다', (tester) async {
    final screen = FakeScreenAwakePlatform();
    final (container, _) = await open(tester, screen: screen);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await settle(tester);
    expect(screen.calls, [true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(screen.calls, [true, false, true]);

    await leave(tester, container);
  });
}
