// 면회 녹음 파일이 열려 있는 동안에만 마이크 포그라운드 서비스와 알림을 띄우는지
// 확인한다.
//
// 서비스는 대역([FakeRecordingServicePlatform])이 받는다. 실기기에서 화면을 끄거나
// 다른 앱으로 옮긴 뒤에도 소리가 파일에 남는지, 알림이 정말 보이는지는 이 테스트가
// 보지 않는다(`app/README.md` 의 면회 녹음).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/design/theme.dart';
import 'package:saerok/features/cards/cards_controller.dart';
import 'package:saerok/features/visit/record_screen.dart';
import 'package:saerok/features/visit/recording_service.dart';
import 'package:saerok/features/visit/visit_controller.dart';
import 'package:saerok/features/visit/visit_recorder.dart';

import 'fake_card_api.dart';
import 'fake_recording_service.dart';
import 'fake_screen_awake.dart';
import 'fake_visit_recorder.dart';

const _recording = 'show:${RecordingNoticeText.recording}';
const _paused = 'show:${RecordingNoticeText.paused}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 대역의 비동기 처리가 끝날 때까지 기다린다.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('RecordingService', () {
    test('바뀔 때만 보내고, 멈춤은 알림 문구만 바꾸고, 내린 뒤에는 다시 내리지 않는다', () async {
      final platform = FakeRecordingServicePlatform();
      final service = RecordingService(platform);

      service.show(recording: true);
      service.show(recording: true);
      await flush();
      expect(platform.calls, [_recording, 'permission', _recording]);
      expect(platform.lastText, RecordingNoticeText.detail);
      expect(service.isShown, isTrue);

      platform.calls.clear();
      service.show(recording: false);
      service.show(recording: true);
      service.hide();
      service.hide();
      await flush();
      expect(platform.calls, [_paused, _recording, 'hide']);
      expect(service.isShown, isFalse);
    });

    test('녹음이 멈추면 소리와 진동이 나는 멈춤 알림으로 바꾸고, 이어 가면 되돌린다', () async {
      final platform = FakeRecordingServicePlatform(grantsPermission: false);
      final service = RecordingService(platform);

      service.show(recording: true);
      await flush();
      expect(platform.lastAlert, isFalse);

      platform.calls.clear();
      service.interrupted();
      service.interrupted();
      await flush();
      expect(platform.calls, ['show:${RecordingNoticeText.stopped}']);
      expect(platform.lastText, RecordingNoticeText.stoppedDetail);
      expect(platform.lastAlert, isTrue);
      expect(service.isShown, isTrue, reason: '파일은 열려 있어 서비스는 둔다');

      service.show(recording: true);
      await flush();
      expect(platform.calls.last, _recording);
      expect(platform.lastAlert, isFalse);
    });

    test('알림 권한은 처음 띄울 때 한 번만 묻는다', () async {
      final platform = FakeRecordingServicePlatform();
      final service = RecordingService(platform);

      service.show(recording: true);
      await flush();
      service.hide();
      service.show(recording: true);
      await flush();

      expect(platform.calls.where((c) => c == 'permission'), hasLength(1));
      expect(platform.calls, [
        _recording,
        'permission',
        _recording,
        'hide',
        _recording,
      ]);
    });

    test('서비스를 띄우는 요청이 닿은 뒤에 알림 권한을 묻는다', () async {
      final platform = FakeRecordingServicePlatform();
      final service = RecordingService(platform);

      service.show(recording: true);
      expect(platform.calls, [_recording], reason: '권한 창은 아직 띄우지 않는다');

      await flush();
      expect(platform.calls.take(2), [_recording, 'permission']);
    });

    test('권한을 받으면 그때의 상태로 알림을 다시 올리고, 거절하면 그대로 둔다', () async {
      final granted = FakeRecordingServicePlatform()
        ..pendingPermission = Completer<bool>();
      final service = RecordingService(granted);
      service.show(recording: true);
      await flush();
      service.show(recording: false);
      granted.pendingPermission!.complete(true);
      await flush();
      expect(granted.calls, [_recording, 'permission', _paused, _paused]);

      final denied = FakeRecordingServicePlatform(grantsPermission: false);
      RecordingService(denied).show(recording: true);
      await flush();
      expect(denied.calls, [_recording, 'permission']);
    });

    test('권한 창의 답이 오기 전에 내렸으면 다시 올리지 않는다', () async {
      final platform = FakeRecordingServicePlatform()
        ..pendingPermission = Completer<bool>();
      final service = RecordingService(platform);
      service.show(recording: true);
      await flush();
      service.hide();
      platform.pendingPermission!.complete(true);
      await flush();

      expect(platform.calls, [_recording, 'permission', 'hide']);
    });

    test('띄우지 못했으면 다음에 다시 띄워 본다', () async {
      final platform = FakeRecordingServicePlatform(refusesShow: true);
      final service = RecordingService(platform);

      service.show(recording: true);
      await flush();
      expect(service.isShown, isFalse);

      platform.refusesShow = false;
      service.show(recording: true);
      await flush();
      expect(service.isShown, isTrue);
      expect(platform.shownTitles, [
        RecordingNoticeText.recording,
        RecordingNoticeText.recording,
      ]);
    });

    test('정리하면 내리고 더는 띄우지 않는다', () async {
      final platform = FakeRecordingServicePlatform(grantsPermission: false);
      final service = RecordingService(platform);
      service.show(recording: true);
      await flush();

      service.dispose();
      service.show(recording: true);
      await flush();

      expect(platform.calls, [_recording, 'permission', 'hide']);
    });
  });

  group('MethodChannelRecordingService', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannelRecordingService.channel;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('MainActivity 와 같은 채널 이름과 메서드, 인자로 보낸다', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'hide' ? null : true;
      });
      const platform = MethodChannelRecordingService();

      expect(channel.name, 'app.saerok.android/recording_service');
      expect(await platform.show(title: '제목', text: '본문'), isTrue);
      await platform.hide();
      expect(await platform.requestNotificationPermission(), isTrue);

      expect(calls.map((c) => c.method), [
        'show',
        'hide',
        'requestNotificationPermission',
      ]);
      expect(calls.first.arguments, {
        'title': '제목',
        'text': '본문',
        'alert': false,
      });
    });

    test('받을 쪽이 없으면 띄울 것이 없는 것으로 보고 던지지 않는다', () async {
      const platform = MethodChannelRecordingService();
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException();
      });

      expect(await platform.show(title: '제목', text: '본문'), isTrue);
      await platform.hide();
      expect(await platform.requestNotificationPermission(), isTrue);
    });

    test('플랫폼이 거절하면 false 이고 던지지 않는다', () async {
      const platform = MethodChannelRecordingService();
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'FAILED');
      });

      expect(await platform.show(title: '제목', text: '본문'), isFalse);
      await platform.hide();
      expect(await platform.requestNotificationPermission(), isFalse);
    });
  });

  group('E-2 면회 녹음', () {
    /// 카드 한 장을 고른 회차를 만들고 녹음 화면을 띄운다. [start] 면 녹음을
    /// 시작한 뒤 띄운다.
    ///
    /// 시간 표시가 1초마다 다시 그려지므로 pumpAndSettle 을 쓰지 않는다.
    Future<(ProviderContainer, VisitController)> open(
      WidgetTester tester, {
      required FakeRecordingServicePlatform service,
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
          service.asOverride,
          FakeScreenAwakePlatform().asOverride,
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

    testWidgets('녹음 전 안내에서는 서비스를 띄우지 않는다', (tester) async {
      final service = FakeRecordingServicePlatform();
      await open(tester, service: service, start: false);

      expect(find.text('네, 좋아요'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('녹음을 시작하면 녹음 중 알림과 함께 띄우고 알림 권한을 묻는다', (tester) async {
      final service = FakeRecordingServicePlatform();
      final (container, visit) = await open(
        tester,
        service: service,
        start: false,
      );
      expect(service.calls, isEmpty);

      // 회차 만들기(5-1)가 실제 비동기로 돌아 화면을 누르지 않고 부른다.
      await tester.runAsync(visit.startRecording);
      await settle(tester);

      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(service.calls, [_recording, 'permission', _recording]);
      expect(service.lastText, RecordingNoticeText.detail);

      await leave(tester, container);
    });

    testWidgets('알림 권한을 거절해도 녹음과 서비스는 이어진다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final (container, _) = await open(tester, service: service);
      await settle(tester);

      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(service.calls, [_recording, 'permission']);
      expect(service.isShown, isTrue);

      await leave(tester, container);
    });

    testWidgets('잠시 멈추면 내리지 않고 알림만 바꾸고, 이어 가면 되돌린다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final (container, _) = await open(tester, service: service);
      expect(service.calls, [_recording, 'permission']);

      await tester.tap(find.byIcon(Icons.pause));
      await settle(tester);
      expect(find.text('잠시 멈췄어요'), findsOneWidget);
      expect(service.calls.last, _paused);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await settle(tester);
      expect(find.text('녹음 중이에요'), findsOneWidget);
      expect(service.calls, [_recording, 'permission', _paused, _recording]);
      expect(service.calls, isNot(contains('hide')));

      await leave(tester, container);
    });

    testWidgets('끝내기 확인 창을 보는 동안은 멈춤으로, 이어서 녹음을 고르면 녹음 중으로 바꾼다', (
      tester,
    ) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final (container, _) = await open(tester, service: service);

      await tester.tap(find.byIcon(Icons.stop));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.calls.last, _paused, reason: '창을 보는 동안 녹음은 멈춰 있다');

      // 창의 `이어서 녹음` 이다. 뒤 화면의 같은 이름 버튼은 녹음 중이라 없다.
      await tester.tap(find.text('이어서 녹음').last);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.calls, [_recording, 'permission', _paused, _recording]);

      await leave(tester, container);
    });

    testWidgets('녹음을 끝내면 파일을 닫은 뒤 내린다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final recorder = FakeVisitRecorder();
      bool? closedBeforeHide;
      service.onHide = () => closedBeforeHide = recorder.calls.contains('stop');
      final (container, visit) = await open(
        tester,
        service: service,
        recorder: recorder,
      );

      await visit.stopRecording(participantCount: 2);
      await settle(tester);

      expect(service.calls, [_recording, 'permission', 'hide']);
      expect(closedBeforeHide, isTrue);
      expect(service.isShown, isFalse);

      await leave(tester, container);
      expect(service.calls.last, 'hide', reason: '닫은 파일을 다시 닫지 않는다');
    });

    testWidgets('끝내기 없이 화면을 떠나도 파일을 닫은 뒤 내린다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final recorder = FakeVisitRecorder();
      bool? closedBeforeHide;
      service.onHide = () => closedBeforeHide = recorder.calls.contains('stop');
      final (container, _) = await open(
        tester,
        service: service,
        recorder: recorder,
      );

      await leave(tester, container);

      expect(service.calls, [_recording, 'permission', 'hide']);
      expect(closedBeforeHide, isTrue);
    });

    testWidgets('파일을 닫지 못해도 내린다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final (container, visit) = await open(
        tester,
        service: service,
        recorder: FakeVisitRecorder(failOnStop: true),
      );

      await visit.stopRecording(participantCount: 2);
      await settle(tester);

      expect(
        container.read(visitControllerProvider).value!.problem,
        VisitRecordingProblem.saveFailed,
      );
      expect(service.calls.last, 'hide');

      await leave(tester, container);
    });

    testWidgets('마이크 권한이 없으면 띄우지 않는다', (tester) async {
      final service = FakeRecordingServicePlatform();
      final (container, _) = await open(
        tester,
        service: service,
        recorder: FakeVisitRecorder(permitted: false),
        start: false,
      );

      await tester.tap(find.text('네, 좋아요'));
      await settle(tester);

      expect(
        container.read(visitControllerProvider).value!.problem,
        VisitRecordingProblem.permissionDenied,
      );
      expect(service.calls, isEmpty);
    });

    testWidgets('녹음 장치가 열리지 않으면 띄우지 않는다', (tester) async {
      final service = FakeRecordingServicePlatform();
      final (container, visit) = await open(
        tester,
        service: service,
        recorder: FakeVisitRecorder(failOnStart: true),
        start: false,
      );

      await tester.runAsync(visit.startRecording);
      await settle(tester);

      expect(
        container.read(visitControllerProvider).value!.problem,
        VisitRecordingProblem.startFailed,
      );
      expect(service.calls, isEmpty);
    });

    testWidgets('녹음 중에 면회 상태가 정리되면 내린다', (tester) async {
      final service = FakeRecordingServicePlatform(grantsPermission: false);
      final recorder = FakeVisitRecorder();
      // 화면 없이 면회 상태만 둔다. 화면이 떠나며 파일을 닫는 경우는 위에서 본다.
      final container = ProviderContainer(
        overrides: [
          visitRecorderProvider.overrideWithValue(recorder),
          service.asOverride,
          ...withMockCards,
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        final cards = await container.read(cardsControllerProvider.future);
        container
            .read(cardsControllerProvider.notifier)
            .toggleSelected(cards.cards.first.cardId);
        await container.read(visitControllerProvider.future);
        await container.read(visitControllerProvider.notifier).startRecording();
        await flush();
      });
      expect(service.isShown, isTrue);

      // 녹음 알림 관리자는 그대로 두고 면회 상태만 정리한다.
      container.invalidate(visitControllerProvider);
      await tester.runAsync(flush);

      expect(service.calls.last, 'hide');
      expect(recorder.calls, isNot(contains('stop')));
    });
  });
}
