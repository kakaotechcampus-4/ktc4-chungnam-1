/// 세션을 단말에 보관한다.
///
/// 앱을 다시 켰을 때 로그인 화면부터 시작하지 않도록 세션을 남긴다(PR #50
/// 리뷰). 화면과 테스트는 [SessionStore] 만 보고 저장소를 직접 부르지 않는다
/// (`ADR-005` 의 주입 방식과 같다).
///
/// 보관하는 값은 접근 토큰과 만료 시각, 계정 정보다. 구글 ID 토큰과 등록
/// 토큰은 그때만 쓰고 보관하지 않는다. 저장한 값은 로그에 남기지 않는다
/// (`CLAUDE.md`).
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/auth_api.dart';
import 'auth_session.dart';

abstract interface class SessionStore {
  /// 보관한 세션을 읽는다. 없거나 읽을 수 없으면 `null` 이다.
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  /// 로그아웃과 세션 폐기에 쓴다.
  Future<void> clear();
}

/// 단말의 보안 저장소에 둔다.
///
/// 안드로이드는 키스토어로 감싼 AES-GCM(`flutter_secure_storage` 11 의 기본),
/// iOS 는 키체인이다. 평문 `SharedPreferences` 에 두지 않는다.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // 단말을 한 번 연 뒤부터 읽을 수 있고 다른 기기로 넘어가지 않는다.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _key = 'saerok.auth.session';

  @override
  Future<AuthSession?> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      // 저장소를 열지 못하는 단말이 있다. 로그인부터 시작하면 되는 일이라
      // 앱을 멈추지 않는다.
      return null;
    }
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AuthSession.fromJson(decoded);
    } on FormatException {
      // 저장 형태가 바뀌었거나 값이 깨졌다. 지우고 로그인부터 시작한다.
      await clear();
      return null;
    } on AuthFailure {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } catch (_) {
      // 보관하지 못해도 이번 로그인은 그대로 쓴다. 다음 실행에서 다시
      // 로그인하면 된다.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // 지우지 못한 경우다. 남은 값은 다음 읽기에서 유효성을 확인한다.
    }
  }
}
