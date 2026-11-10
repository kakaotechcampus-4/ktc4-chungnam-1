/// 앱을 쓰는 도중 로그인 세션이 만료되면 조용히 다시 받는다.
///
/// 세션 수명은 1시간이고 서버는 갱신 자격증명을 보관하지 않는다
/// (`SAEROK_SESSION_TTL_SECONDS`, ADR-007). 그래서 앱을 켤 때와 같이 구글 무음
/// 로그인으로 새 ID 토큰을 받아 `POST /auth/google` 을 다시 부른다
/// ([SessionRestorer] 의 재인증과 같은 순서다). 공개 API 가 401 을 받거나 세션이
/// 곧 만료되면 [ApiClient] 가 이것을 부른다.
///
/// 다시 받지 못해 로그인부터 해야 하면 [sessionLossProvider] 로 알리고, 앱의
/// 맨 위가 그 화면으로 보낸다. 요청 코드는 화면을 옮기지 않는다. 면회를
/// 녹음하는 동안이면 세션을 지우지 않고 녹음이 끝날 때까지 미룬다
/// ([sessionHoldProvider]). 면회 흐름의 화면이면 지우기 전에 보호자에게 먼저
/// 알리고 확인을 받는다([unconfirmedSessionLossProvider]).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/auth_api.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';
import 'auth_session.dart';

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

/// 잃었지만 보호자가 확인할 때까지 지우지 않고 둔 세션이다.
///
/// 면회 흐름에서 잃으면([SessionRefresher.needsConfirmation]) 세션을 바로 지우지
/// 않는다. 지우면 단말의 어르신 목록이 비면서 뒤 화면이 등록 안내로 바뀐다.
/// 앱의 맨 위가 이 값을 보고 확인 창을 띄우고, 확인하면
/// [SessionRefresher.confirmLoss] 가 세션을 지운 뒤 [sessionLossProvider] 로
/// 알린다(UX 점검 8번, 2026-11-10).
final unconfirmedSessionLossProvider =
    NotifierProvider<SessionLossNotifier, SessionLoss?>(
      SessionLossNotifier.new,
    );

/// 세션을 잃어도 지금은 지우지 않고 기다리게 한다. 면회를 녹음하는 동안 녹음이
/// 켜고 끈다(`VisitController`).
///
/// 세션을 지우면 단말의 어르신 목록이 비면서 녹음 화면이 닫히고, 닫힐 때 녹음이
/// 멈춘다. 2026-11-10 E2E 에서 녹음 중 매시간 뜨는 구글 계정 선택 창을 취소하면
/// 로그인 화면으로 가서 녹음이 끊길 수 있었다(다른 계정을 고른 경우도 같다).
/// 그래서 켜져 있는 동안 다시 받지 못하면 세션을 그대로 두고 기다렸다가, 녹음이
/// 끝나 끄면 그때 지우고 로그인 화면으로 보낸다([SessionRefresher]). 운영 세션
/// 수명을 30일로 늘린 뒤에도(2026-11-10) 이 보호는 둔다.
class SessionHold extends Notifier<bool> {
  @override
  bool build() => false;

  void hold() => state = true;

  /// 녹음을 정리하면서 미뤄 부를 수 있어, 앱이 이미 정리됐으면 아무것도 하지 않는다.
  void release() {
    if (ref.mounted) state = false;
  }
}

final sessionHoldProvider = NotifierProvider<SessionHold, bool>(
  SessionHold.new,
);

/// 세션을 다시 받아 본 결과다.
sealed class _Renewal {
  const _Renewal();
}

/// 같은 계정으로 새로 받았다.
final class _Renewed extends _Renewal {
  const _Renewed();
}

/// 받지 못했고 원래 요청도 다시 보내지 않는다. 세션을 잃었거나, 받는 동안
/// 로그아웃하거나 세션이 바뀌었다.
final class _NotRenewed extends _Renewal {
  const _NotRenewed();
}

/// 지금은 받지 못했지만 세션이 죽었다고 볼 수 없다. 세션을 지우지 않는다.
/// [failure] 를 원래 요청의 실패로 돌려준다.
final class _TryLater extends _Renewal {
  const _TryLater(this.failure);

  final ApiFailure failure;
}

class SessionRefresher {
  SessionRefresher(this._ref) {
    _ref.listen(sessionHoldProvider, (_, held) {
      if (!held) _releaseHeldLoss();
    });
  }

  final Ref _ref;

  /// 녹음하는 동안([sessionHoldProvider]) 잃은 세션. 녹음이 끝나면 알린다.
  SessionLoss? _heldLoss;

  /// [_heldLoss] 를 잃은 때의 세션. 그 사이 로그아웃했거나 다시 로그인했으면
  /// 녹음이 끝나도 알리지 않는다.
  AuthSession? _heldSession;

