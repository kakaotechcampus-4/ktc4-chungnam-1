/// 플레이 스토어에 새 버전이 올라왔는지 확인하고 앱 안에서 받는다.
///
/// 구글 플레이의 앱 내 업데이트(유연한 업데이트)를 쓴다. 새 버전이 있으면 플레이가
/// 안내 창을 띄우고, 보호자가 받기로 하면 앱을 쓰는 동안 뒤에서 받는다. 다 받으면
/// [AppUpdateState.downloaded] 가 되고, 앱을 다시 시작해 설치한다.
///
/// 앱이 구버전이라 서버와 맞지 않아 보이는 실패가 나고 플레이에 새 버전이 있으면
/// [AppUpdateState.needed] 가 되어, 업데이트가 필요하다고 알린다.
///
/// 화면과 [AppUpdateController] 는 [AppUpdateGateway] 만 본다. 테스트는
/// [appUpdateGatewayProvider] 를 override 해서 플레이 없이 확인한다(`ADR-005` 의
/// 주입 방식과 같다).
///
/// 플레이에서 설치한 앱에서만 동작한다. `flutter run` 이나 직접 설치한 APK 에서는
/// 확인이 실패하며, 이때는 아무것도 띄우지 않는다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

/// 플레이가 알려 준 업데이트 상태다.
enum AppUpdateStatus {
  /// 받을 새 버전이 없거나, 지금은 앱 안에서 받을 수 없다.
  none,

  /// 새 버전이 있고 앱 안에서 받을 수 있다.
  available,

  /// 새 버전을 다 받아 두었다. 앱을 다시 시작하면 설치된다.
  downloaded,
}

/// 앱 내 업데이트를 다루는 최소한의 약속이다.
abstract interface class AppUpdateGateway {
  /// 새 버전이 있는지 묻는다. 확인하지 못하면 예외를 던진다.
  Future<AppUpdateStatus> check();

  /// 플레이의 안내 창을 띄우고, 보호자가 받기로 하면 뒤에서 받는다.
  ///
  /// 다 받으면 `true`, 보호자가 거절했거나 플레이가 진행하지 못하면 `false` 다.
  /// 받는 도중 실패하면 예외를 던진다. [check] 를 먼저 불러야 한다.
  Future<bool> download();

  /// 받아 둔 새 버전을 설치한다. 앱이 다시 시작되므로 결과가 돌아오지 않는다.
  Future<void> install();
}

/// 구글 플레이의 앱 내 업데이트 API 를 쓴다(`in_app_update`).
class PlayAppUpdateGateway implements AppUpdateGateway {
  const PlayAppUpdateGateway();

  @override
  Future<AppUpdateStatus> check() async {
    final info = await InAppUpdate.checkForUpdate();
    if (info.installStatus == InstallStatus.downloaded) {
      return AppUpdateStatus.downloaded;
    }
    if (info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.flexibleUpdateAllowed) {
      return AppUpdateStatus.available;
    }
    return AppUpdateStatus.none;
  }

  @override
  Future<bool> download() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return result == AppUpdateResult.success;
  }

  @override
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

/// 앱 내 업데이트가 없는 플랫폼이다. 늘 새 버전이 없다고 답한다.
class _NoAppUpdateGateway implements AppUpdateGateway {
  const _NoAppUpdateGateway();

  @override
  Future<AppUpdateStatus> check() async => AppUpdateStatus.none;

  @override
  Future<bool> download() async => false;

  @override
  Future<void> install() async {}
}

final appUpdateGatewayProvider = Provider<AppUpdateGateway>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const _NoAppUpdateGateway();
  }
  return const PlayAppUpdateGateway();
});

/// 앱 업데이트의 지금 상태다.
@immutable
class AppUpdateState {
  const AppUpdateState({
    this.newerVersion = false,
    this.downloaded = false,
    this.needed = false,
  });

  /// 플레이에 이 앱보다 새 버전이 있다. 받았는지와 상관없다.
  final bool newerVersion;

  /// 새 버전을 다 받아 두었다. 다시 시작하면 설치된다.
  final bool downloaded;

  /// 앱이 구버전이라 생겼을 수 있는 문제가 있었다. 업데이트가 필요하다고 알린다.
  final bool needed;

  AppUpdateState copyWith({
    bool? newerVersion,
    bool? downloaded,
    bool? needed,
  }) => AppUpdateState(
    newerVersion: newerVersion ?? this.newerVersion,
    downloaded: downloaded ?? this.downloaded,
    needed: needed ?? this.needed,
  );

  @override
  bool operator ==(Object other) =>
      other is AppUpdateState &&
      other.newerVersion == newerVersion &&
      other.downloaded == downloaded &&
      other.needed == needed;

  @override
  int get hashCode => Object.hash(newerVersion, downloaded, needed);
}

