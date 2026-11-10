// 녹음 중 표시([RecordingPulse])와 그것을 쓰는 E-2 녹음 화면을 확인한다.
//
// PM이 녹음 버튼을 누른 뒤 녹음이 시작됐는지 알 수 없었다(2026-11-10). 녹음하는
// 동안에만 마이크 원 둘레로 물결이 퍼지고, 멈추거나 움직임 줄이기가 켜져 있으면
// 움직이지 않는지 본다. 색과 크기 값은 고정하지 않는다(`app/README.md` 의 화면
// 테스트 기준). B-3 ~ B-6 음성 입력은 `life_fact_step_test.dart` 에서 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/widgets/recording_pulse.dart';

import 'fake_card_api.dart';
import 'fake_visit_recorder.dart';

/// 물결을 그리는 자리에서 그린 것을 모두 적는다. 마이크 원은 따로 그리므로
/// 여기 섞이지 않는다.
List<String> _painted(WidgetTester tester) {
  final layer = tester.renderObject(
    find.descendant(
      of: find.byType(RecordingPulse),
      matching: find.byType(CustomPaint),
    ),
  );
  final calls = <String>[];
  expect(
    layer,
    paints..everything((method, arguments) {
      calls.add('$method $arguments');
      return true;
    }),
  );
  return calls;
}

/// 물결이 그린 것이 없다.
void _expectNothingPainted(WidgetTester tester) {
  expect(
    tester.renderObject(
      find.descendant(
        of: find.byType(RecordingPulse),
        matching: find.byType(CustomPaint),
      ),
    ),
    paintsNothing,
  );
}

bool _active(WidgetTester tester) =>
    tester.widget<RecordingPulse>(find.byType(RecordingPulse)).active;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test_config.dart 가 끈 움직임을 이 파일에서는 켠다.
  setUp(() => RecordingPulse.motion = true);
  tearDown(() => RecordingPulse.motion = false);

  group('물결', () {
    const circle = 112.0;

    Future<void> pumpPulse(
      WidgetTester tester, {
      required bool active,
      bool reduceMotion = false,
    }) {
      return tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(disableAnimations: reduceMotion),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: RecordingPulse(
                  active: active,
                  child: const SizedBox.square(dimension: circle),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('녹음하는 동안 물결이 멈추지 않고 퍼진다', (tester) async {
      await pumpPulse(tester, active: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isTrue);
      final before = _painted(tester);
      expect(before, isNotEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      final after = _painted(tester);
      expect(after, isNotEmpty);
      expect(after, isNot(before), reason: '같은 모양에 머물지 않는다');

      // 몇 바퀴를 지나도 멈추지 않는다.
      await tester.pump(const Duration(seconds: 10));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('녹음하지 않으면 그리지도 움직이지도 않는다', (tester) async {
      await pumpPulse(tester, active: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.hasRunningAnimations, isFalse);
      _expectNothingPainted(tester);
    });

    testWidgets('멈추면 물결이 사라지고 이어서 녹음하면 다시 퍼진다', (tester) async {
      await pumpPulse(tester, active: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);

      await pumpPulse(tester, active: false);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      _expectNothingPainted(tester);

      await pumpPulse(tester, active: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      expect(_painted(tester), isNotEmpty);
    });

    testWidgets('움직임 줄이기가 켜져 있으면 움직이지 않고 고정된 고리로 알린다', (tester) async {
      await pumpPulse(tester, active: true, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isFalse);
      final before = _painted(tester);
      expect(before, isNotEmpty, reason: '움직이지 않아도 녹음 중임은 보인다');

      await tester.pump(const Duration(seconds: 2));
      expect(_painted(tester), before);

      // 녹음하지 않을 때는 고리도 없다.
      await pumpPulse(tester, active: false, reduceMotion: true);
      await tester.pump();
      _expectNothingPainted(tester);
    });

    testWidgets('물결은 자리를 차지하지 않아 아래 내용이 오르내리지 않는다', (tester) async {
      await pumpPulse(tester, active: false);
      final idle = tester.getSize(find.byType(RecordingPulse));

      await pumpPulse(tester, active: true);
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.getSize(find.byType(RecordingPulse)), idle);
      expect(idle, const Size.square(circle));
    });
  });

  group('E-2 녹음 화면', () {
    /// 카드 한 장을 고르고 녹음을 시작한 녹음 화면을 띄운다.
    ///
    /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
    Future<ProviderContainer> openRecording(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      tester.view.physicalSize = const Size(1236, 2751);
      tester.view.devicePixelRatio = 3;
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
        container
            .read(cardsControllerProvider.notifier)
            .toggleSelected(cards.cards.first.cardId);
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
      return container;
    }

    /// 누른 자리의 잉크 번짐이 끝날 때까지 흘린다. 그 움직임과 물결을 섞지
    /// 않으려는 것이다.
    Future<void> afterTap(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    /// 시간 표시 타이머가 남지 않게 화면을 내린다.
    Future<void> leave(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('녹음하는 동안만 마이크 원 둘레에 물결이 퍼진다', (tester) async {
      final container = await openRecording(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(_active(tester), isTrue);
      expect(tester.hasRunningAnimations, isTrue);

      await tester.tap(find.byIcon(Icons.pause));
      await afterTap(tester);
      expect(find.text('잠시 멈췄어요'), findsOneWidget);
      expect(_active(tester), isFalse);
      expect(tester.hasRunningAnimations, isFalse, reason: '멈춘 동안은 움직이지 않는다');

      await tester.tap(find.byIcon(Icons.play_arrow));
      await afterTap(tester);
      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(_active(tester), isTrue);
      expect(tester.hasRunningAnimations, isTrue);

      await leave(tester, container);
    });

    testWidgets('끝내기 확인 창을 보는 동안에는 물결이 멈춘다', (tester) async {
      final container = await openRecording(tester);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_active(tester), isFalse, reason: '창을 보는 동안 녹음은 멈춰 있다');

      await tester.tap(find.text('이어서 녹음').last);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_active(tester), isTrue);

      await leave(tester, container);
    });

    testWidgets('움직임 줄이기가 켜져 있으면 녹음 중에도 움직이지 않는다', (tester) async {
      final container = await openRecording(tester, reduceMotion: true);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(_active(tester), isTrue, reason: '고정된 고리로 녹음 중임을 알린다');
      expect(tester.hasRunningAnimations, isFalse);

      await leave(tester, container);
    });
  });
}
