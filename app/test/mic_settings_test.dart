// 마이크 설정 열기 채널이 `MainActivity` 와 같은 이름을 쓰고, 받을 쪽이 없거나
// 실패해도 던지지 않는지 확인한다. 실제 설정 화면과 권한 상태는 기기에서 본다.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saerok/app/mic_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannelMicSettings.channel;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('MainActivity 와 같은 채널과 이름으로 묻고 답을 그대로 돌려준다', () async {
    final received = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      received.add(call.method);
      return call.method == 'openAppSettings';
    });

    const platform = MethodChannelMicSettings();

    expect(channel.name, 'app.saerok.android/mic_settings');
    expect(await platform.openAppSettings(), isTrue);
    expect(await platform.isMicPermanentlyDenied(), isFalse);
    expect(received, ['openAppSettings', 'isMicPermanentlyDenied']);
  });

  test('받을 쪽이 없거나 실패하면 던지지 않고 false 로 알린다', () async {
    const platform = MethodChannelMicSettings();

    messenger.setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    expect(await platform.openAppSettings(), isFalse);
    expect(await platform.isMicPermanentlyDenied(), isFalse);

    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'FAILED');
    });
    expect(await platform.openAppSettings(), isFalse);
    expect(await platform.isMicPermanentlyDenied(), isFalse);

    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await platform.openAppSettings(), isFalse, reason: '답이 없으면 못 연 것');
  });
}
