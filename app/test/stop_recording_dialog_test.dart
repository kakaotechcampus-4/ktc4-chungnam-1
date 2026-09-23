// E-2 만남 끝내기 확인 창을 확인한다.
//
// 창이 떠 있는 동안 녹음을 멈추고, 이어서 녹음하면 같은 파일에 이어 쓰며,
// 끝내면 보호자가 확인해 준 참여자 수가 남는지 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 두 장을 고르고 녹음이 돌아가는 녹음 화면을 띄운다.
  Future<ProviderContainer> openRecording(
    WidgetTester tester,
    FakeVisitRecorder recorder,
  ) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [visitRecorderProvider.overrideWithValue(recorder)],
    );
    addTearDown(container.dispose);

    final router = buildRouter();
    router.go(AppRoutes.visitRecord);

    // 목 데이터는 asset 에서 읽으므로 실제 비동기 처리를 기다린다.
    await tester.runAsync(() async {
      final cards = await container.read(cardsControllerProvider.future);
      final selector = container.read(cardsControllerProvider.notifier);
      for (final card in cards.cards.take(2)) {
        selector.toggleSelected(card.cardId);
      }

      await container.read(visitControllerProvider.future);
      final visit = container.read(visitControllerProvider.notifier);
      visit.confirmCareRecipient(confirmed: true);
      await visit.startRecording();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    return container;
  }

  /// 창이 떴다 사라질 시간을 준다. 시간 표시가 1초마다 다시 그려지므로
  /// pumpAndSettle 을 쓰지 않는다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapStop(WidgetTester tester) async {
    await tester.tap(find.text('만남 끝내기'));
    await settle(tester);
  }

  VisitState read(ProviderContainer container) =>
      container.read(visitControllerProvider).value!;

  group('끝내기를 누르면', () {
    testWidgets('묻는 창이 뜨고 녹음은 잠시 멈춘다', (tester) async {
      final recorder = FakeVisitRecorder();
      final container = await openRecording(tester, recorder);

      expect(read(container).recording, isTrue);

      await tapStop(tester);

      expect(find.text('만남을 끝낼까요?'), findsOneWidget);
      expect(find.text('오늘 대화에 몇 분이 함께했나요?'), findsOneWidget);
      expect(
        read(container).recording,
        isFalse,
        reason: '창을 보는 사이의 침묵을 대화로 남기지 않는다',
      );
      expect(recorder.calls, contains('pause'));
      expect(
        recorder.calls,
        isNot(contains('stop')),
        reason: '아직 확인 전이라 파일을 닫지 않는다',
      );
    });

    testWidgets('사람 수는 두 명으로 시작한다', (tester) async {
      await openRecording(tester, FakeVisitRecorder());
      await tapStop(tester);

      expect(find.text('2명'), findsOneWidget);
    });

    testWidgets('더하고 뺄 수 있다', (tester) async {
      await openRecording(tester, FakeVisitRecorder());
      await tapStop(tester);

      await tester.tap(find.byKey(const Key('participantPlus')));
      await tester.pump();
      expect(find.text('3명'), findsOneWidget);

      await tester.tap(find.byKey(const Key('participantMinus')));
      await tester.tap(find.byKey(const Key('participantMinus')));
      await tester.pump();
      expect(find.text('1명'), findsOneWidget);
    });

    testWidgets('한 명 아래로는 내려가지 않는다', (tester) async {
      await openRecording(tester, FakeVisitRecorder());
      await tapStop(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('participantMinus')));
        await tester.pump();
      }

      expect(find.text('1명'), findsOneWidget, reason: '계약상 1 이상이다');
    });

    testWidgets('여덟 명 위로는 올라가지 않는다', (tester) async {
      await openRecording(tester, FakeVisitRecorder());
      await tapStop(tester);

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const Key('participantPlus')));
        await tester.pump();
      }

      expect(find.text('8명'), findsOneWidget);
    });
  });

  group('이어서 녹음을 고르면', () {
    testWidgets('창이 닫히고 같은 파일에 이어 쓴다', (tester) async {
      final recorder = FakeVisitRecorder();
      final container = await openRecording(tester, recorder);
      final path = read(container).recordingPath;

      await tapStop(tester);
      await tester.tap(find.text('이어서 녹음'));
      await settle(tester);

      expect(find.text('만남을 끝낼까요?'), findsNothing);
      expect(read(container).recording, isTrue);
      expect(read(container).recordingPath, path, reason: '새 파일을 만들지 않는다');
      expect(read(container).participantCount, isNull);
      expect(recorder.calls, contains('resume'));
      expect(recorder.calls, isNot(contains('stop')));
    });

    testWidgets('잠시 멈춤 상태였으면 멈춘 채로 돌아간다', (tester) async {
      final recorder = FakeVisitRecorder();
      final container = await openRecording(tester, recorder);

      await tester.tap(find.text('잠시 멈춤'));
      await settle(tester);
      expect(read(container).recording, isFalse);

      await tapStop(tester);
      await tester.tap(find.text('이어서 녹음'));
      await settle(tester);

      expect(
        read(container).recording,
        isFalse,
        reason: '취소는 멈추기 전으로 돌아가는 것이지 녹음을 켜는 것이 아니다',
      );
    });
  });

  group('끝내기를 고르면', () {
    testWidgets('확인한 사람 수가 남고 파일을 닫는다', (tester) async {
      final recorder = FakeVisitRecorder();
      final container = await openRecording(tester, recorder);

      await tapStop(tester);
      await tester.tap(find.byKey(const Key('participantPlus')));
      await tester.pump();
      await tester.tap(find.text('끝내기'));
      await settle(tester);

      final state = read(container);
      expect(state.recording, isFalse);
      expect(state.participantCount, 3);
      expect(state.problem, isNull);
      expect(recorder.calls, contains('stop'));
    });

    testWidgets('소감 화면으로 넘어간다', (tester) async {
      await openRecording(tester, FakeVisitRecorder());

      await tapStop(tester);
      await tester.tap(find.text('끝내기'));
      await settle(tester);
      // 소감 화면도 목 데이터를 asset 에서 읽는다.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();

      expect(find.text('만남을 끝낼까요?'), findsNothing);
      expect(find.text('오늘 만남은\n어떠셨나요?'), findsOneWidget);
    });
  });
}
