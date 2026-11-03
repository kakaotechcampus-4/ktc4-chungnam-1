/// 로그인한 뒤 부르는 공개 API 의 공통 요청 틀.
///
/// 계약은 `docs/architecture/api-spec.md` 의 "공통" 을 따른다. 요청마다 서버
/// 주소와 `Authorization` 헤더를 붙이고, 응답은 JSON 객체로 읽으며, 실패는
/// [ApiFailure] 하나로 모은다. 각 API 는 경로와 본문만 넘기면 된다.
///
/// 로그인 전 API(`/auth/google`, `/auth/consent`)는 [AuthApi] 가 따로 맡는다.
/// 접근 토큰은 헤더에만 쓰고 로그와 화면에 내보내지 않는다(`CLAUDE.md`).
///
/// 세션은 1시간이면 만료된다. 곧 만료될 세션은 보내기 전에 새로 받고, 그래도
/// 서버가 401 로 거절하면 세션을 새로 받아 같은 요청을 한 번만 다시 보낸다
/// ([SessionRefresher]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_providers.dart';
import '../features/auth/session_refresher.dart';
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
    this.message,
  });

  final int statusCode;
  final String? errorCode;

  /// 서버가 다시 시도해도 된다고 알린 경우다.
  final bool retryable;

  /// `ErrorResponse.message`. 화면에는 점검 안내([maintenanceMessageOf])에만
  /// 쓴다. 다른 실패는 화면마다 정한 문구를 쓴다.
  final String? message;

  /// 배포 중 분석 접수를 잠시 멈췄다는 거절이다
  /// (`backend/docs/deployment-control.md`). 앱에서는 녹음 분석, 짧은 음성
  /// 전사, 카드 생성 요청이 받는다. 보낼 파일과 입력은 지우지 않고 점검이
  /// 끝난 뒤 다시 보내게 한다.
  bool get isMaintenance =>
      statusCode == 503 && errorCode == serviceMaintenanceCode;

  @override
  String toString() => 'ApiServerFailure($statusCode, $errorCode)';
}

/// 배포 중 접수를 멈췄을 때 서버가 주는 `errorCode`.
const serviceMaintenanceCode = 'SERVICE_MAINTENANCE';

/// 서버가 안내 문구를 주지 않았을 때 보여줄 점검 안내.
const serviceMaintenanceMessage = '서비스 점검 중이에요. 잠시 후 다시 시도해 주세요.';

