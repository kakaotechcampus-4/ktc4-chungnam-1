/// 면회 녹음 파일이 열려 있는 동안 안드로이드 포그라운드 서비스와 알림을 띄운다.
///
/// 앱이 앞에 있을 때만 마이크를 쓸 수 있으므로, 서비스 없이는 보호자가 전원 버튼으로
/// 화면을 끄거나 다른 앱으로 옮기면 그 사이가 녹음되지 않을 수 있다. 마이크 유형의
/// 포그라운드 서비스가 떠 있으면 안드로이드가 마이크를 막지 않는다. 서비스는
/// `MainActivity` 의 MethodChannel 과 `RecordingService.kt` 가 맡고, 플러그인을 더하지
/// 않는다(`record` 7.1.1 에는 포그라운드 서비스가 없다).
///
/// `VisitController` 가 파일을 열면 [RecordingService.show] 로 띄우고, 잠시 멈추면
/// 알림 문구만 바꾸고, 보호자 모르게 녹음이 멈추면 [RecordingService.interrupted]
/// 로 크게 알리고, 파일을 닫으면 [RecordingService.hide] 로 내린다. 테스트는
/// [recordingServicePlatformProvider] 를 override 해서 기기 없이 띄우고 내리는 시점을
/// 확인한다(`ADR-005` 의 주입 방식과 같다).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 녹음 알림 문구. 앱의 녹음 화면(`녹음 중이에요`, `잠시 멈췄어요`)과 같은 말로 쓴다.
abstract final class RecordingNoticeText {
  static const recording = '면회를 녹음하고 있어요';
  static const paused = '면회 녹음을 잠시 멈췄어요';
  static const detail = '누르면 녹음 화면으로 돌아가요';

  /// 보호자가 멈추지 않았는데 녹음이 멈췄을 때. 소리와 진동이 나는 알림으로 바꾼다.
  static const stopped = '면회 녹음이 멈췄어요';
  static const stoppedDetail = '새록을 열어 녹음을 확인해주세요';
}

/// 알림이 보여 주는 녹음 상태다.
enum _Notice { recording, paused, stopped }

/// 포그라운드 서비스를 띄우고 내리는 최소한의 약속이다.
abstract interface class RecordingServicePlatform {
  /// 서비스를 띄우고 [title], [text] 로 알림을 보인다. 이미 떠 있으면 알림 문구만
  /// 바꾼다. 띄우기를 요청하지 못했으면 `false` 다. 던지지 않는다. 녹음은 서비스와
  /// 상관없이 앱이 앞에 있는 동안 이어져야 한다.
  ///
  /// [alert] 면 소리와 진동이 나고 화면 위에 잠깐 뜨는 알림 채널로 올린다. 녹음이
  /// 멈춰 녹음에 소리가 남지 않을 때만 쓴다.
  Future<bool> show({
    required String title,
    required String text,
    bool alert = false,
  });

  /// 서비스와 알림을 내린다. 떠 있지 않아도 괜찮다. 던지지 않는다.
  Future<void> hide();

  /// 알림이 보이도록 알림 권한을 묻는다(안드로이드 13 이상). 이미 있거나 필요 없으면
  /// 묻지 않고 `true` 다. 거절해도 서비스는 그대로 떠 있고 알림만 보이지 않는다.
  Future<bool> requestNotificationPermission();
}

/// `MainActivity` 의 MethodChannel 로 서비스를 다루는 실제 구현이다.
class MethodChannelRecordingService implements RecordingServicePlatform {
  const MethodChannelRecordingService();

  /// `MainActivity.kt` 의 채널 이름과 같아야 한다.
  static const channel = MethodChannel('app.saerok.android/recording_service');