  /// 세션을 지우기 전에 보호자의 확인을 먼저 받을지 답한다. 앱의 맨 위가 지금
  /// 화면을 보고 정한다(`main.dart`, 면회 흐름이면 `true`). 정하지 않았으면
  /// 확인 없이 바로 지운다.
  bool Function() needsConfirmation = _immediately;

  static bool _immediately() => false;

  /// 보호자의 확인을 기다리는 잃은 세션([unconfirmedSessionLossProvider]).
  SessionLoss? _unconfirmedLoss;

  /// [_unconfirmedLoss] 를 잃은 때의 세션.
  AuthSession? _unconfirmedSession;

  /// 지금 다시 받는 중인 작업이다. 여러 요청이 함께 401 을 받아도 한 번만 받는다.
  Future<_Renewal>? _running;

  /// 같은 계정으로 새로 받아 바꾼 세션. 예전 `Authorization` → 새 값이다.
  /// 먼저 보낸 요청의 401 이 늦게 와도 같은 계정의 것인지 가린다.
  final _renewed = <String, String>{};

  /// 공개 API 가 401 을 받았다. [sentAuthorization] 은 그 요청에 실어 보낸
  /// 세션이다. `true` 면 지금 세션으로 같은 요청을 한 번 다시 보낸다.
  ///
  /// - 보낸 뒤 로그아웃했거나 다른 세션(다른 계정, 다시 로그인)이 되었으면
  ///   다시 받지도, 다시 보내지도 않는다. 늦게 온 401 로 로그인 상태를 되살리거나
  ///   다른 계정으로 보내지 않는다.
  /// - 같은 계정을 그 사이 이미 새로 받았으면 받지 않고 새 세션으로 보낸다.
  /// - 보낸 세션 그대로면 새로 받는다([refresh]).
  /// - 서버에 닿지 못했거나 서버가 다시 시도해도 된다고 거절했으면 세션을
  ///   지우지 않고 [ApiNetworkFailure] 나 다시 시도할 수 있는
  ///   [ApiServerFailure] 를 던진다. 부르는 쪽이 보낼 자료를 지우지 않게 한다.
  Future<bool> retryAfterUnauthorized(String? sentAuthorization) async {
    final current = _ref.read(sessionProvider);
    if (current == null || sentAuthorization == null) return false;
    if (sentAuthorization != current.authorizationHeader) {
      return continues(sentAuthorization);
    }
    return switch (await _renew()) {
      _Renewed() => true,
      _NotRenewed() => false,
      _TryLater(:final failure) => throw failure,
    };
  }

  /// 지금 세션이 [startedAuthorization] 로 시작한 로그인을 이어 가는지 답한다.
  /// 그 세션 그대로이거나 같은 계정으로 새로 받은 세션이면 `true` 다.
  /// 로그아웃했거나 다른 계정 또는 새 로그인이면 `false` 다.
  bool continues(String startedAuthorization) {
    final now = _ref.read(sessionProvider)?.authorizationHeader;
    if (now == null) return false;
    String? next = startedAuthorization;
    while (next != null) {
      if (next == now) return true;
      next = _renewed[next];
    }
    return false;
  }

  /// 세션을 새로 받았으면 `true` 다.
  ///
  /// 서버에 닿지 못했거나 서버가 다시 시도해도 된다고(`retryable`) 거절했으면
  /// 세션을 지우지 않고 `false` 다. 지금 받지 못했을 뿐 세션이 죽었다고 단정하지
  /// 않는다. 그 밖에 받지 못하면 세션을 지우고 [sessionLossProvider] 로 알린 뒤
  /// `false` 다.
  ///
  /// 받는 동안 로그아웃하거나 세션이 바뀌었으면 늦게 온 결과를 버리고
  /// `false` 다. 계정 선택 창에서 원래와 다른 계정을 골랐으면 그 계정으로
  /// 바꾸지 않고 로그인 화면에서 다시 고르게 한다. 어느 쪽이든 원래 요청은
  /// 다시 보내지 않는다.
  Future<bool> refresh() async => await _renew() is _Renewed;

