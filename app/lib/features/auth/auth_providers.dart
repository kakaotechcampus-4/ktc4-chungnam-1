/// 로그인에 쓰는 provider 들이다.
///
/// 화면은 여기만 보고 서버나 구글 SDK, 단말 저장소를 직접 부르지 않는다.
/// 테스트는 [authApiProvider], [googleAuthenticatorProvider] 와
/// [sessionStoreProvider] 를 override 한다(`ADR-005`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_api.dart';
import 'auth_session.dart';
import 'google_authenticator.dart';
import 'session_store.dart';

final authApiProvider = Provider<AuthApi>((ref) {
  final api = AuthApi();
  ref.onDispose(api.close);
  return api;
});

final googleAuthenticatorProvider = Provider<GoogleAuthenticator>(
  (ref) => GoogleSignInAuthenticator(),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

class SessionNotifier extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  /// 로그인에 성공했다. 앱을 다시 켜도 이어지도록 보관한다.
  Future<void> start(AuthenticatedResult result) async {
    final session = AuthSession.fromResult(result);
    state = session;
    await ref.read(sessionStoreProvider).write(session);
  }

  /// 보관해 둔 세션을 되살렸다. 이미 저장소에서 읽은 값이라 다시 쓰지 않는다.
  void restore(AuthSession session) => state = session;

  /// 로그아웃이다. 보관한 세션을 지운다.
  ///
  /// 구글 쪽도 함께 풀어 다음 로그인에서 계정을 다시 고를 수 있게 한다.
  /// 저장소를 먼저 비워, 중간에 실패해도 세션이 남지 않게 한다.
  Future<void> signOut() async {
    state = null;
    await ref.read(sessionStoreProvider).clear();
    await ref.read(googleAuthenticatorProvider).signOut();
  }

  /// 세션을 버린다. 서버가 거절했거나 되살릴 수 없을 때다.
  Future<void> discard() async {
    state = null;
    await ref.read(sessionStoreProvider).clear();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AuthSession?>(
  SessionNotifier.new,
);
