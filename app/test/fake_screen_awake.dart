// 기기 없이 화면 켜짐을 켜고 끄는 시점을 확인하려고 쓰는 대역이다.
//
// 실제 창 표시는 `MainActivity` 가 바꾸므로 단위 테스트에서 볼 수 없다. 화면이
// 언제 켜 두기와 놓기를 요청하는지만 여기에 남긴다.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saerok/app/screen_awake.dart';

class FakeScreenAwakePlatform implements ScreenAwakePlatform {
  FakeScreenAwakePlatform({this.fails = false});

  /// 창을 바꾸지 못하는 경우.
  bool fails;

  /// 받은 요청 순서다. `true` 는 켜 두기, `false` 는 놓기.
  final List<bool> calls = [];

  /// 마지막 요청대로라면 지금 화면이 켜져 있다.
  bool get isOn => calls.isNotEmpty && calls.last;

  @override
  Future<void> setKeepScreenOn(bool on) async {
    calls.add(on);
    if (fails) throw StateError('창을 바꾸지 못했다');
  }

  /// 이 대역을 끼우는 override.
  Override get asOverride =>
      screenAwakePlatformProvider.overrideWithValue(this);
}
