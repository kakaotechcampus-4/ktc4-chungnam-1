// 녹음 파일을 닫은 뒤 녹음 화면에 다시 들어온 경우를 확인한다(2026-11-10 UX
// 점검 1번).
//
// `record` 는 파일을 닫은 뒤의 이어 가기를 오류 없이 무시한다. 예전에는 이때도
// `잠시 멈췄어요` 와 `이어서 녹음` 을 보여주고, 누르면 녹음되는 것 없이 시간만
// 흘렀다. 이제는 `이미 끝낸 면회예요` 와 다음 할 일 하나만 둔다.
//
// - 만남을 끝내고 소감 화면에서 뒤로 오면 `소감 쓰기`
// - 끝내지 않고 나간 뒤 사진 화면에서 다시 시작하면 `평가 이어서 하기`
//
// 서버, 녹음 장치와 기기 기록은 대역을 쓰고 값은 모두 합성이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saerok/app/routes.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/cards/cards_screen.dart' show cardSelectLabel;
import 'package:saerok/features/review/review_screen.dart';
import 'package:saerok/features/visit/pending_uploads.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/widgets/app_surfaces.dart';

import 'fake_card_api.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_recorder.dart';
import 'journey/journey_harness.dart';
import 'journey/journey_server.dart';

Finder _toggle(String title) => find.byWidgetPredicate(
  (w) => w is SelectionToggle && w.label == cardSelectLabel(title),
);

const _finished = '이미 끝낸 면회예요';
const _reviewTitle = '오늘 만남은\n어떠셨나요?';

/// 카드 한 장을 골라 녹음을 시작한다.
Future<JourneyDriver> _recording(WidgetTester tester) async {
  final server = JourneyServer();
  final app = await JourneyDriver.launch(tester, server);
  await app.waitFor(find.text('오늘의 대화카드 받기'), maxSteps: 300);
  await app.tap(find.text('오늘의 대화카드 받기'));
  await app.waitFor(find.text('오늘의 대화 카드'));
  final setId = server.setIds.single;
  await app.tap(_toggle(server.cardTitlesOf(setId).first));
  await app.tap(find.text('대화 시작하기'));
  await app.tap(find.text('사진 없이 시작할게요'));
  await app.tap(find.text('네, 좋아요'));
  await app.waitFor(find.text('녹음 중이에요'));
  // 시간이 몇 초 흐르게 둔다.
  for (var i = 0; i < 20; i++) {
    await app.step();
  }
  return app;
}

ProviderContainer _containerOf(WidgetTester tester, Finder finder) =>
    ProviderScope.containerOf(tester.element(finder));

/// 끝낸 면회 화면에는 녹음을 이어 가는 길이 없다.
void _expectNoRecording() {
  expect(find.text(_finished), findsOneWidget);
  expect(find.text('이어서 녹음'), findsNothing);
  expect(find.bySemanticsLabel('이어서 녹음'), findsNothing);
  expect(find.text('잠시 멈췄어요'), findsNothing);
  expect(find.text('녹음 중이에요'), findsNothing);
  expect(find.text('네, 좋아요'), findsNothing);
}

