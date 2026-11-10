// 면회 중 대화 카드 시트 안의 녹음 표시를 확인한다.
//
// 시트가 화면의 5분의 4를 덮어 녹음 화면의 `녹음 중이에요` 와 시간이 가려졌다
// (2026-11-10 UX 점검 7번). 시트 손잡이 바로 아래에 녹음 상태와 시간을 두어,
// 시트를 내리지 않고도 녹음이 이어지는지 보이는지 본다. 색과 크기 값은 고정하지
// 않는다(`app/README.md` 의 화면 테스트 기준). 겹침은 접근성 하한(글자를 키워도
// 겹치거나 화면 밖으로 나가지 않음)으로만 본다.

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

/// 시트 안에서만 찾는다. 녹음 화면은 시트 아래에 그대로 있다.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

String _label(Duration elapsed) => VisitState(
  cards: const [],
  currentIndex: 0,
  followUpIndex: 0,
  started: true,
  recording: true,
  elapsed: elapsed,
).elapsedLabel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 두 장을 골라 녹음을 시작하고 대화 카드 시트를 꺼낸다.
  ///
  /// 처음 녹음은 asset 을 읽느라 실제 시간에서 시작하므로 1초 타이머도 실제
  /// 시간으로 돈다. 한 번 멈췄다 이어 가 타이머를 테스트의 가짜 시간으로 옮긴다.
  /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    Size logical = const Size(412, 917),
    double textScale = 1,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    // 화면을 먼저 내린 뒤에 버리도록 [leave] 가 버린다. 테스트가 중간에
    // 실패해 화면이 남은 채로 버리면 다음 테스트가 그 화면을 내릴 때 버린
    // 상태를 건드려 실패가 이어진다.
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ...withMockCards,
      ],
    );

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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const RecordScreen(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    final visit = container.read(visitControllerProvider.notifier);
    await visit.pauseRecording();
    await visit.startRecording();
    await tester.pump();

    await tester.tap(find.text('위로 올려서 대화 카드 꺼내기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// 시간 표시 타이머가 남지 않게 화면을 내리고 상태를 버린다.
  Future<void> leave(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    await tester.pump();
    container.dispose();
  }

  VisitState stateOf(ProviderContainer container) =>
      container.read(visitControllerProvider).value!;

  testWidgets('시트를 꺼내도 녹음 중과 흐르는 시간이 시트 안에 보인다', (tester) async {
    final container = await openSheet(tester);
    final start = stateOf(container).elapsed;

    expect(_inSheet(find.text('녹음 중')), findsOneWidget);
    expect(_inSheet(find.text(_label(start))), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(
      _inSheet(find.text(_label(start + const Duration(seconds: 2)))),
      findsOneWidget,
      reason: '시트를 내리지 않아도 시간이 흐르는 것이 보인다',
    );

    await leave(tester, container);
  });

  testWidgets('녹음이 멈추면 시트에도 잠시 멈춤이 보이고 시간이 멈춘다', (tester) async {
    final container = await openSheet(tester);
    final visit = container.read(visitControllerProvider.notifier);

    await visit.pauseRecording();
    await tester.pump();
    final paused = _label(stateOf(container).elapsed);

    expect(_inSheet(find.text('잠시 멈춤')), findsOneWidget);
    expect(_inSheet(find.text('녹음 중')), findsNothing);
    expect(_inSheet(find.text(paused)), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(
      _inSheet(find.text(paused)),
      findsOneWidget,
      reason: '멈춘 동안 시간도 멈춘다',
    );

    await visit.startRecording();
    await tester.pump();
    expect(_inSheet(find.text('녹음 중')), findsOneWidget);
    expect(_inSheet(find.text('잠시 멈춤')), findsNothing);

    await leave(tester, container);
  });

  testWidgets('시트의 작은 녹음 원도 녹음하는 동안만 물결이 퍼진다', (tester) async {
    RecordingPulse.motion = true;
    addTearDown(() => RecordingPulse.motion = false);
    final container = await openSheet(tester);

    bool sheetPulse() => tester
        .widget<RecordingPulse>(_inSheet(find.byType(RecordingPulse)))
        .active;

    expect(sheetPulse(), isTrue);

    await container.read(visitControllerProvider.notifier).pauseRecording();
    await tester.pump();
    expect(sheetPulse(), isFalse);

    await container.read(visitControllerProvider.notifier).startRecording();
    await tester.pump();
    expect(sheetPulse(), isTrue);

    await leave(tester, container);
  });

  testWidgets('화면 낭독기는 녹음 상태가 바뀌면 알리고 흐르는 시간은 알리지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await openSheet(tester);

    expect(
      tester.getSemantics(_inSheet(find.bySemanticsLabel('녹음 중이에요'))),
      isSemantics(label: '녹음 중이에요', isLiveRegion: true),
    );
    final time = _label(stateOf(container).elapsed);
    expect(
      tester.getSemantics(_inSheet(find.text(time))),
      isSemantics(isLiveRegion: false),
      reason: '1초마다 바뀌는 시간을 매번 읽지 않는다',
    );

    await container.read(visitControllerProvider.notifier).pauseRecording();
    await tester.pump();
    expect(
      tester.getSemantics(_inSheet(find.bySemanticsLabel('잠시 멈췄어요'))),
      isSemantics(label: '잠시 멈췄어요', isLiveRegion: true),
    );

    await leave(tester, container);
    handle.dispose();
  });

  // 글자 2.0배는 넣지 않는다. 테스트 글꼴은 글자마다 정사각형이라 숫자가 실제
  // 글꼴의 두 배쯤 넓고, 360x640 2.0배에서는 녹음 화면의 컨트롤 줄과 꼬리 질문
  // 칸이 이 변경 전부터 넘친다(UX 점검 12번). 2.0배는 실제 글꼴로 그려 본다.
  group('작은 화면과 큰 글자', () {
    for (final (size, scale) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
      (Size(390, 844), 1.0),
      (Size(390, 844), 1.3),
    ]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} 글자 $scale배에서 녹음 표시가 '
        '시트 안에 있고 카드 막대와 겹치지 않는다',
        (tester) async {
          final handle = tester.ensureSemantics();
          final container = await openSheet(
            tester,
            logical: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);

          final sheet = tester.getRect(find.byType(BottomSheet));
          final status = tester.getRect(
            find.byKey(const Key('visitSheetRecordingStatus')),
          );
          final firstSegment = tester.getRect(
            _inSheet(find.bySemanticsLabel('1번 카드')),
          );

          expect(status.top, greaterThanOrEqualTo(sheet.top));
          expect(status.left, greaterThanOrEqualTo(sheet.left));
          expect(status.right, lessThanOrEqualTo(sheet.right));
          expect(
            status.bottom,
            lessThanOrEqualTo(firstSegment.top),
            reason: '카드 막대의 누르는 자리를 덮지 않는다',
          );
          // 손잡이(위아래 12, 높이 4)와 카드 막대 위 여백(16)은 원래대로 두고
          // 그 사이에 끼운다. 그만큼 시트가 화면의 5분의 4보다 높다.
          expect(status.top - sheet.top, greaterThanOrEqualTo(28));
          expect(
            firstSegment.top - status.bottom,
            greaterThanOrEqualTo(16),
            reason: '녹음 표시 줄과 카드 막대 사이 원래 간격',
          );
          expect(sheet.height, greaterThan(size.height * 0.8));

          await leave(tester, container);
          handle.dispose();
        },
      );
    }
  });
}