/// [error] 가 점검 중 거절이면 보여줄 문구를, 아니면 `null` 을 돌려준다.
///
/// 서버가 준 `message` 를 쓰고, 비어 있으면 [serviceMaintenanceMessage] 다.
String? maintenanceMessageOf(Object? error) {
  if (error is! ApiServerFailure || !error.isMaintenance) return null;
  final text = error.message?.trim() ?? '';
  return text.isEmpty ? serviceMaintenanceMessage : text;
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
    this.beforeRequest,
    this.reauthenticate,
    this.continues,
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

  /// 요청을 보내기 전에 부른다. 곧 만료될 세션을 미리 새로 받는 자리다.
  final Future<void> Function()? beforeRequest;

  /// 서버가 401 로 거절하면 요청에 실어 보낸 `Authorization` 값과 함께
  /// 부른다. `true` 면 같은 요청을 한 번만 다시 보낸다. 없으면 401 을 그대로
  /// 실패로 돌려준다.
  ///
  /// 보낸 뒤 로그아웃했거나 다른 세션이 되었으면 다시 보내지 않도록, 어느
  /// 세션으로 보냈는지 함께 넘긴다.
  ///
  /// 지금은 다시 받지 못했지만 세션이 죽었다고 볼 수 없으면(서버에 닿지 못함,
  /// 서버의 일시 장애) [ApiFailure] 를 던진다. 그 실패를 원래 요청의 실패로
  /// 돌려준다. 부르는 쪽은 다시 시도할 수 있는 실패로 보고 보낼 자료를 남긴다.
  final Future<bool> Function(String? sentAuthorization)? reauthenticate;

  /// 요청을 시작할 때의 `Authorization` 값을 받아, 지금 세션이 그 로그인을
  /// 이어 가는지 답한다. 같은 계정을 새로 받은 세션이면 이어 간다.
  ///
  /// 세션을 새로 받기를 기다린 뒤 보내기 전에 묻는다. 그 사이 로그아웃했거나
  /// 다른 계정으로 로그인했으면 [ApiSignedOutFailure] 로 멈춰, 앞 계정에서 시작한
  /// 요청을 다른 계정으로 보내지 않는다. 없으면 묻지 않는다.
  final bool Function(String startedAuthorization)? continues;

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
  ///
  /// 파일은 한 번 보내면 다시 읽을 수 없어 [files] 는 보낼 때마다 새로 만든다.
  /// 세션이 만료돼 다시 보낼 때도 같은 파일을 처음부터 올린다.
  ///
  /// [limit] 를 주지 않으면 [uploadTimeout] 이다. 결과를 화면에서 기다리는
  /// 요청은 더 짧게 준다.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    required Future<List<http.MultipartFile>> Function() files,
    Duration? limit,
  }) => _json(() async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.addAll(await files());
    return http.Response.fromStream(await _client.send(request));
  }, limit ?? uploadTimeout);

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
  ///
  /// 401 이면 세션을 새로 받아 한 번만 다시 보낸다. 요청은 보낼 때마다 헤더를
  /// 새로 읽으므로 다시 보내는 요청은 새 세션으로 나간다. 다시 보내도 401 이면
  /// 더 반복하지 않고 실패로 돌려준다.
  ///
  /// 세션을 새로 받기를 기다린 뒤에는 시작한 로그인이 이어지는지 보고 보낸다
  /// ([continues]).
  Future<http.Response> _send(
    Future<http.Response> Function() request,
    Duration limit,
  ) async {
    // 요청을 시작한 로그인. 기다리는 동안 계정이 바뀌면 보내지 않는다.
    final started = authorization();
    await beforeRequest?.call();
    _ensureContinues(started);
    // 이번 요청에 실릴 세션. 401 이 늦게 와도 이 세션의 것인지 가린다.
    final sent = authorization();
    var response = await _attempt(request, limit);
    if (response.statusCode == 401) {
      final reauthenticate = this.reauthenticate;
      if (reauthenticate != null && await reauthenticate(sent)) {
        _ensureContinues(started);
        response = await _attempt(request, limit);
      }
    }

    if (response.statusCode >= 400) {
      final decoded = _decode(response);
      throw decoded is Map<String, dynamic>
          ? ApiServerFailure(
              statusCode: response.statusCode,
              errorCode: decoded['errorCode'] as String?,
              retryable: decoded['retryable'] as bool? ?? false,
              message: decoded['message'] is String
                  ? decoded['message'] as String
                  : null,
            )
          : ApiServerFailure(statusCode: response.statusCode);
    }
    return response;
  }

  void _ensureContinues(String? started) {
    final continues = this.continues;
    if (started == null || continues == null) return;
    if (!continues(started)) throw const ApiSignedOutFailure();
  }

  /// 한 번 보낸다. 연결 실패와 시간 초과는 [ApiNetworkFailure] 다.
  Future<http.Response> _attempt(
    Future<http.Response> Function() request,
    Duration limit,
  ) async {
    try {
      return await request().timeout(limit);
    } on TimeoutException {
      throw const ApiNetworkFailure();
    } on http.ClientException {
      throw const ApiNetworkFailure();
    } on SocketException {
      throw const ApiNetworkFailure();
    }
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
/// 세션이 곧 만료되거나 401 을 받으면 [sessionRefresherProvider] 로 새로 받는다.
/// 테스트는 이 provider 를 override 해 가짜 `http.Client` 를 넣는다(`ADR-005`).
final apiClientProvider = Provider<ApiClient>((ref) {
  final refresher = ref.read(sessionRefresherProvider);
  final api = ApiClient(
    authorization: () => ref.read(sessionProvider)?.authorizationHeader,
    beforeRequest: refresher.refreshIfExpiring,
    reauthenticate: refresher.retryAfterUnauthorized,
    continues: refresher.continues,
  );
  ref.onDispose(api.close);
  return api;
});
