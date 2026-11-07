/// 리포트 완료 푸시를 받도록 이 기기를 언제 등록하고 언제 등록을 풀지 정한다.
///
/// 로그인한 계정이 알림 수신(선택 동의)에 동의했을 때만 알림 권한을 묻고 FCM 에
/// 등록해 등록 ID(FID)를 받는다. 받은 ID 는 서버에 등록한다(1-7). 로그아웃 직전에
/// 서버의 등록을 지우고(1-8), 로그아웃하거나 동의를 거두면 FCM 등록도 푼다. 동의를
/// 거두면 서버가 1-6 에서 등록을 지우므로 따로 부르지 않는다(app/README.md "푸시 알림").
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/providers.dart';
import '../../data/push_device_api.dart';
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
  StreamSubscription<String>? _openedReports;
  bool _wanted = false;
  bool _permissionAsked = false;
  bool _initialMessageChecked = false;

  /// 등록을 요청한 뒤 아직 풀지 않았는지. ID 를 받기 전에 로그아웃해도 등록을 푼다.
  bool _registered = false;

  /// 등록과 등록 풀기가 겹치면 마지막 것만 이어간다.
  int _turn = 0;

  @override
  String? build() {
    ref.onDispose(() {
      _registrations?.cancel();
      _openedReports?.cancel();
    });
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
      unawaited(_upload(id));
    });
    // 로그인한 동안에만 알림을 눌러 리포트를 연다.
    _openedReports ??= messaging.openedReportSessions.listen(_openReport);
    _registered = true;
    // 자동 등록을 꺼 두어 앱을 켤 때마다 직접 등록해야 ID 가 새로 동기화된다.
    await messaging.register();
    if (!_initialMessageChecked && ref.mounted && turn == _turn) {
      // 앱이 꺼져 있을 때 알림을 눌러 켰다. 한 번만 읽는다.
      _initialMessageChecked = true;
      final sessionId = await messaging.initialReportSession();
      if (sessionId != null) _openReport(sessionId);
    }
  }

  /// 서버에 이 기기를 등록한다(1-7). 앱을 켤 때마다 다시 보내 등록 시각을 새로 한다.
  ///
  /// 실패해도 다시 시도하지 않는다. 다음에 앱을 켜면 다시 보낸다.
  Future<void> _upload(String id) async {
    try {
      await ref.read(pushDeviceApiProvider).register(id);
    } on ApiFailure catch (failure) {
      if (kDebugMode) {
        debugPrint('[push] 서버에 등록하지 못했어요: ${failure.runtimeType}');
      }
    }
  }

  void _openReport(String sessionId) {
    if (!ref.mounted || !_wanted) return;
    ref.read(pendingReportOpenProvider.notifier).request(sessionId);
  }

  /// 로그아웃 직전, 세션이 남아 있을 때 부른다. 서버의 이 기기 등록을 지운다(1-8).
  ///
  /// 로그아웃은 오프라인에서도 되어야 하므로 짧게만 기다리고 실패는 넘긴다. 지우지
  /// 못한 서버 등록은 FCM 등록을 푼 뒤 발송이 `UNREGISTERED` 로 실패할 때 서버가
  /// 지우고, 같은 기기에서 다른 계정이 등록하면 그 계정으로 옮겨진다.
  Future<void> releaseForSignOut() async {
    final id = state;
    if (id == null) return;
    try {
      await ref
          .read(pushDeviceApiProvider)
          .unregister(id)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[push] 서버 등록을 지우지 못했어요: ${error.runtimeType}');
      }
    }
  }

  Future<void> _stop() async {
    final registrations = _registrations;
    final openedReports = _openedReports;
    _registrations = null;
    _openedReports = null;
    // 구독 해제가 끝나기를 기다리지 않는다. 알림 열기 스트림(onMessageOpenedApp)의
    // 해제는 끝나지 않아, 기다리면 아래 상태 정리와 FCM 등록 풀기에 닿지 못한다
    // (2026-11-08 Galaxy S22 디버그 로그로 확인).
    unawaited(registrations?.cancel());
    unawaited(openedReports?.cancel());
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

/// 리포트 완료 알림을 눌러 열어야 할 회차 ID. 홈에 도착하면 `main.dart` 가 연다.
///
/// 알림으로 앱을 켜면 스플래시가 세션을 확인한 뒤 홈으로 옮기므로 바로 열면 덮인다.
/// 녹음처럼 다른 화면에 있을 때도 끊지 않고 홈으로 돌아오면 연다.
class PendingReportOpen extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String sessionId) => state = sessionId;

  /// 열 회차 ID 를 꺼내고 비운다.
  String? take() {
    final sessionId = state;
    state = null;
    return sessionId;
  }
}

final pendingReportOpenProvider = NotifierProvider<PendingReportOpen, String?>(
  PendingReportOpen.new,
);
