// E-2 녹음이 실제 장치를 어떻게 부르는지 확인한다.
//
// 음성 형식과 저장 위치는 `VisitRecorder` 가 안고 있고, 여기서는 상태가 장치를
// 부르는 순서와 실패했을 때의 화면 상태만 본다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_visit_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 카드 한 장을 고르고 가짜 장치를 끼운 회차를 만든다.
  Future<(ProviderContainer, VisitController)> startVisit(
    FakeVisitRecorder recorder,
  ) async {
    final container = ProviderContainer(
      overrides: [visitRecorderProvider.overrideWithValue(recorder)],
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

  group('화면을 떠날 때', () {
    testWidgets('끝내기를 누르지 않고 나가도 파일을 닫는다', (tester) async {
      // 닫지 않으면 WAV 헤더가 쓰이지 않아 재생할 수 없는 파일이 남는다.
      final recorder = FakeVisitRecorder();
      final container = ProviderContainer(
        overrides: [visitRecorderProvider.overrideWithValue(recorder)],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        final cards = await container.read(cardsControllerProvider.future);
        container
            .read(cardsControllerProvider.notifier)
            .toggleSelected(cards.cards.first.cardId);

        await container.read(visitControllerProvider.future);
        final visit = container.read(visitControllerProvider.notifier);
        visit.confirmCareRecipient(confirmed: true);
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
    });

    test('끝냈는데 파일이 없으면 저장 실패로 알린다', () async {
      final recorder = FakeVisitRecorder(losesFile: true);
      final (container, controller) = await startVisit(recorder);

      await controller.startRecording();
      await controller.stopRecording();

      expect(read(container).problem, VisitRecordingProblem.saveFailed);
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
