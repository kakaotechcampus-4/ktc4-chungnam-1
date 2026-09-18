/// 로그인에 쓰는 provider 들이다.
///
/// 화면은 여기만 보고 서버나 구글 SDK 를 직접 부르지 않는다. 테스트는
/// [authApiProvider] 와 [googleAuthenticatorProvider] 를 override 한다
/// (`ADR-005`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_api.dart';
import 'google_authenticator.dart';

final authApiProvider = Provider<AuthApi>((ref) {
  final api = AuthApi();
  ref.onDispose(api.close);
  return api;
});

final googleAuthenticatorProvider = Provider<GoogleAuthenticator>(
  (ref) => GoogleSignInAuthenticator(),
);

/// 로그인한 뒤의 세션이다.
///
/// 앱이 도는 동안만 메모리에 둔다. 단말에 저장하지 않으므로 앱을 다시 켜면
/// 로그인부터 시작한다. 자동 재로그인은 `app/README.md` 의 "아직 붙이지 않은 것"
/// 에 남겨 두었다.
class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
    required this.account,
  });

  /// 서버 응답을 그대로 옮긴다. 만료 시각은 받은 시점에서 계산한다.
  factory AuthSession.fromResult(AuthenticatedResult result, {DateTime? now}) {
    return AuthSession(
      accessToken: result.accessToken,
      tokenType: result.tokenType,
      expiresAt: (now ?? DateTime.now()).add(
        Duration(seconds: result.expiresIn),
      ),
      account: result.account,
    );
  }

  /// `Authorization` 헤더에 쓴다. 로그와 화면에 내보내지 않는다.
  final String accessToken;

  final String tokenType;
  final DateTime expiresAt;
  final AuthAccount account;

  String get authorizationHeader => '$tokenType $accessToken';

  bool isExpired({DateTime? now}) => !(now ?? DateTime.now()).isBefore(
    expiresAt,
  );
}

class SessionNotifier extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  /// 로그인에 성공했다.
  void start(AuthenticatedResult result) =>
      state = AuthSession.fromResult(result);

  void clear() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, AuthSession?>(
  SessionNotifier.new,
);
