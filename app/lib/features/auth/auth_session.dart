/// 로그인한 뒤의 세션이다.
///
/// 앱을 다시 켰을 때 복원할 수 있도록 [SessionStore] 가 보관한다. 접근 토큰은
/// `Authorization` 헤더에만 쓰고 로그와 화면에 내보내지 않는다(`CLAUDE.md`).
library;

import '../../data/auth_api.dart';

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

  /// 보관해 둔 값을 되읽는다.
  ///
  /// 형태가 어긋나면 [AuthUnexpectedResponseFailure] 를 던진다. 절반만 읽어
  /// 로그인한 것처럼 넘기지 않는다.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (expiresAt == null) {
      throw const AuthUnexpectedResponseFailure('expiresAt 이 없다');
    }
    final account = json['account'];
    if (account is! Map<String, dynamic>) {
      throw const AuthUnexpectedResponseFailure('account 가 없다');
    }
    final accessToken = json['accessToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const AuthUnexpectedResponseFailure('accessToken 이 없다');
    }
    return AuthSession(
      accessToken: accessToken,
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      expiresAt: expiresAt,
      account: AuthAccount.fromJson(account),
    );
  }

  /// `Authorization` 헤더에 쓴다. 로그와 화면에 내보내지 않는다.
  final String accessToken;

  final String tokenType;
  final DateTime expiresAt;
  final AuthAccount account;

  String get authorizationHeader => '$tokenType $accessToken';

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).isBefore(expiresAt);

  /// 만료가 코앞이면 미리 새로 받는다.
  ///
  /// 복원 직후 화면을 띄우고 나서 곧바로 만료되는 일을 줄인다.
  bool isExpiring({DateTime? now, Duration margin = const Duration(minutes: 1)}) =>
      isExpired(now: (now ?? DateTime.now()).add(margin));

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'tokenType': tokenType,
    'expiresAt': expiresAt.toIso8601String(),
    'account': account.toJson(),
  };
}