  Future<_Renewal> _renew() {
    // 녹음하는 동안이나 확인을 기다리는 동안 이미 잃은 세션이다. 계정 선택 창을
    // 다시 띄우지 않는다.
    if (_heldLoss != null || _unconfirmedLoss != null) {
      return Future.value(const _NotRenewed());
    }
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  /// 세션이 1분 안에 만료되면 미리 새로 받는다. 세션이 없으면 아무것도 하지 않는다.
  Future<void> refreshIfExpiring() async {
    final session = _ref.read(sessionProvider);
    if (session == null || !session.isExpiring()) return;
    await refresh();
  }

  Future<_Renewal> _refresh() async {
    // 다시 받기 시작한 때의 세션. 받는 동안 이것이 바뀌면 결과를 쓰지 않는다.
    final before = _ref.read(sessionProvider);
    bool changed() => !identical(_ref.read(sessionProvider), before);

    final idToken = await _ref
        .read(googleAuthenticatorProvider)
        .silentIdToken();
    // 계정 선택 창이 떠 있는 동안 로그아웃했으면 이미 로그인 화면이다.
    if (changed()) return const _NotRenewed();
    if (idToken == null) {
      // 고른 계정이 없거나 조용히 받을 수 없다. 로그인 화면에서 다시 고른다.
      await _lose(const SessionSignedOut());
      return const _NotRenewed();
    }

    try {
      final result = await _ref.read(authApiProvider).signInWithGoogle(idToken);
      // 기다리는 동안 로그아웃했으면 늦게 온 로그인을 저장하지 않는다.
      if (changed()) return const _NotRenewed();
      switch (result) {
        case AuthenticatedResult():
          // 원래 계정에서 시작한 요청을 다른 계정으로 보내지 않는다.
          final accountId = before?.account.accountId;
          if (accountId != null && result.account.accountId != accountId) {
            await _lose(const SessionSignedOut());
            return const _NotRenewed();
          }
          await _ref.read(sessionProvider.notifier).start(result);
          final renewed = _ref.read(sessionProvider);
          if (before != null && renewed != null) {
            _renewed[before.authorizationHeader] = renewed.authorizationHeader;
          }
          return const _Renewed();
        case ConsentRequiredResult():
          await _lose(SessionConsentRequired(result));
          return const _NotRenewed();
      }
    } on AuthNetworkFailure catch (failure) {
      logAuthFailure(failure);
      if (changed()) return const _NotRenewed();
      return const _TryLater(ApiNetworkFailure());
    } on AuthFailure catch (failure) {
      logAuthFailure(failure);
      if (changed()) return const _NotRenewed();
      // 서버의 일시 장애다. 인증을 거절한 것이 아니므로 세션을 지우지 않는다.
      if (failure case AuthServerFailure(
        :final statusCode,
        :final errorCode,
        retryable: true,
      )) {
        return _TryLater(
          ApiServerFailure(
            statusCode: statusCode,
            errorCode: errorCode,
            retryable: true,
          ),
        );
      }
      await _lose(const SessionSignedOut());
      return const _NotRenewed();
    }
  }

  Future<void> _lose(SessionLoss loss) async {
    if (_ref.read(sessionHoldProvider)) {
      // 녹음 중이다. 세션을 그대로 두고 녹음이 끝나면 알린다. 처음 잃은 이유를
      // 남긴다.
      if (_heldLoss == null) {
        _heldLoss = loss;
        _heldSession = _ref.read(sessionProvider);
      }
      return;
    }
    if (needsConfirmation()) {
      // 면회 흐름이다. 화면을 옮기기 전에 보호자에게 먼저 알린다. 세션은
      // 확인할 때 지운다([confirmLoss]). 이미 묻고 있으면 처음 이유를 둔다.
      if (_unconfirmedLoss == null) {
        _unconfirmedLoss = loss;
        _unconfirmedSession = _ref.read(sessionProvider);
        _ref.read(unconfirmedSessionLossProvider.notifier).report(loss);
      }
      return;
    }
    await _ref.read(sessionProvider.notifier).discard();
    _ref.read(sessionLossProvider.notifier).report(loss);
  }

  /// 보호자가 확인 창에서 확인했다. 기다리던 세션을 지우고
  /// [sessionLossProvider] 로 알려 로그인 화면이나 동의 화면으로 가게 한다.
  ///
  /// 그 사이 로그아웃했거나 다시 로그인했으면 그 세션을 건드리지 않는다.
  Future<void> confirmLoss() async {
    final loss = _unconfirmedLoss;
    final session = _unconfirmedSession;
    _unconfirmedLoss = null;
    _unconfirmedSession = null;
    _ref.read(unconfirmedSessionLossProvider.notifier).clear();
    if (loss == null) return;
    if (!identical(_ref.read(sessionProvider), session)) return;
    await _ref.read(sessionProvider.notifier).discard();
    _ref.read(sessionLossProvider.notifier).report(loss);
  }

  Future<void> _releaseHeldLoss() async {
    final loss = _heldLoss;
    final session = _heldSession;
    _heldLoss = null;
    _heldSession = null;
    if (loss == null) return;
    // 녹음하는 동안 로그아웃했거나 다시 로그인했으면 그 세션을 건드리지 않는다.
    if (!identical(_ref.read(sessionProvider), session)) return;
    await _lose(loss);
  }
}

final sessionRefresherProvider = Provider<SessionRefresher>(
  SessionRefresher.new,
);
