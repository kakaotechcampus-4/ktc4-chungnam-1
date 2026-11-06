/// 푸시 알림을 받을 이 기기를 FCM 에 등록하고 등록 ID 를 받는다.
///
/// 서버가 리포트 완료를 이 기기로 알리려면 이 기기의 등록 ID 가 필요하다. FCM 은
/// 예전의 기기 토큰(`getToken`) 대신 Firebase Installation ID(FID)를 쓰게 바꿨다.
/// 서버는 HTTP v1 발송의 `fid` 에 이 값을 넣는다. 화면과 provider 는
/// [PushMessaging] 만 보고 Firebase 를 직접 부르지 않는다. 테스트와 기본값은 아무것도
/// 하지 않는 [NoPushMessaging] 이고, 실제 앱만 `main.dart` 에서
/// [FirebasePushMessaging] 으로 바꾼다(ADR-005).
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class PushMessaging {
  /// 이 기기에서 푸시를 쓸 수 있는 구현인지. `false` 면 계정과 동의도 읽지 않는다.
  bool get enabled;

  /// 알림 표시 권한을 묻는다. 안드로이드 13 이상에서만 창이 뜬다.
  ///
  /// 허락했으면 `true` 다. 거절해도 등록은 되지만 알림이 보이지 않는다.
  Future<bool> requestPermission();

  /// FCM 에 이 기기를 등록한다. 등록 ID 는 [registrations] 로 온다.
  ///
  /// Firebase 설정이 없거나 등록하지 못하면 아무것도 오지 않는다.
  Future<void> register();

  /// 등록 ID(FID). 등록할 때와 앱을 켤 때의 동기화, ID 가 바뀔 때마다 온다.
  Stream<String> get registrations;

  /// 이 기기의 등록을 푼다. 서버가 이 ID 로 보내면 실패한다.
  Future<void> unregister();

  /// 앱이 꺼져 있을 때 리포트 완료 알림을 눌러 앱을 켰으면 그 회차 ID. 한 번만 준다.
  Future<String?> initialReportSession();

  /// 앱이 뒤에 있을 때 리포트 완료 알림을 누를 때마다 그 회차 ID 를 준다.
  Stream<String> get openedReportSessions;
}

/// 리포트 완료 알림(`data.type == reportReady`)이면 그 회차 ID. 아니면 `null` 이다.
///
/// 서버가 보내는 알림 형식은 `api-spec.md` 1-7 에 있다.
String? reportSessionOf(Map<String, dynamic> data) {
  if (data['type'] != 'reportReady') return null;
  final sessionId = data['sessionId'];
  return sessionId is String && sessionId.isNotEmpty ? sessionId : null;
}

/// 푸시를 쓰지 않는다. 테스트와 기본값이다.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  bool get enabled => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> register() async {}

  @override
  Stream<String> get registrations => const Stream.empty();

  @override
  Future<void> unregister() async {}

  @override
  Future<String?> initialReportSession() async => null;

  @override
  Stream<String> get openedReportSessions => const Stream.empty();
}

/// FCM 으로 등록한다.
///
/// Firebase 는 처음 쓸 때 초기화한다. 앱을 켜자마자 초기화하지 않는 것은 알림
/// 수신에 동의한 로그인 계정에서만 Firebase 와 통신하기 위해서다. 자동 등록도
/// `AndroidManifest.xml` 에서 꺼 두었다.
///
/// `android/app/google-services.json` 없이 빌드하면 초기화가 실패한다. 이때는
/// 오류를 던지지 않고 등록 없이 지낸다.
class FirebasePushMessaging implements PushMessaging {
  Future<bool>? _ready;

  @override
  bool get enabled => true;

  Future<bool> _initialized() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return true;
    } catch (error) {
      _log('Firebase 를 초기화하지 못했어요: ${error.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _initialized()) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (error) {
      _log('알림 권한을 묻지 못했어요: ${error.runtimeType}');
      return false;
    }
  }

  @override
  Future<void> register() async {
    if (!await _initialized()) return;
    try {
      await FirebaseMessaging.instance.register();
    } catch (error) {
      _log('FCM 에 등록하지 못했어요: ${error.runtimeType}');
    }
  }

  @override
  Stream<String> get registrations async* {
    if (!await _initialized()) return;
    yield* FirebaseMessaging.instance.onRegistered;
  }

  @override
  Future<void> unregister() async {
    if (!await _initialized()) return;
    try {
      await FirebaseMessaging.instance.unregister();
    } catch (error) {
      _log('FCM 등록을 풀지 못했어요: ${error.runtimeType}');
    }
  }

  @override
  Future<String?> initialReportSession() async {
    if (!await _initialized()) return null;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      return message == null ? null : reportSessionOf(message.data);
    } catch (error) {
      _log('알림으로 켠 앱의 알림을 읽지 못했어요: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Stream<String> get openedReportSessions async* {
    if (!await _initialized()) return;
    await for (final message in FirebaseMessaging.onMessageOpenedApp) {
      final sessionId = reportSessionOf(message.data);
      if (sessionId != null) yield sessionId;
    }
  }
}

void _log(String message) {
  if (kDebugMode) debugPrint('[push] $message');
}

final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => const NoPushMessaging(),
);
