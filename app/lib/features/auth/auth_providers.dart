/// 로그인에 쓰는 provider 들이다.
///
/// 화면은 여기만 보고 서버나 구글 SDK, 단말 저장소를 직접 부르지 않는다.
/// 테스트는 [authApiProvider], [googleAuthenticatorProvider] 와
/// [sessionStoreProvider] 를 override 한다(`ADR-005`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_api.dart';
import 'auth_messages.dart';
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

/// 구글 로그인 설정이 없을 때 로그인 버튼을 누르면 바로 환자 정보 입력으로 넘길지.
///
/// **임시 장치다.** 목 로그인을 지운 뒤로, BE 의 구글 클라이언트 ID 와 SHA-1 등록이
/// 준비되기 전에는 로그인 다음 화면을 확인할 길이 없어 둔다. 디버그 빌드에서
/// `SAEROK_GOOGLE_SERVER_CLIENT_ID` 가 비어 있을 때만 켜지고 릴리스 빌드에서는
/// 늘 꺼진다. 서버 세션을 만들지 않으므로 로그아웃과 탈퇴는 동작하지 않는다.
/// 구글 로그인 설정이 준비되면 지운다.
final skipGoogleLoginProvider = Provider<bool>(
  (ref) => kDebugMode && googleServerClientId.isEmpty,
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

  /// 로그아웃이다. 보관한 세션을 지우고 서버에서도 폐기한다.
  ///
  /// 구글 쪽도 함께 풀어 다음 로그인에서 계정을 다시 고를 수 있게 한다.
  /// 저장소를 먼저 비워, 중간에 실패해도 세션이 남지 않게 한다.
  ///
  /// 서버 폐기는 실패해도 로그아웃을 막지 않는다. 오프라인에서도 로그아웃은
  /// 되어야 하고, 단말에서 지운 세션은 다시 쓰일 일이 없다. 서버가 받지 못한
  /// 세션은 만료(기본 1시간)까지 서버에서만 유효하다.
  Future<void> signOut() async {
    final session = state;
    state = null;
    await ref.read(sessionStoreProvider).clear();
    if (session != null) {
      try {
        await ref.read(authApiProvider).logout(session.authorizationHeader);
      } on AuthFailure catch (failure) {
        logAuthFailure(failure);
      }
    }
    await _signOutOfGoogle();
  }

  /// 회원 탈퇴다. 서버가 계정을 지운 것을 확인한 뒤에만 단말 세션을 지운다.
  ///
  /// 서버가 거절하거나 닿지 못하면 [AuthFailure] 를 그대로 던지고 세션을
  /// 남긴다. 지워지지 않았는데 로그아웃된 것처럼 보이면 사용자는 탈퇴됐다고
  /// 믿게 된다.
  ///
  /// 세션 없이 부르면 [StateError] 다. 화면이 먼저 확인한다.
  Future<void> deleteAccount() async {
    final session = state;
    if (session == null) {
      throw StateError('세션 없이 탈퇴를 부를 수 없다');
    }
    await ref.read(authApiProvider).deleteAccount(session.authorizationHeader);

    state = null;
    await ref.read(sessionStoreProvider).clear();
    await _signOutOfGoogle();
  }

  /// 세션을 버린다. 서버가 거절했거나 되살릴 수 없을 때다.
  Future<void> discard() async {
    state = null;
    await ref.read(sessionStoreProvider).clear();
  }

  /// 단말 세션을 지운 뒤에 부른다. 여기서 실패해도 로그아웃이나 탈퇴를 되돌리지
  /// 않는다. 다음 로그인의 계정 고르기 창에 같은 계정이 먼저 보일 뿐이다.
  Future<void> _signOutOfGoogle() async {
    try {
      await ref.read(googleAuthenticatorProvider).signOut();
    } catch (error) {
      if (kDebugMode) debugPrint('[auth] 구글 로그아웃 실패: ${error.runtimeType}');
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AuthSession?>(
  SessionNotifier.new,
);
