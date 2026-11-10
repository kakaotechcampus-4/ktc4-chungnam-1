/// 마이크 권한이 꺼져 있을 때 휴대전화 설정의 새록 화면을 연다.
///
/// 보호자가 설정 메뉴를 혼자 찾지 않게 면회 시작(E-1)과 세부 정보 음성
/// 입력(B-3 ~ B-6)의 권한 안내에 `설정 열기` 를 둔다(UX 점검 2026-11-10 9번).
/// `record` 는 권한이 있는지만 알려 주고 설정을 열거나 안드로이드가 다시 묻지
/// 않는 상태를 알려 주지 않는다. 화면 켜짐(`screen_awake.dart`)처럼 플러그인을
/// 더하지 않고 `MainActivity` 의 MethodChannel 하나로 처리한다. 테스트는
/// [micSettingsPlatformProvider] 를 대역으로 바꾼다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 설정 화면 열기와 권한 상태 확인의 최소한의 약속이다.
abstract interface class MicSettingsPlatform {
  /// 휴대전화 설정의 새록 앱 정보 화면을 연다. 열지 못했으면 `false` 다.
  /// 던지지 않는다.
  Future<bool> openAppSettings();

  /// 마이크 권한이 없고 안드로이드가 권한 창을 더 띄우지 않는 상태인지.
  ///
  /// 한 번도 묻지 않았을 때와 구분하지 못하므로 권한을 물어 거부된 뒤에만
  /// 부른다. 권한을 켰거나 알 수 없으면 `false` 다. 던지지 않는다.
  Future<bool> isMicPermanentlyDenied();
}

/// `MainActivity` 의 MethodChannel 로 설정을 여는 실제 구현이다.
class MethodChannelMicSettings implements MicSettingsPlatform {
  const MethodChannelMicSettings();

  /// `MainActivity.kt` 의 채널 이름과 같아야 한다.
  static const channel = MethodChannel('app.saerok.android/mic_settings');

  /// `MainActivity.kt` 의 메서드 이름과 같아야 한다.
  static const openMethod = 'openAppSettings';
  static const permanentlyDeniedMethod = 'isMicPermanentlyDenied';

  @override
  Future<bool> openAppSettings() => _call(openMethod);

  @override
  Future<bool> isMicPermanentlyDenied() => _call(permanentlyDeniedMethod);

  Future<bool> _call(String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      // Android 가 아닌 곳(테스트, 다른 플랫폼)에는 받을 쪽이 없다.
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// 설정을 실제로 여는 곳이다. 테스트에서 갈아 끼운다.
final micSettingsPlatformProvider = Provider<MicSettingsPlatform>(
  (ref) => const MethodChannelMicSettings(),
);

/// 설정을 열지 못했을 때 아래 알림 띠로 알리는 문구.
const micSettingsOpenFailedNotice = '설정을 열지 못했어요.\n휴대전화 설정에서 새록을 찾아주세요.';

/// 새록의 앱 정보 화면을 연다. 열지 못하면 아래 알림 띠로 알린다.
///
/// 열지 못한 것을 조용히 넘기면 버튼이 고장 난 것처럼 보인다.
Future<void> openMicSettings(BuildContext context, WidgetRef ref) async {
  final opened = await ref.read(micSettingsPlatformProvider).openAppSettings();
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text(micSettingsOpenFailedNotice)));
}
