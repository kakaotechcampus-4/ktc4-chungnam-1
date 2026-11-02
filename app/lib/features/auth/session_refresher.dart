/// 앱을 쓰는 도중 로그인 세션이 만료되면 조용히 다시 받는다.
///
/// 세션 수명은 1시간이고 서버는 갱신 자격증명을 보관하지 않는다
/// (`SAEROK_SESSION_TTL_SECONDS`, ADR-007). 그래서 앱을 켤 때와 같이 구글 무음
/// 로그인으로 새 ID 토큰을 받아 `POST /auth/google` 을 다시 부른다
/// ([SessionRestorer] 의 재인증과 같은 순서다). 공개 API 가 401 을 받거나 세션이
/// 곧 만료되면 [ApiClient] 가 이것을 부른다.
///
/// 다시 받지 못해 로그인부터 해야 하면 [sessionLossProvider] 로 알리고, 앱의
/// 맨 위가 그 화면으로 보낸다. 요청 코드는 화면을 옮기지 않는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_api.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';

/// 세션을 다시 받지 못해 로그인부터 해야 하는 이유다.
sealed class SessionLoss {
  const SessionLoss();
}

/// 조용히 다시 받을 수 없다. 로그인 화면에서 다시 고른다.
final class SessionSignedOut extends SessionLoss {
  const SessionSignedOut();
}

/// 계정이 사라져 다시 가입해야 한다. 서버가 준 등록 정보로 동의 화면을 연다.
final class SessionConsentRequired extends SessionLoss {
  const SessionConsentRequired(this.pending);

  final ConsentRequiredResult pending;
}

/// 마지막으로 잃은 세션이다. 앱의 맨 위가 화면을 옮긴 뒤 [clear] 로 비운다.
class SessionLossNotifier extends Notifier<SessionLoss?> {
  @override
  SessionLoss? build() => null;

  void report(SessionLoss loss) => state = loss;

  void clear() => state = null;
}

final sessionLossProvider = NotifierProvider<SessionLossNotifier, SessionLoss?>(
  SessionLossNotifier.new,
);

class SessionRefresher {
  SessionRefresher(this._ref);

  final Ref _ref;

  /// 지금 다시 받는 중인 작업이다. 여러 요청이 함께 401 을 받아도 한 번만 받는다.
  Future<bool>? _running;

  /// 세션을 새로 받았으면 `true` 다.
  ///
  /// 서버에 닿지 못해 받지 못했으면 세션을 지우지 않고 `false` 다. 지금 닿지
  /// 못했을 뿐 세션이 죽었다고 단정하지 않는다. 그 밖에 받지 못하면 세션을
  /// 지우고 [sessionLossProvider] 로 알린 뒤 `false` 다.
  ///
  /// 받는 동안 로그아웃하거나 세션이 바뀌었으면 늦게 온 결과를 버리고
  /// `false` 다. 계정 선택 창에서 원래와 다른 계정을 골랐으면 그 계정으로
  /// 바꾸지 않고 로그인 화면에서 다시 고르게 한다. 어느 쪽이든 원래 요청은
  /// 다시 보내지 않는다.
  Future<bool> refresh() =>
      _running ??= _refresh().whenComplete(() => _running = null);

  /// 세션이 1분 안에 만료되면 미리 새로 받는다. 세션이 없으면 아무것도 하지 않는다.
  Future<void> refreshIfExpiring() async {
    final session = _ref.read(sessionProvider);
    if (session == null || !session.isExpiring()) return;
    await refresh();
  }

  Future<bool> _refresh() async {
    // 다시 받기 시작한 때의 세션. 받는 동안 이것이 바뀌면 결과를 쓰지 않는다.
    final before = _ref.read(sessionProvider);
    bool changed() => !identical(_ref.read(sessionProvider), before);

    final idToken = await _ref
        .read(googleAuthenticatorProvider)
        .silentIdToken();
    // 계정 선택 창이 떠 있는 동안 로그아웃했으면 이미 로그인 화면이다.
    if (changed()) return false;
    if (idToken == null) {
      // 고른 계정이 없거나 조용히 받을 수 없다. 로그인 화면에서 다시 고른다.
      await _lose(const SessionSignedOut());
      return false;
    }

    try {
      final result = await _ref.read(authApiProvider).signInWithGoogle(idToken);
      // 기다리는 동안 로그아웃했으면 늦게 온 로그인을 저장하지 않는다.
      if (changed()) return false;
      switch (result) {
        case AuthenticatedResult():
          // 원래 계정에서 시작한 요청을 다른 계정으로 보내지 않는다.
          final accountId = before?.account.accountId;
          if (accountId != null && result.account.accountId != accountId) {
            await _lose(const SessionSignedOut());
            return false;
          }
          await _ref.read(sessionProvider.notifier).start(result);
          return true;
        case ConsentRequiredResult():
          await _lose(SessionConsentRequired(result));
          return false;
      }
    } on AuthNetworkFailure catch (failure) {
      logAuthFailure(failure);
      return false;
    } on AuthFailure catch (failure) {
      logAuthFailure(failure);
      if (changed()) return false;
      await _lose(const SessionSignedOut());
      return false;
    }
  }

  Future<void> _lose(SessionLoss loss) async {
    await _ref.read(sessionProvider.notifier).discard();
    _ref.read(sessionLossProvider.notifier).report(loss);
  }
}

final sessionRefresherProvider = Provider<SessionRefresher>(
  SessionRefresher.new,
);
