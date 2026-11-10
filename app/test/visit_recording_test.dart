// E-2 녹음이 실제 장치를 어떻게 부르는지 확인한다.
//
// 음성 형식과 저장 위치는 `VisitRecorder` 가 안고 있고, 여기서는 상태가 장치를
// 부르는 순서와 실패했을 때의 화면 상태만 본다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:saerok/features/auth/session_refresher.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';
import 'package:saerok/features/visit/pending_uploads.dart';

import 'fake_card_api.dart';
import 'fake_visit_recorder.dart';
import 'fake_pending_uploads.dart';
import 'fake_visit_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 한 장을 고르고 가짜 장치를 끼운 회차를 만든다.
  Future<(ProviderContainer, VisitController)> startVisit(
    FakeVisitRecorder recorder,
  ) async {
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        ...withMockCards,
      ],
    );
    addTearDown(container.dispose);

    final cards = await container.read(cardsControllerProvider.future);
    final selector = container.read(cardsControllerProvider.notifier);
    selector.toggleSelected(cards.cards.first.cardId);

    await container.read(visitControllerProvider.future);
    return (container, container.read(visitControllerProvider.notifier));
  }

  VisitState read(ProviderContainer container) =>
      container.read(visitControllerProvider).value!;

  group('녹음 파일', () {
    test('시작하면 장치를 열고 파일 자리를 받는다', () async {
      final recorder = FakeVisitRecorder();
      final (container, controller) = await startVisit(recorder);

      expect(read(container).recordingPath, isNull);

      await controller.startRecording();

      final state = read(container);
      expect(state.recording, isTrue);
      expect(state.recordingPath, '/fake/visit_recordings/visit-1.wav');
      expect(recorder.calls, ['hasPermission', 'start']);
    });

    test('잠시 멈췄다 이어 가면 같은 파일에 이어 쓴다', () async {
      final recorder = FakeVisitRecorder();
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      final path = read(container).recordingPath;

      await controller.pauseRecording();
      expect(read(container).recording, isFalse);

      await controller.startRecording();

      expect(read(container).recording, isTrue);
      expect(
        read(container).recordingPath,
        path,
        reason: '이어 가기는 새 파일을 만들지 않는다',
      );
      expect(recorder.calls, ['hasPermission', 'start', 'pause', 'resume']);
    });

    test('끝내면 장치를 닫고 저장된 파일이 남는다', () async {
      final recorder = FakeVisitRecorder();
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      await controller.stopRecording();

      final state = read(container);
      expect(state.recording, isFalse);
      expect(state.recordingPath, '/fake/visit_recordings/visit-1.wav');
      expect(state.problem, isNull);
      expect(recorder.calls.last, 'stop');
    });

    test('시작한 적이 없으면 장치를 부르지 않고 끝낸다', () async {
      final recorder = FakeVisitRecorder();
      final (container, controller) = await startVisit(recorder);

      await controller.stopRecording();

      expect(recorder.calls, isEmpty);
      expect(read(container).recordingPath, isNull);
    });

    test('이미 닫은 파일을 다시 닫으려 들지 않는다', () async {
      // 끝내기를 누른 뒤 화면을 떠나면 끝내기가 두 번 불린다. 두 번째를 그대로
      // 장치에 넘기면 닫을 것이 없어 저장 실패로 잘못 표시된다.
      final recorder = FakeVisitRecorder();
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      await controller.stopRecording();
      await controller.stopRecording();

      expect(recorder.calls.where((call) => call == 'stop'), hasLength(1));
      expect(read(container).problem, isNull);
    });
  });

  // 녹음하는 동안 세션을 잃어도 로그인 화면으로 보내지 않도록 세션을 붙잡아
  // 둔다(2026-11-10 E2E). 파일을 닫으면 놓는다.
  group('녹음하는 동안 세션 붙잡기', () {
    bool held(ProviderContainer container) =>
        container.read(sessionHoldProvider);

    test('녹음을 시작하면 붙잡고 잠시 멈춰도 놓지 않는다', () async {
      final (container, controller) = await startVisit(FakeVisitRecorder());
      expect(held(container), isFalse);

      await controller.startRecording();
      expect(held(container), isTrue);

      await controller.pauseRecording();
      expect(held(container), isTrue, reason: '파일은 아직 열려 있다');
    });

    test('만남을 끝내 파일을 닫으면 놓는다', () async {
      final (container, controller) = await startVisit(FakeVisitRecorder());
      await controller.startRecording();

      await controller.stopRecording(participantCount: 2);

      expect(held(container), isFalse);
    });

    test('끝내지 않고 녹음 화면을 떠나도 파일을 닫은 뒤 놓는다', () async {
      final (container, controller) = await startVisit(FakeVisitRecorder());
      await controller.startRecording();

      await controller.stopRecordingOnLeave();

      expect(held(container), isFalse);
    });

    test('녹음을 마무리하지 못한 채 면회가 정리돼도 놓는다', () async {
      final (container, controller) = await startVisit(FakeVisitRecorder());
      await controller.startRecording();
      expect(held(container), isTrue);

      container.invalidate(visitControllerProvider);
      await container.read(visitControllerProvider.future);
      // 정리하는 중에는 미뤄 놓는다.
      await Future<void>.delayed(Duration.zero);

      expect(held(container), isFalse);
    });

    test('녹음을 시작하지 못하면 붙잡지 않는다', () async {
      final recorder = FakeVisitRecorder(permitted: false);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();

      expect(held(container), isFalse);
    });
  });

  test('녹음을 시작하자마자 회차와 파일을 기기에 적어 둔다', () async {
    // 녹음 중에 앱이 죽으면 끝내기와 화면 떠나기가 불리지 않는다. 시작할 때 적어
    // 두어야 다시 켰을 때 이 회차의 파일을 찾아 보낼 수 있다.
    final recorder = FakeVisitRecorder();
    final uploads = FakePendingUploads();
    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        ...mockCardsWith(pendingUploads: uploads),
      ],
    );
    addTearDown(container.dispose);
    final cards = await container.read(cardsControllerProvider.future);
    container
        .read(cardsControllerProvider.notifier)
        .toggleSelected(cards.cards.first.cardId);
    await container.read(visitControllerProvider.future);

    await container.read(visitControllerProvider.notifier).startRecording();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.calls, isNot(contains('stop')));
    final pending = uploads.saved[FakeVisitApi.sessionId];
    expect(pending?.audioPath, read(container).recordingPath);
    expect(pending?.participantCount, isNull);
  });

  group('화면을 떠날 때', () {
    testWidgets('끝내기를 누르지 않고 나가도 파일을 닫는다', (tester) async {
      // 닫지 않으면 WAV 헤더가 쓰이지 않아 재생할 수 없는 파일이 남는다.
      final recorder = FakeVisitRecorder();
      final uploads = FakePendingUploads();
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          ...mockCardsWith(pendingUploads: uploads),
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

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: RecordScreen()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();

      expect(recorder.calls, isNot(contains('stop')));

      // 녹음 화면을 화면 밖으로 내보낸다. 뒤로 나가는 것과 같다.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      expect(recorder.calls, contains('stop'));
      expect(uploads.saved[FakeVisitApi.sessionId]?.audioPath, isNotNull);
      expect(uploads.saved[FakeVisitApi.sessionId]?.participantCount, isNull);
      expect(
        container.read(visitControllerProvider).value!.participantCount,
        isNull,
        reason: '확인받지 않은 사람 수를 대신 지어내지 않는다',
      );
    });

    // 디버그 빌드에서 열린 파일 없이 화면을 떠나면 dispose 안에서 상태를 바로
    // 바꿔 Riverpod 이 `Tried to modify a provider while the widget tree was
    // building` 을 던지던 경로다. 같은 컨테이너를 유지한 채 화면만 내린다.
    Future<(ProviderContainer, VisitController, FakeVisitRecorder)> showScreen(
      WidgetTester tester, {
      required bool start,
    }) async {
      final recorder = FakeVisitRecorder();
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          ...mockCardsWith(pendingUploads: FakePendingUploads()),
        ],
      );
      addTearDown(container.dispose);

      late VisitController visit;
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
            child: const MaterialApp(home: RecordScreen()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      return (container, visit, recorder);
    }

    Future<void> leaveScreen(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();
    }

    test('화면을 떠날 때도 열린 파일은 그 호출 안에서 바로 닫기 시작한다', () async {
      final recorder = FakeVisitRecorder();
      final (container, visit) = await startVisit(recorder);
      await visit.startRecording();

      final leaving = visit.stopRecordingOnLeave();
      expect(recorder.calls.last, 'stop', reason: '닫기를 미루지 않는다');

      await leaving;
      expect(read(container).recording, isFalse);
      expect(read(container).recordingPath, isNotNull);
    });

    test('닫을 파일이 없으면 상태 변경만 다음 microtask 로 미룬다', () async {
      final recorder = FakeVisitRecorder();
      final (container, visit) = await startVisit(recorder);
      await visit.startRecording();
      await visit.stopRecording();
      recorder.calls.clear();
      var notified = 0;
      final sub = container.listen(
        visitControllerProvider,
        (_, _) => notified++,
      );
      addTearDown(sub.close);

      final leaving = visit.stopRecordingOnLeave();
      expect(notified, 0, reason: '호출 안에서는 상태를 바꾸지 않는다');

      await leaving;
      expect(notified, greaterThan(0), reason: '미룬 변경은 결국 닿는다');
      expect(read(container).recording, isFalse);
      expect(recorder.calls, isNot(contains('stop')));
    });

    test('보낸 녹음은 화면을 떠날 때 다시 보낼 녹음으로 돌아가지 않는다', () async {
      // 제출이 끝나 보냈다고 적은 뒤 녹음 화면이 늦게 정리되는 경우다. 다시
      // 적으면 앱을 다시 켰을 때 같은 녹음을 또 보내려 든다.
      final recorder = FakeVisitRecorder();
      final uploads = FakePendingUploads();
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          ...mockCardsWith(pendingUploads: uploads),
        ],
      );
      addTearDown(container.dispose);
      final cards = await container.read(cardsControllerProvider.future);
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(cards.cards.first.cardId);
      await container.read(visitControllerProvider.future);
      final visit = container.read(visitControllerProvider.notifier);

      await visit.startRecording();
      await visit.stopRecording(participantCount: 2);
      final pending = uploads.saved[FakeVisitApi.sessionId]!;
      await uploads.markUploaded(pending);

      await visit.stopRecordingOnLeave();

      expect(uploads.saved, isEmpty);
      expect(uploads.uploaded[FakeVisitApi.sessionId]?.participantCount, 2);
    });

    testWidgets('녹음 전 안내에서 나가도 상태 수정 오류가 나지 않는다', (tester) async {
      final (container, _, recorder) = await showScreen(tester, start: false);
      expect(find.text('네, 좋아요'), findsOneWidget);

      await leaveScreen(tester, container);

      expect(tester.takeException(), isNull);
      expect(recorder.calls, isNot(contains('stop')), reason: '닫을 파일이 없다');
      expect(read(container).recording, isFalse);
    });

    testWidgets('녹음을 끝낸 뒤 나가도 상태 수정 오류가 나지 않는다', (tester) async {
      final (container, visit, recorder) = await showScreen(
        tester,
        start: true,
      );
      await tester.runAsync(visit.stopRecording);
      await tester.pump();
      recorder.calls.clear();

      await leaveScreen(tester, container);

      expect(tester.takeException(), isNull);
      expect(recorder.calls, isNot(contains('stop')), reason: '이미 닫았다');
      expect(read(container).recording, isFalse);
      expect(read(container).recordingPath, isNotNull);
    });
  });

  group('녹음이 되지 않을 때', () {
    test('마이크 권한이 없으면 시작하지 않고 알린다', () async {
      final recorder = FakeVisitRecorder(permitted: false);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();

      final state = read(container);
      expect(state.started, isFalse, reason: '녹음 중 화면으로 넘어가지 않는다');
      expect(state.recording, isFalse);
      expect(state.problem, VisitRecordingProblem.permissionDenied);
      expect(recorder.calls, ['hasPermission']);
    });

    test('장치가 열리지 않으면 시작 실패로 남긴다', () async {
      final recorder = FakeVisitRecorder(failOnStart: true);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();

      final state = read(container);
      expect(state.started, isFalse);
      expect(state.problem, VisitRecordingProblem.startFailed);
    });

    test('다시 시작해서 성공하면 안내가 사라진다', () async {
      final recorder = FakeVisitRecorder(permitted: false);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      expect(read(container).problem, isNotNull);

      recorder.permitted = true;
      await controller.startRecording();

      expect(read(container).problem, isNull);
      expect(read(container).recording, isTrue);
    });

    test('파일을 닫지 못하면 저장 실패로 알린다', () async {
      final recorder = FakeVisitRecorder(failOnStop: true);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      await controller.stopRecording();

      final state = read(container);
      expect(state.recording, isFalse);
      expect(state.problem, VisitRecordingProblem.saveFailed);
      expect(
        await container
            .read(pendingUploadsProvider)
            .find(FakeVisitApi.sessionId),
        isNull,
      );
    });

    test('끝냈는데 파일이 없으면 저장 실패로 알린다', () async {
      final recorder = FakeVisitRecorder(losesFile: true);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      await controller.stopRecording();

      expect(read(container).problem, VisitRecordingProblem.saveFailed);
    });
  });

  group('녹음 중에 정리될 때', () {
    test('파일을 닫는 사이 컨테이너가 정리되면 상태를 건드리지 않고 끝낸다', () async {
      // 앱을 통째로 정리하거나 로그아웃으로 provider 를 버리는 경우다. 파일
      // 닫기(`stop`)가 끝나기 전에 정리되면, 끝난 뒤 정리된 ref 를 쓰지 않아야 한다.
      final recorder = _SlowStopRecorder();
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          ...withMockCards,
        ],
      );
      final cards = await container.read(cardsControllerProvider.future);
      container
          .read(cardsControllerProvider.notifier)
          .toggleSelected(cards.cards.first.cardId);
      await container.read(visitControllerProvider.future);
      final controller = container.read(visitControllerProvider.notifier);
      await controller.startRecording();

      final stopping = controller.stopRecording(participantCount: 2);
      expect(recorder.calls, contains('stop'));
      container.dispose();
      recorder.finishStop();

      await expectLater(stopping, completes);
    });
  });

  group('음성 형식', () {
    // AI 영역이 형식을 확정하면 이 값이 바뀐다. 바뀌었는데 문서가 그대로면
    // 이 테스트가 먼저 알려 준다.
    test('잠정값은 WAV 16kHz 모노다', () {
      expect(visitRecordConfig.encoder, AudioEncoder.wav);
      expect(visitRecordConfig.sampleRate, 16000);
      expect(visitRecordConfig.numChannels, 1);
      expect(VisitRecording.fileExtension, 'wav');
    });
  });
}

/// 파일 닫기를 테스트가 풀어 줄 때까지 붙잡아 두는 녹음 장치.
class _SlowStopRecorder extends FakeVisitRecorder {
  final _stopped = Completer<void>();

  void finishStop() => _stopped.complete();

  @override
  Future<VisitRecording?> stop() async {
    final saved = await super.stop();
    await _stopped.future;
    return saved;
  }
}
