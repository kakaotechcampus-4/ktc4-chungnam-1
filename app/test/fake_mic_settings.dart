// 기기 없이 마이크 설정 열기를 확인하려고 쓰는 대역이다.
//
// 실제 설정 화면은 `MainActivity` 가 열므로 단위 테스트에서 볼 수 없다. 화면이
// 언제 설정을 열고 권한 상태를 묻는지만 여기에 남긴다.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saerok/app/mic_settings.dart';

class FakeMicSettingsPlatform implements MicSettingsPlatform {
  FakeMicSettingsPlatform({this.permanentlyDenied = false, this.opens = true});

  /// 안드로이드가 마이크 권한 창을 더 띄우지 않는 상태인지. 설정에서 켜고
  /// 돌아온 경우를 보려고 테스트 중에 바꾼다.
  bool permanentlyDenied;

  /// 설정 화면을 열 수 있는지.
  bool opens;

  /// 설정을 열려고 한 수.
  int opened = 0;

  /// 권한 상태를 물은 수.
  int checked = 0;

  @override
  Future<bool> openAppSettings() async {
    opened += 1;
    return opens;
  }

  @override
  Future<bool> isMicPermanentlyDenied() async {
    checked += 1;
    return permanentlyDenied;
  }

  /// 이 대역을 끼우는 override.
  Override get asOverride =>
      micSettingsPlatformProvider.overrideWithValue(this);
}