void main() {
  testWidgets('만남을 끝내고 소감 화면에서 뒤로 오면 이어서 녹음 대신 소감 쓰기만 둔다', (tester) async {
    final app = await _recording(tester);
    await app.tap(find.byIcon(Icons.stop));
    await app.waitFor(find.text('만남을 끝낼까요?'));
    await app.tap(find.text('끝내기'));
    await app.waitFor(find.text(_reviewTitle));

    await app.back();
    await app.waitFor(find.text(_finished));

    _expectNoRecording();
    expect(find.text('평가 이어서 하기'), findsNothing);
    final container = _containerOf(tester, find.text(_finished));
    final stoppedAt = container.read(visitControllerProvider).value!.elapsed;
    for (var i = 0; i < 20; i++) {
      await app.step();
    }
    expect(
      container.read(visitControllerProvider).value!.elapsed,
      stoppedAt,
      reason: '끝낸 면회의 시간은 흐르지 않는다',
    );

    await app.tap(find.text('소감 쓰기'));
    await app.waitFor(find.text(_reviewTitle));
    expect(app.recorder.starts, 1, reason: '새로 녹음하지 않는다');
    await app.close();
  });

  testWidgets('끝내지 않고 나간 뒤 다시 시작하면 평가 이어서 하기만 두고 녹음하지 않는다', (tester) async {
    final app = await _recording(tester);
    await app.back();
    await app.tap(find.text('그만두고 나가기'));
    await app.waitFor(find.text('사진 없이 시작할게요'));

    await app.tap(find.text('사진 없이 시작할게요'));
    await app.waitFor(find.text(_finished));

    _expectNoRecording();
    expect(find.text('소감 쓰기'), findsNothing);
    expect(app.recorder.starts, 1);
    final container = _containerOf(tester, find.text(_finished));
    final sessionId = container.read(visitControllerProvider).value!.sessionId;
    expect(sessionId, isNotNull);

    await app.tap(find.text('평가 이어서 하기'));
    await app.waitFor(find.text(_reviewTitle));
    expect(
      find.byWidgetPredicate(
        (w) => w is ReviewScreen && w.sessionId == sessionId,
      ),
      findsOneWidget,
      reason: '카드 화면과 홈의 평가 이어서 하기와 같은 회차 평가로 간다',
    );
    await app.close();
  });

  testWidgets('끝낸 면회 화면에서 뒤로 가면 그만둘지 묻지 않고 나간다', (tester) async {
    final app = await _recording(tester);
    await app.back();
    await app.tap(find.text('그만두고 나가기'));
    await app.tap(find.text('사진 없이 시작할게요'));
    await app.waitFor(find.text(_finished));

    await app.back();

    expect(find.text('녹음을 그만둘까요?'), findsNothing, reason: '멈출 녹음이 없다');
    await app.waitFor(find.text('사진 없이 시작할게요'));
    expect(find.text(_finished), findsNothing);
    await app.close();
  });

  // 파일을 닫으면 녹음 중 화면이 끝낸 면회 화면으로 바뀐다. 실기기에서는 그 뒤
  // 기기 기록(pending-uploads.json)을 적는 동안 화면이 그려지므로, 녹음 중 화면의
  // context 로 넘어가려 하면 이미 사라져 소감 화면이 열리지 않는다.
  testWidgets('끝내기 뒤 기록을 적는 사이 화면이 바뀌어도 소감 화면으로 넘어간다', (tester) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final uploads = _HeldPendingUploads();
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(FakeVisitRecorder()),
        ...mockCardsWith(pendingUploads: uploads),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.visitRecord,
      routes: [
        GoRoute(
          path: AppRoutes.visitRecord,
          builder: (context, state) => const RecordScreen(),
        ),
        GoRoute(
          path: AppRoutes.visitReview,
          builder: (context, state) => const Scaffold(body: Text('소감 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);

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
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(find.text('녹음 중이에요'), findsOneWidget);

    uploads.hold();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('끝내기'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(_finished), findsOneWidget, reason: '파일은 닫았고 기록을 적는 중이다');
    expect(find.text('소감 화면'), findsNothing);

    uploads.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('소감 화면'), findsOneWidget);
  });

  testWidgets('녹음 파일을 저장하지 못했으면 끝낸 면회 화면에 그 안내를 함께 둔다', (tester) async {
    tester.view.physicalSize = const Size(1236, 2751);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final recorder = FakeVisitRecorder(failOnStop: true);
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        ...mockCardsWith(pendingUploads: FakePendingUploads()),
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      final cards = await container.read(cardsControllerProvider.future);
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(cards.cards.first.cardId);
      await container.read(visitControllerProvider.future);
      final visit = container.read(visitControllerProvider.notifier);
      await visit.startRecording();
      await visit.stopRecording(participantCount: 2);

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

    expect(find.text(_finished), findsOneWidget);
    expect(find.textContaining('녹음 파일을 저장하지 못했어요'), findsOneWidget);
    expect(
      find.textContaining('리포트를 만들어요'),
      findsNothing,
      reason: '녹음이 없으면 리포트를 만든다고 하지 않는다',
    );
    expect(find.text('소감 쓰기'), findsOneWidget);
    expect(find.text('이어서 녹음'), findsNothing);
  });
}

/// 기록 적기를 테스트가 풀어 줄 때까지 붙잡아 둘 수 있는 기기 기록 대역.
class _HeldPendingUploads extends FakePendingUploads {
  Completer<void>? _held;

  void hold() => _held = Completer<void>();

  void release() => _held?.complete();

  @override
  Future<void> save(PendingUpload upload) async {
    await _held?.future;
    await super.save(upload);
  }
}
