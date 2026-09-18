/// 로그인 API 클라이언트.
///
/// 계약은 `backend/README.md` 의 "로그인 API" 를 따른다. 서버가 준 값을 그대로
/// 옮기고 여기서 새 값을 만들지 않는다.
///
/// 구글 ID 토큰은 `POST /auth/google` 한 번에만 쓰고 보관하지 않는다. ID 토큰,
/// 등록 토큰과 세션 값은 로그에 남기지 않는다(`CLAUDE.md`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 서버 주소. 빌드할 때 넘긴다.
///
///     flutter run --dart-define=SAEROK_API_BASE_URL=http://10.0.2.2:8000
///
/// 기본값은 안드로이드 에뮬레이터에서 호스트를 가리키는 주소다
/// (`backend/README.md` 의 "설정"). 실기기는 PC 의 LAN 주소를 넘긴다.
const apiBaseUrl = String.fromEnvironment(
  'SAEROK_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

// ── 실패 ────────────────────────────────────────────

/// 로그인 과정에서 생기는 실패다. 화면은 이 네 가지만 구분하면 된다.
///
/// 사용자에게 보여줄 문구는 `features/auth/auth_messages.dart` 에 있다.
sealed class AuthFailure implements Exception {
  const AuthFailure();
}

/// 서버가 공통 `ErrorResponse` 로 거절했다.
///
/// [errorCode] 는 `backend/README.md` 의 오류 표에 있는 값이며, 응답을 읽지
/// 못했으면 `null` 이다. 서버가 주지 않은 코드를 지어내지 않는다.
final class AuthServerFailure extends AuthFailure {
  const AuthServerFailure({
    required this.statusCode,
    this.errorCode,
    this.retryable = false,
  });

  final int statusCode;
  final String? errorCode;

  /// 서버가 다시 시도해도 된다고 알린 경우다.
  final bool retryable;

  @override
  String toString() => 'AuthServerFailure($statusCode, $errorCode)';
}

/// 서버에 닿지 못했다. 연결 실패와 시간 초과다.
final class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure();

  @override
  String toString() => 'AuthNetworkFailure()';
}

/// 서버 응답이 계약과 다르다. 성공으로 넘기지 않고 실패로 둔다.
final class AuthUnexpectedResponseFailure extends AuthFailure {
  const AuthUnexpectedResponseFailure(this.detail);

  /// 어디가 어긋났는지. 사용자에게 보여주지 않고 개발 중 확인에만 쓴다.
  final String detail;

  @override
  String toString() => 'AuthUnexpectedResponseFailure($detail)';
}

/// 구글 로그인 SDK 쪽 실패다. 사용자 취소는 실패로 보지 않으므로 여기에 없다.
final class AuthGoogleFailure extends AuthFailure {
  const AuthGoogleFailure({required this.misconfigured, this.detail});

  /// 클라이언트 ID 나 SHA-1 등 설정 문제다. 사용자가 다시 눌러도 풀리지 않는다.
  final bool misconfigured;

  /// 무엇이 어긋났는지. 토큰이나 계정 정보는 담지 않는다.
  final String? detail;

  @override
  String toString() =>
      'AuthGoogleFailure(misconfigured: $misconfigured, $detail)';
}

// ── 응답 ────────────────────────────────────────────

/// `POST /auth/google` 의 두 응답이다. `status` 로 갈린다.
sealed class GoogleLoginResult {
  const GoogleLoginResult();
}

/// 세션을 받았다. 이미 계정이 있거나 동의 제출을 마친 경우다.
final class AuthenticatedResult extends GoogleLoginResult {
  const AuthenticatedResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.account,
  });

  factory AuthenticatedResult.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    if (account is! Map<String, dynamic>) {
      throw const AuthUnexpectedResponseFailure('account 가 없다');
    }
    return AuthenticatedResult(
      accessToken: _string(json, 'accessToken'),
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      expiresIn: _int(json, 'expiresIn'),
      account: AuthAccount.fromJson(account),
    );
  }

  final String accessToken;
  final String tokenType;

  /// 세션이 유효한 시간(초).
  final int expiresIn;

  final AuthAccount account;
}

/// 구글 인증은 통과했으나 아직 계정이 없다.
///
/// 이 응답을 받은 시점에는 계정이 만들어지지 않았다. 필수 동의를 모두 받아
/// `POST /auth/consent` 를 호출해야 계정이 생긴다(ADR-007).
final class ConsentRequiredResult extends GoogleLoginResult {
  const ConsentRequiredResult({
    required this.registrationToken,
    required this.expiresIn,
    required this.consentVersion,
    required this.requiredConsents,
    required this.optionalConsents,
  });

  factory ConsentRequiredResult.fromJson(Map<String, dynamic> json) {
    return ConsentRequiredResult(
      registrationToken: _string(json, 'registrationToken'),
      expiresIn: _int(json, 'expiresIn'),
      consentVersion: _string(json, 'consentVersion'),
      requiredConsents: _stringList(json, 'requiredConsents'),
      optionalConsents: _stringList(json, 'optionalConsents'),
    );
  }

