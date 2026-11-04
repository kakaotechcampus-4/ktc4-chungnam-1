/// 녹음하는 동안 화면이 저절로 꺼지지 않게 한다.
///
/// Android 창의 `FLAG_KEEP_SCREEN_ON` 을 켜고 끈다. 플러그인을 더하지 않고
/// `MainActivity` 의 MethodChannel 하나로 처리한다. 화면은 [KeepScreenOn]
/// 위젯으로 이 기능을 쓰고, 테스트는 [screenAwakePlatformProvider] 를 override
/// 해서 기기 없이 켜고 끄는 시점을 확인한다(`ADR-005` 의 주입 방식과 같다).
///
/// 화면이 켜져 있게만 한다. 앱이 백그라운드로 내려간 뒤에도 녹음을 이어 가게
/// 하지는 않는다. 그 일은 포그라운드 서비스가 맡아야 하며 아직 없다
/// (`app/README.md` 의 면회 녹음 참고).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 창의 화면 켜짐 표시를 바꾸는 최소한의 약속이다.
abstract interface class ScreenAwakePlatform {
  /// [on] 이면 화면이 저절로 꺼지지 않게 하고, 아니면 기기 설정을 따르게
  /// 되돌린다. 실패해도 던지지 않는다. 녹음은 화면 켜짐과 상관없이 이어져야
  /// 한다.
  ///
  /// 창에 반영했거나 반영할 창이 없으면 `true`, 창이 요청을 거절했으면
  /// `false` 다. [ScreenAwake] 는 `false` 를 받으면 같은 값을 나중에 다시
  /// 보낸다.
  Future<bool> setKeepScreenOn(bool on);
}

/// `MainActivity` 의 MethodChannel 로 창 표시를 바꾸는 실제 구현이다.
class MethodChannelScreenAwake implements ScreenAwakePlatform {
  const MethodChannelScreenAwake();

  /// `MainActivity.kt` 의 채널 이름과 같아야 한다.
  static const channel = MethodChannel('app.saerok.android/screen_awake');

  /// `MainActivity.kt` 의 메서드 이름과 같아야 한다.
  static const method = 'setKeepScreenOn';

  @override
  Future<bool> setKeepScreenOn(bool on) async {
    try {
      await channel.invokeMethod<void>(method, {'on': on});
      return true;
    } on MissingPluginException {
      // Android 가 아닌 곳(테스트, 다른 플랫폼)에는 받을 쪽이 없다. 다시
      // 보내도 같으므로 반영할 창이 없는 것으로 본다.
      return true;
    } on PlatformException {
      // 창을 바꾸지 못했다. 화면이 꺼질 수는 있어도 녹음은 막지 않는다.
      return false;
    }
  }
}

/// 화면 켜짐을 원하는 곳을 모아 하나라도 있으면 켜 둔다.
///
/// 면회 녹음과 세부 정보 음성 입력이 같은 창을 쓴다. 한쪽이 놓았다고 다른
/// 쪽이 아직 녹음 중인데 끄지 않도록, 원하는 곳([hold] 의 `holder`)을 세어
/// 모두 놓았을 때만 끈다.
///
/// 앱이 엔진에서 떨어지면(`AppLifecycleState.detached`) 원하는 곳이 남아
/// 있어도 끈다. 다시 붙어 앞으로 오면(`resumed`) 남은 곳이 있을 때 다시 켠다.
///
/// 창이 요청을 거절하거나 구현이 던지면 그 값을 보낸 적 없는 것으로 되돌린다.
/// 그래서 다음 [hold] 나 `resumed` 때 같은 값을 다시 보낸다.
class ScreenAwake with WidgetsBindingObserver {
  ScreenAwake(this._platform) {
    WidgetsBinding.instance.addObserver(this);
  }

  final ScreenAwakePlatform _platform;
  final Set<Object> _holders = {};

  /// 마지막으로 창에 보낸 값. 보낸 요청이 실패하면 그 전 값으로 되돌린다.
  bool _sent = false;

  /// 보낸 요청의 순번. 실패한 요청이 그 뒤에 보낸 요청의 [_sent] 를
  /// 되돌리지 않도록 가장 최근 요청인지 확인할 때 쓴다.
  int _generation = 0;

  /// 마지막으로 보낸 요청. 한 채널의 요청은 보낸 순서대로 닿으므로 따로
  /// 줄 세우지 않는다.
  Future<void> _last = Future.value();

  bool _disposed = false;

  /// 화면을 켜 두기를 원하는 곳이 있는지.
  bool get isHeld => _holders.isNotEmpty;

  /// [holder] 가 녹음을 시작했다. 같은 [holder] 로 여러 번 불러도 한 번이다.
  ///
  /// 이미 잡은 곳이 다시 불러도 앞선 켜기가 실패했으면 다시 보낸다.
  void hold(Object holder) {
    if (_disposed) return;
    _holders.add(holder);
    _sync();
  }

  /// [holder] 가 녹음을 마쳤거나 화면을 떠났다. 잡지 않았으면 아무것도 하지
  /// 않는다.
  void release(Object holder) {
    if (_holders.remove(holder)) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        _send(false);
      case AppLifecycleState.resumed:
        _sync();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        // 창이 보이지 않으면 표시는 아무 일도 하지 않는다. 그대로 둔다.
        break;
    }
  }

  /// 모두 놓고 창을 기기 설정으로 되돌린다.
  Future<void> dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _holders.clear();
    _send(false);
    return _last;
  }

  void _sync() => _send(_holders.isNotEmpty);

  void _send(bool on) {
    if (on == _sent) return;
    _sent = on;
    _last = _call(on, ++_generation);
  }

  Future<void> _call(bool on, int generation) async {
    var applied = false;
    try {
      applied = await _platform.setKeepScreenOn(on);
    } on Object {
      // 약속은 던지지 않는 것이지만, 구현이 던져도 다음 요청은 보낸다.
    }
    // 그 사이 다른 값을 보냈으면 그 요청이 [_sent] 를 맡는다.
    if (!applied && generation == _generation) _sent = !on;
  }
}

/// 창의 표시를 실제로 바꾸는 곳이다. 테스트에서 갈아 끼운다.
final screenAwakePlatformProvider = Provider<ScreenAwakePlatform>(
  (ref) => const MethodChannelScreenAwake(),
);

/// 화면들이 함께 쓰는 화면 켜짐 관리자다.
final screenAwakeProvider = Provider<ScreenAwake>((ref) {
  final awake = ScreenAwake(ref.watch(screenAwakePlatformProvider));
  ref.onDispose(awake.dispose);
  return awake;
});

/// [enabled] 인 동안 화면이 저절로 꺼지지 않게 한다.
///
/// [enabled] 가 `false` 로 바뀌거나 이 위젯이 화면에서 빠지면 바로 놓는다.
/// 녹음 끝내기, 취소와 화면 이탈을 따로 챙기지 않아도 녹음 상태만 넘기면
/// 된다.
class KeepScreenOn extends ConsumerStatefulWidget {
  const KeepScreenOn({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  ConsumerState<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends ConsumerState<KeepScreenOn> {
  /// [dispose] 안에서는 `ref` 를 읽을 수 없어 미리 받아 둔다.
  late final ScreenAwake _awake;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    if (widget.enabled) _awake.hold(this);
  }

  @override
  void didUpdateWidget(KeepScreenOn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    widget.enabled ? _awake.hold(this) : _awake.release(this);
  }

  @override
  void dispose() {
    _awake.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
