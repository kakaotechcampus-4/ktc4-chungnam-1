// 면회 녹음이 앱 생명주기로는 멈추지 않고, 보호자 모르게 멈추면 크게 알리는지
// 확인한다(2026-11-10 PM 결정).
//
// 녹음 장치는 대역([FakeVisitRecorder])이 상태 알림을 흉내 낸다. 실제로 전화나
// 다른 앱의 소리에 `record` 가 멈추는지, 알림 소리와 진동이 나는지는 이 테스트가
// 보지 않는다(`app/README.md` 의 면회 녹음).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/recording_service.dart';
import 'package:saerok/features/visit/recording_stopped_alert.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_recording_service.dart';
import 'fake_screen_awake.dart';
import 'fake_visit_recorder.dart';

const _recording = 'show:${RecordingNoticeText.recording}';
const _stopped = 'show:${RecordingNoticeText.stopped}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 진동 요청을 센다.
  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method.startsWith('HapticFeedback')) {
            haptics.add('${call.method}:${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// 카드 한 장을 고른 회차로 녹음을 시작하고 녹음 화면을 띄운다.
  ///
  /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
  Future<(ProviderContainer, VisitController)> open(
    WidgetTester tester, {
    required FakeVisitRecorder recorder,
    FakeRecordingServicePlatform? service,
    FakeScreenAwakePlatform? screenAwake,
    Size logical = const Size(412, 917),
  }) async {
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        visitRecorderProvider.overrideWithValue(recorder),
        (service ?? FakeRecordingServicePlatform(grantsPermission: false))
            .asOverride,
        (screenAwake ?? FakeScreenAwakePlatform()).asOverride,
        ...withMockCards,
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
    return (container, visit);
  }

  /// 대역의 상태 알림과 바뀐 화면이 닿게 한다.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// 시간 표시 타이머가 남지 않게 화면을 내린다.
  Future<void> leave(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await settle(tester);
  }

  VisitState read(ProviderContainer container) =>
      container.read(visitControllerProvider).value!;

  final alertFinder = find.byKey(const Key('recordingStoppedAlert'));

  testWidgets('앱이 뒤로 가거나 화면이 꺼져도 녹음을 멈추지 않는다', (tester) async {
    final recorder = FakeVisitRecorder();
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final (container, _) = await open(
      tester,
      recorder: recorder,
      service: service,
    );
    // 시간 타이머를 테스트의 가짜 시간에서 다시 시작하려고 한 번 멈췄다 잇는다.
    await tester.tap(find.byIcon(Icons.pause));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    recorder.calls.clear();
    service.calls.clear();
    final before = read(container).elapsed;

    // 다른 앱으로 옮기거나 전원 버튼으로 화면을 끄면 차례로 이렇게 바뀐다.
    for (final lifecycle in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await settle(tester);
    }
    await tester.pump(const Duration(seconds: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(recorder.calls, isNot(contains('pause')));
    expect(read(container).recording, isTrue);
    expect(read(container).elapsed - before, const Duration(seconds: 3));
    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(alertFinder, findsNothing);
    expect(service.calls, isEmpty, reason: '알림도 그대로 녹음 중이다');

    await leave(tester, container);
  });

  testWidgets('보호자가 멈추면 크게 알리지 않는다', (tester) async {
    final recorder = FakeVisitRecorder();
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final (container, _) = await open(
      tester,
      recorder: recorder,
      service: service,
    );

    await tester.tap(find.byIcon(Icons.pause));
    await settle(tester);

    expect(find.text('잠시 멈췄어요'), findsOneWidget);
    expect(alertFinder, findsNothing);
    expect(read(container).problem, isNull);
    expect(haptics, isEmpty);
    expect(service.calls, isNot(contains(_stopped)));

    await leave(tester, container);
  });

  testWidgets('장치가 저절로 멈추면 시간을 멈추고 맨 위에 크게 알리고 진동한다', (tester) async {
    final recorder = FakeVisitRecorder();
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final screenAwake = FakeScreenAwakePlatform();
    final (container, _) = await open(
      tester,
      recorder: recorder,
      service: service,
      screenAwake: screenAwake,
    );
    await tester.pump(const Duration(seconds: 2));

    // 전화가 오거나 다른 앱이 소리를 내 `record` 가 스스로 멈췄다.
    recorder.deviceChanged(VisitRecorderState.paused);
    await settle(tester);

    final stoppedAt = read(container).elapsed;
    expect(read(container).recording, isFalse);
    expect(read(container).problem, VisitRecordingProblem.interrupted);
    expect(alertFinder, findsOneWidget);
    expect(find.text('녹음이 멈췄어요'), findsOneWidget);
    expect(find.text('전화나 다른 앱의 소리 때문에 멈췄을 수 있어요'), findsOneWidget);
    expect(
      find.descendant(of: alertFinder, matching: find.text('이어서 녹음')),
      findsOneWidget,
    );
    expect(haptics, ['HapticFeedback.vibrate:null']);

    // 띠는 화면 맨 위다. 상태 글자보다 위에 있다.
    expect(
      tester.getTopLeft(alertFinder).dy,
      lessThan(tester.getTopLeft(find.text('잠시 멈췄어요')).dy),
    );

    // 화면 낭독기가 바로 읽는다.
    final semantics = tester.getSemantics(alertFinder);
    expect(semantics.flagsCollection.isLiveRegion, isTrue);

    // 알림은 소리와 진동이 나는 `면회 녹음이 멈췄어요` 로 바뀐다.
    expect(service.calls.last, _stopped);
    expect(service.lastText, RecordingNoticeText.stoppedDetail);
    expect(service.lastAlert, isTrue);

    // 띠를 보도록 화면은 켜 둔다.
    expect(screenAwake.isOn, isTrue);

    // 시간이 더 흐르지 않는다.
    await tester.pump(const Duration(seconds: 3));
    expect(read(container).elapsed, stoppedAt);

    // 같은 멈춤으로 다시 진동하지 않는다.
    recorder.deviceChanged(VisitRecorderState.paused);
    await settle(tester);
    expect(haptics, hasLength(1));

    await leave(tester, container);
  });

  testWidgets('띠의 이어서 녹음을 누르면 같은 파일에 이어 쓰고 띠와 멈춤 알림을 거둔다', (tester) async {
    final recorder = FakeVisitRecorder();
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final (container, _) = await open(
      tester,
      recorder: recorder,
      service: service,
    );
    recorder.deviceChanged(VisitRecorderState.paused);
    await settle(tester);
    final stoppedAt = read(container).elapsed;

    await tester.tap(find.byKey(const Key('recordingAlertAction')));
    await settle(tester);

    expect(recorder.calls.where((c) => c == 'start'), hasLength(1));
    expect(recorder.calls.last, 'resume');
    expect(read(container).recording, isTrue);
    expect(read(container).problem, isNull);
    expect(alertFinder, findsNothing);
    expect(find.text('녹음 중이에요'), findsOneWidget);
    expect(service.calls.last, _recording);
    expect(service.lastAlert, isFalse);

    await tester.pump(const Duration(seconds: 2));
    expect(read(container).elapsed - stoppedAt, const Duration(seconds: 2));

    await leave(tester, container);
  });

  testWidgets('대화 카드 시트를 보고 있어도 시트 맨 위에 같은 띠가 뜨고 거기서 이어 간다', (tester) async {
    final recorder = FakeVisitRecorder();
    final (container, _) = await open(tester, recorder: recorder);

    await tester.tap(find.bySemanticsLabel('대화 카드 꺼내기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheetAlert = find.byKey(const Key('visitSheetRecordingAlert'));
    expect(sheetAlert, findsNothing);

    recorder.deviceChanged(VisitRecorderState.paused);
    await settle(tester);

    expect(sheetAlert, findsOneWidget);
    expect(
      find.descendant(of: sheetAlert, matching: find.text('녹음이 멈췄어요')),
      findsOneWidget,
    );
    expect(haptics, hasLength(1), reason: '시트와 화면이 따로 진동하지 않는다');

    await tester.tap(
      find.descendant(of: sheetAlert, matching: find.text('이어서 녹음')),
    );
    await settle(tester);
    expect(recorder.calls.last, 'resume');
    expect(sheetAlert, findsNothing);

    await leave(tester, container);
  });

  testWidgets('장치가 녹음을 끝내 버리면 이어서 녹음 대신 만남 끝내기만 둔다', (tester) async {
    final recorder = FakeVisitRecorder();
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final (container, visit) = await open(
      tester,
      recorder: recorder,
      service: service,
    );

    recorder.deviceFailed();
    await settle(tester);

    expect(read(container).problem, VisitRecordingProblem.recorderStopped);
    expect(alertFinder, findsOneWidget);
    expect(
      find.text('이어서 녹음할 수 없어요. 만남 끝내기를 누르면 지금까지 녹음한 것을 저장해요'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: alertFinder, matching: find.text('만남 끝내기')),
      findsOneWidget,
    );
    expect(find.text('이어서 녹음'), findsNothing);
    expect(haptics, hasLength(1));
    expect(service.calls.last, _stopped);

    // 이어서 녹음을 불러도 소리 없이 시간만 흐르게 하지 않는다.
    await visit.startRecording();
    await settle(tester);
    expect(recorder.calls, isNot(contains('resume')));
    expect(read(container).recording, isFalse);

    await leave(tester, container);
  });

  testWidgets('멈춘 녹음을 이어 가지 못하면 같은 띠로 크게 알린다', (tester) async {
    final recorder = FakeVisitRecorder(failOnResume: true);
    final service = FakeRecordingServicePlatform(grantsPermission: false);
    final (container, _) = await open(
      tester,
      recorder: recorder,
      service: service,
    );
    await tester.tap(find.byIcon(Icons.pause));
    await settle(tester);
    expect(haptics, isEmpty);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);

    expect(read(container).problem, VisitRecordingProblem.startFailed);
    expect(alertFinder, findsOneWidget);
    expect(find.text('녹음을 이어 가지 못했어요'), findsOneWidget);
    expect(haptics, hasLength(1));
    expect(service.calls.last, _stopped);

    await leave(tester, container);
  });

  testWidgets('만남을 끝냈는데 저장하지 못하면 넘어가지 않고 같은 띠로 알린다', (tester) async {
    final recorder = FakeVisitRecorder(failOnStop: true);
    final (container, _) = await open(tester, recorder: recorder);

    await tester.tap(find.byIcon(Icons.stop));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('끝내기'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(read(container).problem, VisitRecordingProblem.saveFailed);
    expect(alertFinder, findsOneWidget);
    expect(find.text('녹음 파일을 저장하지 못했어요'), findsOneWidget);
    expect(
      find.descendant(of: alertFinder, matching: find.text('소감 쓰기')),
      findsOneWidget,
    );
    expect(find.text('이어서 녹음'), findsNothing);
    expect(haptics, hasLength(1));

    await leave(tester, container);
  });

  group('장치가 먼저 닫은 파일', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('saerok_rec_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// 머리글까지 쓴 무음 WAV. 사람 목소리가 아니다.
    void writeFinishedWav(String path) {
      final bytes = BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(List.filled(40, 0))
        ..add(List.filled(320, 0));
      File(path).writeAsBytesSync(bytes.toBytes());
    }

    test('머리글이 있는 파일만 닫힌 녹음으로 본다', () {
      final finished = '${dir.path}/a.wav';
      writeFinishedWav(finished);
      final unfinished = '${dir.path}/b.wav';
      File(unfinished).writeAsBytesSync(List.filled(400, 0));

      expect(isFinishedRecording(finished), isTrue);
      expect(isFinishedRecording(unfinished), isFalse);
      expect(isFinishedRecording('${dir.path}/none.wav'), isFalse);
    });

    test('장치가 끝낸 녹음은 만남 끝내기로 저장하고 멈춤 문제를 남기지 않는다', () async {
      final recorder = FakeVisitRecorder(
        losesFile: true,
        directory: dir.path.replaceAll(r'\', '/'),
      );
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          FakeRecordingServicePlatform(grantsPermission: false).asOverride,
          ...withMockCards,
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
      final path = read(container).recordingPath!;
      // 장치가 파일을 닫고 머리글을 쓴 뒤 세션을 버렸다.
      writeFinishedWav(path);
      recorder.deviceFailed();
      await Future<void>.delayed(Duration.zero);
      expect(read(container).problem, VisitRecordingProblem.recorderStopped);

      await visit.stopRecording(participantCount: 2);

      expect(read(container).recordingPath, path);
      expect(read(container).problem, isNull);
    });
  });

  testWidgets('글자를 키워도 띠의 글자와 버튼이 잘리지 않는다', (tester) async {
    for (final (size, scale) in [
      (const Size(360, 640), 1.0),
      (const Size(390, 844), 1.3),
      (const Size(390, 844), 2.0),
    ]) {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: RecordingStoppedAlert(
                  alert: RecordingAlert.interrupted,
                  actionLabel: '이어서 녹음',
                  onAction: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: '$size x$scale');
      final button = tester.getRect(
        find.byKey(const Key('recordingAlertAction')),
      );
      final label = tester.getRect(find.text('이어서 녹음'));
      expect(button.height, greaterThanOrEqualTo(56), reason: '$size x$scale');
      expect(button.top, lessThanOrEqualTo(label.top));
      expect(button.bottom, greaterThanOrEqualTo(label.bottom));
    }
  });

  test('보호자 모르게 멈춘 경우만 크게 알릴 멈춤으로 고른다', () {
    VisitState state({required bool started, VisitRecordingProblem? problem}) =>
        VisitState(
          cards: const [],
          currentIndex: 0,
          followUpIndex: 0,
          started: started,
          recording: false,
          elapsed: Duration.zero,
          problem: problem,
        );

    expect(recordingAlertOf(null), isNull);
    expect(
      recordingAlertOf(
        state(started: false, problem: VisitRecordingProblem.startFailed),
      ),
      isNull,
      reason: '첫 시작 실패는 녹음 안내 화면의 안내 상자가 맡는다',
    );
    expect(
      recordingAlertOf(
        state(started: true, problem: VisitRecordingProblem.interrupted),
      ),
      RecordingAlert.interrupted,
    );
    expect(
      recordingAlertOf(
        state(started: true, problem: VisitRecordingProblem.recorderStopped),
      ),
      RecordingAlert.deviceStopped,
    );
    expect(
      recordingAlertOf(
        state(started: true, problem: VisitRecordingProblem.saveFailed),
      ),
      RecordingAlert.saveFailed,
    );
    expect(recordingAlertOf(state(started: true)), isNull);
  });
}