  /// 구글 인증과 동의 제출 사이에만 쓰는 임시 토큰이다. 저장하지 않는다.
  final String registrationToken;

  /// 등록 토큰이 유효한 시간(초).
  final int expiresIn;

  /// 서버가 제시한 약관 버전. 동의 제출에 그대로 되돌려 보낸다.
  final String consentVersion;

  /// 서버가 필수로 보는 동의 키다.
  final List<String> requiredConsents;

  final List<String> optionalConsents;
}

/// 서버의 `AccountResponse`.
///
/// 앱의 `data/models.dart` 에 있는 `Account` 와 같은 것을 가리키지만 형태가 아직
/// 다르다. 서버 응답에는 `loginId` 가 없고 `email` 이 `null` 일 수 있다
/// (`backend/README.md` 의 "아직 정하지 않은 것"). 한쪽에 억지로 맞추면 없는 값을
/// 지어내야 하므로, 계약이 합쳐질 때까지 응답을 그대로 담는 타입을 따로 둔다.
class AuthAccount {
  const AuthAccount({
    required this.accountId,
    required this.authProvider,
    required this.displayName,
    required this.email,
    required this.consentVersion,
    required this.createdAt,
  });

  factory AuthAccount.fromJson(Map<String, dynamic> json) {
    final consent = json['consent'];
    return AuthAccount(
      accountId: _string(json, 'accountId'),
      authProvider: _string(json, 'authProvider'),
      displayName: _string(json, 'displayName'),
      email: json['email'] as String?,
      consentVersion: consent is Map<String, dynamic>
          ? consent['consentVersion'] as String?
          : null,
      createdAt: json['createdAt'] as String?,
    );
  }

  final String accountId;

  /// 지금은 `google` 뿐이다.
  final String authProvider;

  final String displayName;

  /// 서버가 이메일을 저장하지 않으면 `null` 이다.
  final String? email;

  final String? consentVersion;
  final String? createdAt;
}

// ── 클라이언트 ──────────────────────────────────────

class AuthApi {
  AuthApi({
    String baseUrl = apiBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = _trimSlash(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// 구글 ID 토큰을 검증받는다.
  ///
  /// 계정이 있으면 [AuthenticatedResult], 없으면 [ConsentRequiredResult] 다.
  Future<GoogleLoginResult> signInWithGoogle(String idToken) async {
    final body = await _post('/auth/google', {'idToken': idToken});
    final status = body['status'];
    return switch (status) {
      'authenticated' => AuthenticatedResult.fromJson(body),
      'consentRequired' => ConsentRequiredResult.fromJson(body),
      _ => throw AuthUnexpectedResponseFailure('모르는 status: $status'),
    };
  }

  /// 필수 동의를 제출한다. 여기서 계정과 동의 이력이 함께 만들어진다.
  ///
  /// [consents] 는 계약의 네 항목을 모두 담는다. [displayName] 은 선택이며
  /// 비워 두면 서버 기본값을 쓴다.
  Future<AuthenticatedResult> submitConsent({
    required String registrationToken,
    required String consentVersion,
    required Map<String, bool> consents,
    String? displayName,
  }) async {
    final trimmed = displayName?.trim();
    final body = await _post('/auth/consent', {
      'registrationToken': registrationToken,
      'consentVersion': consentVersion,
      'consents': consents,
      // 서버 모델이 `extra="forbid"` 라 보내지 않을 값은 아예 넣지 않는다.
      if (trimmed != null && trimmed.isNotEmpty) 'displayName': trimmed,
    });
    return AuthenticatedResult.fromJson(body);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthNetworkFailure();
    } on http.ClientException {
      throw const AuthNetworkFailure();
    } on SocketException {
      throw const AuthNetworkFailure();
    }

    if (response.statusCode >= 400) throw _serverFailure(response);

    final decoded = _decode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const AuthUnexpectedResponseFailure('응답이 객체가 아니다');
    }
    return decoded;
  }

  /// 공통 `ErrorResponse` 를 읽는다. 읽지 못해도 상태 코드는 남긴다.
  static AuthServerFailure _serverFailure(http.Response response) {
    final decoded = _decode(response);
    if (decoded is Map<String, dynamic>) {
      return AuthServerFailure(
        statusCode: response.statusCode,
        errorCode: decoded['errorCode'] as String?,
        retryable: decoded['retryable'] as bool? ?? false,
      );
    }
    return AuthServerFailure(statusCode: response.statusCode);
  }

  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String _trimSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw AuthUnexpectedResponseFailure('$key 가 없다');
  }
  return value;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw AuthUnexpectedResponseFailure('$key 가 없다');
  return value;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw AuthUnexpectedResponseFailure('$key 가 없다');
  return value.whereType<String>().toList(growable: false);
}
