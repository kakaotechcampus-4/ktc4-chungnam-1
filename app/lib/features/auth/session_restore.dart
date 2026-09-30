/// 앱을 다시 켤 때 보관해 둔 세션을 되살린다.
///
/// 스플래시가 부르는 자리다. 앱을 켤 때마다 로그인 버튼을 누르지 않아도 되게
/// 하고, 토큰이 만료됐으면 구글 무음 로그인으로 조용히 다시 받는다(PR #50
/// 리뷰). 서버는 갱신 자격증명을 보관하지 않으므로 갱신은 앱이 새 ID 토큰을
/// 받아 `POST /auth/google` 을 다시 부르는 방식이다(`backend/README.md` 의
/// "세션").
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_api.dart';
import 'auth_providers.dart';
import 'auth_session.dart';

/// 복원을 마친 결과다.
enum SessionRestoreOutcome {
  /// 보관한 세션이 없다. 로그인부터 시작한다.
  none,

  /// 되살렸다. 홈으로 간다.
  restored,

  /// 보관한 세션이 있었으나 되살리지 못했다. 로그인부터 시작한다.
  expired,
}

class SessionRestorer {
  const SessionRestorer(this._ref);

  final Ref _ref;

  Future<SessionRestoreOutcome> restore() async {
    final store = _ref.read(sessionStoreProvider);
    final stored = await store.read();
    if (stored == null) return SessionRestoreOutcome.none;

    // 만료가 코앞이면 확인해 봐야 곧 만료된다. 곧바로 새로 받는다.
    if (!stored.isExpiring()) {
      final verified = await _verify(stored);
      if (verified != null) {
        _ref.read(sessionProvider.notifier).restore(verified);
        return SessionRestoreOutcome.restored;
      }
    }

    return _reauthenticate();
  }

  /// 보관한 세션이 서버에서도 살아 있는지 확인한다.
  ///
  /// 살아 있으면 서버가 준 계정으로 갱신해 돌려준다. 서버가 거절하면 `null`
  /// 이고, 부르는 쪽이 다시 인증한다.
  Future<AuthSession?> _verify(AuthSession stored) async {
    try {
      final account = await _ref.read(authApiProvider).me(
        stored.authorizationHeader,
      );
      return AuthSession(
        accessToken: stored.accessToken,
        tokenType: stored.tokenType,
        expiresAt: stored.expiresAt,
        account: account,
      );
    } on AuthServerFailure catch (failure) {
      // 401, 403 은 세션이 죽었다는 뜻이다. 그 밖의 상태 코드는 서버 쪽
      // 문제이지 세션 문제가 아니므로, 아직 만료되지 않은 세션을 버리지 않는다.
      if (failure.statusCode == 401 || failure.statusCode == 403) return null;
      return stored;
    } on AuthNetworkFailure {
      // 서버에 닿지 못했다. 확인하지 못했을 뿐 만료된 것은 아니다. 여기서
      // 로그인 화면으로 보내면 비행기 모드에서 앱을 열 수 없다.
      return stored;
    } on AuthUnexpectedResponseFailure {
      return null;
    }
  }

  /// 구글 무음 로그인으로 세션을 새로 받는다.
  Future<SessionRestoreOutcome> _reauthenticate() async {
    final idToken = await _ref.read(googleAuthenticatorProvider).silentIdToken();
    if (idToken == null) {
      // 고른 계정이 없거나 조용히 받을 수 없다. 로그인 화면에서 다시 받는다.
      await _ref.read(sessionProvider.notifier).discard();
      return SessionRestoreOutcome.expired;
    }

    try {
      final result = await _ref.read(authApiProvider).signInWithGoogle(idToken);
      switch (result) {
        case AuthenticatedResult():
          await _ref.read(sessionProvider.notifier).start(result);
          return SessionRestoreOutcome.restored;
        case ConsentRequiredResult():
          // 계정이 사라졌다. 동의 화면으로 바로 보내지 않는다. 가입은
          // 사용자가 로그인 화면에서 스스로 시작해야 한다(ADR-007).
          await _ref.read(sessionProvider.notifier).discard();
          return SessionRestoreOutcome.expired;
      }
    } on AuthNetworkFailure {
      // 지금 닿지 못했을 뿐이다. 보관한 값은 지우지 않고 두어 다음 실행에서
      // 다시 해본다.
      return SessionRestoreOutcome.expired;
    } on AuthFailure {
      await _ref.read(sessionProvider.notifier).discard();
      return SessionRestoreOutcome.expired;
    }
  }
}

final sessionRestorerProvider = Provider<SessionRestorer>(
  SessionRestorer.new,
);
