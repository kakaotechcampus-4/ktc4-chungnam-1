/// 리포트 완료 푸시를 받도록 이 기기를 언제 등록하고 언제 등록을 풀지 정한다.
///
/// 로그인한 계정이 알림 수신(선택 동의)에 동의했을 때만 알림 권한을 묻고 FCM 에
/// 등록해 등록 ID(FID)를 받는다. 로그아웃하거나 동의를 거두면 등록을 푼다. 받은
/// ID 를 서버에 넘기는 일은 BE 의 기기 등록 API 가 정해진 뒤 여기에 붙인다
/// (app/README.md "푸시 알림").
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../auth/auth_providers.dart';
import 'push_messaging.dart';

/// 이 기기를 푸시에 등록해 둘지. 아직 모르면 `null` 이다.
///
/// 계정을 처음 읽는 중이거나 읽지 못했으면 모르는 것으로 둔다. 연결이 잠깐 끊겼다고
/// 등록을 풀지 않기 위해서다. 다른 계정의 동의를 보지 않도록 계정 ID 가 세션과
/// 같을 때만 동의를 읽는다.
final pushWantedProvider = Provider<bool?>((ref) {
  if (!ref.watch(pushMessagingProvider.select((m) => m.enabled))) return false;
  final accountId = ref.watch(
    sessionProvider.select((s) => s?.account.accountId),
  );
  if (accountId == null) return false;
  final account = ref.watch(accountProvider).value;
  if (account == null || account.accountId != accountId) return null;
  return account.consent['pushNotification']?.granted ?? false;
});

/// 이 기기의 등록 ID(FID). 등록하지 않았거나 등록을 풀었으면 `null` 이다.
class PushRegistrationController extends Notifier<String?> {
  StreamSubscription<String>? _registrations;
  bool _wanted = false;
  bool _permissionAsked = false;

  /// 등록을 요청한 뒤 아직 풀지 않았는지. ID 를 받기 전에 로그아웃해도 등록을 푼다.
  bool _registered = false;

  /// 등록과 등록 풀기가 겹치면 마지막 것만 이어간다.
  int _turn = 0;

  @override
  String? build() {
    ref.onDispose(() => _registrations?.cancel());
    ref.listen<bool?>(pushWantedProvider, (_, wanted) {
      if (wanted == null || wanted == _wanted) return;
      _wanted = wanted;
      final turn = ++_turn;
      // build 안에서 state 를 바꾸지 않도록 다음 차례에 시작한다.
      Future.microtask(() => wanted ? _start(turn) : _stop());
    }, fireImmediately: true);
    return null;
  }

  Future<void> _start(int turn) async {
    final messaging = ref.read(pushMessagingProvider);
    // 앱을 켤 때마다 한 번만 묻는다. 두 번 거절하면 안드로이드가 더 묻지 않는다.
    if (!_permissionAsked) {
      _permissionAsked = true;
      await messaging.requestPermission();
    }
    if (!ref.mounted || turn != _turn) return;
    // 등록 결과를 놓치지 않도록 먼저 듣는다.
    _registrations ??= messaging.registrations.listen((id) {
      if (!ref.mounted || !_wanted) return;
      if (state == id) return;
      state = id;
      // 디버그 빌드에서만 남긴다. Firebase 콘솔의 테스트 메시지로 이 기기에 알림이
      // 오는지 확인할 때 쓴다. 릴리스 빌드의 로그에는 남기지 않는다.
      if (kDebugMode) debugPrint('[push] 등록 ID: $id');
    });
    _registered = true;
    // 자동 등록을 꺼 두어 앱을 켤 때마다 직접 등록해야 ID 가 새로 동기화된다.
    await messaging.register();
  }

  Future<void> _stop() async {
    final registrations = _registrations;
    _registrations = null;
    await registrations?.cancel();
    if (!ref.mounted) return;
    state = null;
    if (!_registered) return;
    _registered = false;
    await ref.read(pushMessagingProvider).unregister();
    if (kDebugMode) debugPrint('[push] 등록을 풀었어요');
  }
}

final pushRegistrationProvider =
    NotifierProvider<PushRegistrationController, String?>(
      PushRegistrationController.new,
    );
