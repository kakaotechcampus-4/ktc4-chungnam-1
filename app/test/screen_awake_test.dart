// 녹음 중 화면 켜짐을 켜고 끄는 규칙을 확인한다.
//
// 실제 창 표시(`FLAG_KEEP_SCREEN_ON`)는 `MainActivity` 가 바꾸므로 여기서는
// Dart 쪽이 언제 무엇을 요청하는지와 채널 약속만 본다. 실기기에서 화면이 정말
// 꺼지지 않는지는 이 테스트로 확인하지 않는다.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/screen_awake.dart';

import 'fake_screen_awake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 대역의 비동기 처리가 끝날 때까지 기다린다.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ScreenAwake', () {
    test('처음 잡을 때 켜고 마지막으로 놓을 때 끈다', () async {
      final platform = FakeScreenAwakePlatform();
      final awake = ScreenAwake(platform);
      addTearDown(awake.dispose);
      final visit = Object();
      final speech = Object();

      awake.hold(visit);
      awake.hold(visit);
      await settle();
      expect(platform.calls, [true], reason: '같은 곳이 두 번 잡아도 한 번이다');

      awake.hold(speech);
      awake.release(visit);
      await settle();
      expect(platform.calls, [true], reason: '아직 녹음 중인 곳이 있으면 끄지 않는다');

      awake.release(speech);
      await settle();
      expect(platform.calls, [true, false]);
      expect(awake.isHeld, isFalse);
    });

    test('잡지 않은 곳이 놓아도 아무것도 보내지 않는다', () async {
      final platform = FakeScreenAwakePlatform();
      final awake = ScreenAwake(platform);
      addTearDown(awake.dispose);

      awake.release(Object());
      await settle();

      expect(platform.calls, isEmpty);
    });

    test('앱이 엔진에서 떨어지면 끄고 다시 앞으로 오면 되살린다', () async {
      final platform = FakeScreenAwakePlatform();
      final awake = ScreenAwake(platform);
      addTearDown(awake.dispose);

      awake.hold(Object());
      awake.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      expect(platform.calls, [true], reason: '안 보이는 동안은 그대로 둔다');

      awake.didChangeAppLifecycleState(AppLifecycleState.detached);
      await settle();
      expect(platform.calls, [true, false]);

      awake.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(platform.calls, [true, false, true]);
    });

    test('놓은 뒤 앞으로 와도 다시 켜지 않는다', () async {
      final platform = FakeScreenAwakePlatform();
      final awake = ScreenAwake(platform);
      addTearDown(awake.dispose);
      final holder = Object();

      awake.hold(holder);
      awake.release(holder);
      awake.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(platform.calls, [true, false]);
    });

    test('정리하면 잡은 곳이 남아 있어도 끄고, 그 뒤 잡기는 무시한다', () async {
      final platform = FakeScreenAwakePlatform();
      final awake = ScreenAwake(platform);

      awake.hold(Object());
      await awake.dispose();
      awake.hold(Object());
      await settle();

      expect(platform.calls, [true, false]);
    });

    test('창을 바꾸지 못해도 다음 요청은 보낸다', () async {
      final platform = FakeScreenAwakePlatform(fails: true);
      final awake = ScreenAwake(platform);
      addTearDown(awake.dispose);
      final holder = Object();

      awake.hold(holder);
      awake.release(holder);
      await settle();

      expect(platform.calls, [true, false]);
    });
  });

  group('MethodChannelScreenAwake', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannelScreenAwake.channel;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('MainActivity 와 같은 채널과 이름으로 켜고 끈다', () async {
      final received = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        received.add(call);
        return null;
      });

      const platform = MethodChannelScreenAwake();
      await platform.setKeepScreenOn(true);
      await platform.setKeepScreenOn(false);

      expect(channel.name, 'app.saerok.android/screen_awake');
      expect(received.map((c) => c.method), [
        'setKeepScreenOn',
        'setKeepScreenOn',
      ]);
      expect(received.map((c) => c.arguments), [
        {'on': true},
        {'on': false},
      ]);
    });

    test('받을 쪽이 없거나 실패해도 던지지 않는다', () async {
      const platform = MethodChannelScreenAwake();
      await expectLater(platform.setKeepScreenOn(true), completes);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'FAILED');
      });
      await expectLater(platform.setKeepScreenOn(true), completes);
    });
  });

  group('KeepScreenOn', () {
    Widget wrap(FakeScreenAwakePlatform platform, Widget child) =>
        ProviderScope(
          overrides: [platform.asOverride],
          child: Directionality(textDirection: TextDirection.ltr, child: child),
        );

    testWidgets('켜기 값을 따라 잡고 놓으며, 빠지면 놓는다', (tester) async {
      final platform = FakeScreenAwakePlatform();

      await tester.pumpWidget(
        wrap(platform, const KeepScreenOn(enabled: false, child: SizedBox())),
      );
      expect(platform.calls, isEmpty);

      await tester.pumpWidget(
        wrap(platform, const KeepScreenOn(enabled: true, child: SizedBox())),
      );
      await tester.pump();
      expect(platform.calls, [true]);

      await tester.pumpWidget(
        wrap(platform, const KeepScreenOn(enabled: false, child: SizedBox())),
      );
      await tester.pump();
      expect(platform.calls, [true, false]);

      await tester.pumpWidget(
        wrap(platform, const KeepScreenOn(enabled: true, child: SizedBox())),
      );
      await tester.pump();
      await tester.pumpWidget(wrap(platform, const SizedBox()));
      await tester.pump();
      expect(platform.calls, [true, false, true, false]);
    });

    testWidgets('켠 채로 들어와도 바로 잡는다', (tester) async {
      final platform = FakeScreenAwakePlatform();

      await tester.pumpWidget(
        wrap(platform, const KeepScreenOn(enabled: true, child: SizedBox())),
      );
      await tester.pump();

      expect(platform.isOn, isTrue);
    });
  });
}
