/// 로그인한 뒤 부르는 공개 API 의 공통 요청 틀.
///
/// 계약은 `docs/architecture/api-spec.md` 의 "공통" 을 따른다. 요청마다 서버
/// 주소와 `Authorization` 헤더를 붙이고, 응답은 JSON 객체로 읽으며, 실패는
/// [ApiFailure] 하나로 모은다. 각 API 는 경로와 본문만 넘기면 된다.
///
/// 로그인 전 API(`/auth/google`, `/auth/consent`)는 [AuthApi] 가 따로 맡는다.
/// 접근 토큰은 헤더에만 쓰고 로그와 화면에 내보내지 않는다(`CLAUDE.md`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_providers.dart';
import 'auth_api.dart' show apiBaseUrl;

// ── 실패 ────────────────────────────────────────────

/// 공개 API 호출에서 생기는 실패다. 화면은 이 네 가지만 구분하면 된다.
sealed class ApiFailure implements Exception {
  const ApiFailure();
}

/// 서버가 공통 `ErrorResponse` 로 거절했다.
///
/// [errorCode] 는 명세의 오류 표에 있는 값이며, 응답을 읽지 못했으면 `null`
/// 이다. 서버가 주지 않은 코드를 지어내지 않는다.
final class ApiServerFailure extends ApiFailure {
  const ApiServerFailure({
    required this.statusCode,
    this.errorCode,
    this.retryable = false,
  });

  final int statusCode;
  final String? errorCode;

  /// 서버가 다시 시도해도 된다고 알린 경우다.
  final bool retryable;

  @override
  String toString() => 'ApiServerFailure($statusCode, $errorCode)';
}

/// 서버에 닿지 못했다. 연결 실패와 시간 초과다.
final class ApiNetworkFailure extends ApiFailure {
  const ApiNetworkFailure();

  @override
  String toString() => 'ApiNetworkFailure()';
}

/// 서버 응답이 계약과 다르다. 성공으로 넘기지 않고 실패로 둔다.
final class ApiUnexpectedResponseFailure extends ApiFailure {
  const ApiUnexpectedResponseFailure(this.detail);

  /// 어디가 어긋났는지. 사용자에게 보여주지 않고 개발 중 확인에만 쓴다.
  final String detail;

  @override
  String toString() => 'ApiUnexpectedResponseFailure($detail)';
}

/// 로그인 세션이 없다. 요청을 보내지 않고 멈춘다.
final class ApiSignedOutFailure extends ApiFailure {
  const ApiSignedOutFailure();

  @override
  String toString() => 'ApiSignedOutFailure()';
}

// ── 클라이언트 ──────────────────────────────────────

class ApiClient {
  ApiClient({
    required this.authorization,
    String baseUrl = apiBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 5),
  }) : _baseUrl = _trimSlash(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// 요청할 때마다 `Authorization` 헤더 값을 읽는다. 로그인 전이면 `null` 이다.
  ///
  /// 값을 붙잡아 두지 않으므로 다시 로그인해도 새 세션으로 보낸다.
  final String? Function() authorization;

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  /// 일반 JSON 요청의 제한 시간.
  final Duration timeout;

  /// 파일 업로드의 제한 시간. 면회 녹음은 수십 MB 가 될 수 있어 따로 둔다.
  final Duration uploadTimeout;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _json(
        () async => _client.get(_uri(path, query), headers: _headers()),
        timeout,
      );

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, Object?>? body,
  ]) => _json(
    () async => _client.post(
      _uri(path),
      headers: _headers(json: body != null),
      body: body == null ? null : jsonEncode(body),
    ),
    timeout,
  );

  Future<Map<String, dynamic>> patch(String path, Map<String, Object?> body) =>
      _json(
        () async => _client.patch(
          _uri(path),
          headers: _headers(json: true),
          body: jsonEncode(body),
        ),
        timeout,
      );

  /// `multipart/form-data` 로 파일을 올린다. 명세는 파일 업로드에만 이 형식을 쓴다.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    required List<http.MultipartFile> files,
  }) => _json(() async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.addAll(files);
    return http.Response.fromStream(await _client.send(request));
  }, uploadTimeout);

  /// 본문 없이 지운다. 성공 응답은 빈 `204` 이므로 아무것도 돌려주지 않는다.
  Future<void> delete(String path) => _send(
    () async => _client.delete(_uri(path), headers: _headers()),
    timeout,
  );

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// 세션이 없으면 [ApiSignedOutFailure] 를 던진다. 요청은 나가지 않는다.
  Map<String, String> _headers({bool json = false}) {
    final header = authorization();
    if (header == null) throw const ApiSignedOutFailure();
    return {
      'Authorization': header,
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// 응답 본문을 JSON 객체로 읽는다. 객체가 아니면 성공으로 넘기지 않는다.
  Future<Map<String, dynamic>> _json(
    Future<http.Response> Function() request,
    Duration limit,
  ) async {
    final decoded = _decode(await _send(request, limit));
    if (decoded is! Map<String, dynamic>) {
      throw const ApiUnexpectedResponseFailure('응답이 객체가 아니다');
    }
    return decoded;
  }

  /// 요청을 보내고 연결 실패와 서버의 거절을 [ApiFailure] 로 옮긴다.
  Future<http.Response> _send(
    Future<http.Response> Function() request,
    Duration limit,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(limit);
    } on TimeoutException {
      throw const ApiNetworkFailure();
    } on http.ClientException {
      throw const ApiNetworkFailure();
    } on SocketException {
      throw const ApiNetworkFailure();
    }

    if (response.statusCode >= 400) {
      final decoded = _decode(response);
      throw decoded is Map<String, dynamic>
          ? ApiServerFailure(
              statusCode: response.statusCode,
              errorCode: decoded['errorCode'] as String?,
              retryable: decoded['retryable'] as bool? ?? false,
            )
          : ApiServerFailure(statusCode: response.statusCode);
    }
    return response;
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

/// 지금 로그인한 세션으로 요청하는 클라이언트.
///
/// 테스트는 이 provider 를 override 해 가짜 `http.Client` 를 넣는다(`ADR-005`).
final apiClientProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(
    authorization: () => ref.read(sessionProvider)?.authorizationHeader,
  );
  ref.onDispose(api.close);
  return api;
});