  @override
  Future<bool> show({
    required String title,
    required String text,
    bool alert = false,
  }) async {
    try {
      return await channel.invokeMethod<bool>('show', {
            'title': title,
            'text': text,
            'alert': alert,
          }) ??
          false;
    } on MissingPluginException {
      // 안드로이드가 아닌 곳(테스트, 다른 플랫폼)에는 받을 쪽이 없다. 다시 보내도
      // 같으므로 띄울 것이 없는 것으로 본다.
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> hide() async {
    try {
      await channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // 받을 쪽이 없으면 띄운 것도 없다.
    } on PlatformException {
      // 내리지 못했다. 앱이 엔진을 놓을 때 `MainActivity` 가 다시 내린다.
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }
}

/// 면회 녹음 알림의 지금 상태를 들고, 바뀔 때만 플랫폼에 보낸다.
///
/// 한 채널의 요청은 보낸 순서대로 닿으므로 따로 줄 세우지 않는다(`ScreenAwake` 와
/// 같다). 서비스를 띄우지 못했으면 보낸 적 없는 것으로 되돌려, 다음 [show] 때 다시
/// 띄워 본다.
class RecordingService {
  RecordingService(this._platform);

  final RecordingServicePlatform _platform;

  /// 마지막으로 보낸 상태. `null` 이면 내려 있다.
  _Notice? _notice;

  /// 보낸 요청의 순번. 늦게 끝난 실패가 그 뒤에 보낸 요청의 상태를 되돌리지 않게 한다.
  int _generation = 0;

  /// 이번 실행에서 알림 권한을 물었는지. 처음 띄울 때 한 번만 묻는다.
  bool _askedPermission = false;

  bool _disposed = false;

  /// 서비스를 띄워 둔 상태인지.
  bool get isShown => _notice != null;

  /// 녹음 파일이 열려 있다. [recording] 이 아니면 잠시 멈춘 것이다.
  ///
  /// 처음 띄울 때는 알림이 보이도록 알림 권한을 묻는다. 서비스를 띄우는 요청이
  /// 닿은 뒤에 묻는다. 권한 창이 앱을 가린 뒤에는 서비스를 띄우지 못할 수 있어서다.
  /// 묻는 동안에도 녹음과 서비스는 이어진다. 권한을 받으면 알림을 다시 올린다. 권한
  /// 없이 올린 알림은 받은 뒤에도 보이지 않기 때문이다.
  void show({required bool recording}) =>
      _set(recording ? _Notice.recording : _Notice.paused);

  /// 보호자가 멈추지 않았는데 녹음이 멈췄다. 파일은 열려 있으므로 서비스는 두고,
  /// 알림을 소리와 진동이 나는 `면회 녹음이 멈췄어요` 로 바꿔 앱을 열게 한다.
  /// 화면을 끄거나 다른 앱에 있어도 알아채게 하려는 것이다.
  void interrupted() => _set(_Notice.stopped);

  void _set(_Notice notice) {
    if (_disposed || _notice == notice) return;
    final first = _notice == null;
    _notice = notice;
    final sent = _show(notice, ++_generation);
    if (first && !_askedPermission) {
      _askedPermission = true;
      unawaited(sent.then((_) => _askPermission()));
    } else {
      unawaited(sent);
    }
  }

  /// 녹음 파일을 닫았거나 면회가 끝났다. 띄우지 않았으면 아무것도 하지 않는다.
  void hide() {
    if (_notice == null) return;
    _notice = null;
    _generation++;
    unawaited(_hide());
  }

  /// 내리고 더는 띄우지 않는다.
  void dispose() {
    hide();
    _disposed = true;
  }

  Future<void> _show(_Notice notice, int generation) async {
    var shown = false;
    try {
      shown = await _platform.show(
        title: switch (notice) {
          _Notice.recording => RecordingNoticeText.recording,
          _Notice.paused => RecordingNoticeText.paused,
          _Notice.stopped => RecordingNoticeText.stopped,
        },
        text: notice == _Notice.stopped
            ? RecordingNoticeText.stoppedDetail
            : RecordingNoticeText.detail,
        alert: notice == _Notice.stopped,
      );
    } on Object {
      // 약속은 던지지 않는 것이지만, 구현이 던져도 녹음은 이어 간다.
    }
    if (!shown && generation == _generation) _notice = null;
  }

  Future<void> _hide() async {
    try {
      await _platform.hide();
    } on Object {
      // 내리지 못해도 앱이 엔진을 놓을 때 `MainActivity` 가 다시 내린다.
    }
  }

  Future<void> _askPermission() async {
    var granted = false;
    try {
      granted = await _platform.requestNotificationPermission();
    } on Object {
      return;
    }
    final notice = _notice;
    if (!granted || notice == null || _disposed) return;
    await _show(notice, ++_generation);
  }
}

/// 서비스를 실제로 띄우는 곳이다. 테스트에서 갈아 끼운다.
final recordingServicePlatformProvider = Provider<RecordingServicePlatform>(
  (ref) => const MethodChannelRecordingService(),
);

/// 면회 녹음이 함께 쓰는 녹음 알림 관리자다.
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService(ref.watch(recordingServicePlatformProvider));
  ref.onDispose(service.dispose);
  return service;
});