/// 새 버전이 있는지, 다 받았는지, 업데이트가 필요한지를 들고 있다.
///
/// 안내 창은 앱이 켜져 있는 동안 한 번만 저절로 띄운다. 보호자가 거절하면 앱을
/// 새로 켤 때까지 저절로 다시 묻지 않는다. 받는 도중 실패하면 다음 확인 때 다시
/// 묻는다. 업데이트가 필요하다는 안내에서 보호자가 직접 누르면 다시 묻는다.
class AppUpdateController extends Notifier<AppUpdateState> {
  /// 지금 하는 확인. 앱 시작, 복귀와 실패 신호가 겹쳐도 한 번만 묻는다.
  Future<void>? _checking;

  /// 이번 실행에서 안내 창을 저절로 띄웠는지.
  bool _asked = false;

  /// 지금 받는 중인지. 플레이의 받기를 겹쳐 시작하지 않는다.
  bool _downloading = false;

  /// 실패 신호를 보고 업데이트가 필요한지 따지는 중인지.
  bool _suspecting = false;

  AppUpdateGateway get _gateway => ref.read(appUpdateGatewayProvider);

  @override
  AppUpdateState build() => const AppUpdateState();

  /// 새 버전이 있는지 확인한다. 있으면 받기 시작하고, 이미 받아 두었으면
  /// [AppUpdateState.downloaded] 가 된다. 확인하지 못해도 앱 사용은 막지 않는다.
  ///
  /// [mayAsk] 가 `false` 면 새 버전이 있어도 안내 창을 띄우지 않고 다음 확인으로
  /// 미룬다. 면회 중에는 플레이의 안내 창이 화면을 가리지 않게 한다.
  Future<void> check({bool mayAsk = true}) =>
      _checking ??= _check(mayAsk).whenComplete(() => _checking = null);

  Future<void> _check(bool mayAsk) async {
    final status = await _status();
    switch (status) {
      case AppUpdateStatus.downloaded:
        state = state.copyWith(newerVersion: true, downloaded: true);
      case AppUpdateStatus.available:
        state = state.copyWith(newerVersion: true);
        if (mayAsk && !_asked) {
          _asked = true;
          unawaited(_download());
        }
      case AppUpdateStatus.none || null:
        break;
    }
  }

  /// 플레이에 묻는다. 확인하지 못하면 `null` 이다.
  Future<AppUpdateStatus?> _status() async {
    try {
      return await _gateway.check();
    } on MissingPluginException {
      // 플러그인이 없는 환경(위젯 테스트 등)이다.
      return null;
    } on Object catch (error) {
      _log('확인 실패', error);
      return null;
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    _downloading = true;
    try {
      if (await _gateway.download()) state = state.copyWith(downloaded: true);
    } on Object catch (error) {
      _asked = false;
      _log('받기 실패', error);
    } finally {
      _downloading = false;
    }
  }

  /// 보호자가 업데이트 안내에서 `업데이트` 를 눌렀다. 앞서 거절했어도 플레이의
  /// 안내 창을 다시 띄운다.
  Future<void> requestUpdate() async {
    if (_downloading) return;
    // 플레이는 마지막으로 확인한 정보로 안내 창을 띄우므로 먼저 다시 묻는다.
    await check(mayAsk: false);
    if (state.downloaded || !state.newerVersion) return;
    _asked = true;
    await _download();
  }

  /// 앱이 서버와 맞지 않아서 생겼을 수 있는 실패가 있었다(`ApiClient` 가 알린다).
  ///
  /// 플레이에 새 버전이 있을 때만 업데이트가 필요하다고 본다. 새 버전이 없으면
  /// 앱의 버그나 서버 문제일 수 있으므로 업데이트를 권하지 않는다. [certain] 이면
  /// 서버가 업데이트를 요구한 것이므로 새 버전을 확인하지 못해도 필요하다고 본다.
  Future<void> suspectOutdated({bool certain = false}) async {
    if (state.needed || _suspecting) return;
    _suspecting = true;
    try {
      // 실패는 화면을 만드는 도중에 알려질 수 있어, 한 박자 뒤에 상태를 바꾼다.
      await Future<void>.value();
      // 앱을 켠 뒤 새 버전이 올라왔을 수 있어 다시 묻는다.
      await check(mayAsk: false);
      if (certain || state.newerVersion) state = state.copyWith(needed: true);
    } finally {
      _suspecting = false;
    }
  }

  /// 받아 둔 새 버전을 설치한다. 앱이 곧 다시 시작된다.
  void install() {
    unawaited(
      _gateway.install().catchError((Object error) {
        _log('설치 실패', error);
      }),
    );
  }

  void _log(String what, Object error) {
    if (kDebugMode) debugPrint('[app-update] $what: $error');
  }
}

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );
