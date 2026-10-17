// 프로필 API(`api-spec.md` 2절)를 흉내 내는 가짜 서버다.
//
// 로그인한 상태로 화면을 띄우는 테스트는 어르신 목록을 서버에서 불러온다.
// 실제 주소로 요청이 나가지 않도록 이 서버를 `profileApiProvider` 에 넣는다.
// 값은 모두 합성이다.

import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/profile_api.dart';

class FakeProfileServer {
  FakeProfileServer({List<Map<String, Object?>>? profiles})
    : profiles = profiles ?? [];

  /// 서버에 있는 프로필. 명세의 Profile 모양이다.
  final List<Map<String, Object?>> profiles;

  /// 받은 요청을 차례대로 남긴다. 본문은 JSON 으로 읽은 값이다.
  final requests = <({String method, String path, Object? body})>[];

  /// 정해 두면 그 요청에 이 오류로 답한다. 키는 `METHOD path` 다.
  final failures = <String, ({int status, String errorCode})>{};

  /// 연결이 끊긴 것처럼 모든 요청을 실패시킨다.
  bool offline = false;

  int _next = 1;

  ProfileApi get api => ProfileApi(
    ApiClient(
      authorization: () => 'Bearer fake-token',
      baseUrl: 'http://api.test',
      client: MockClient(_handle),
    ),
  );

  Override get override => profileApiProvider.overrideWithValue(api);

  Future<http.Response> _handle(http.Request request) async {
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    requests.add((method: request.method, path: request.url.path, body: body));
    if (offline) throw http.ClientException('오프라인');

    final failure = failures['${request.method} ${request.url.path}'];
    if (failure != null) {
      return _json({
        'schemaVersion': 1,
        'errorCode': failure.errorCode,
        'message': '테스트용 오류',
        'requestId': 'req_test',
        'retryable': false,
      }, failure.status);
    }

    final segments = request.url.pathSegments;
    // /api/v1/profiles
    if (segments.length == 3) {
      if (request.method == 'GET') {
        return _json({
          'schemaVersion': 1,
          'profiles': [
            for (final p in profiles)
              {
                'profileId': p['profileId'],
                'name': p['name'],
                'gender': p['gender'],
                'setupStatus': p['setupStatus'],
              },
          ],
        }, 200);
      }
      final created = profile(
        id: 'server-${_next++}',
        name: (body as Map)['name'] as String,
        gender: body['gender'] as String,
        birthDate: body['birthDate'] as String,
        stage: (body['condition'] as Map)['stage'] as String,
      );
      profiles.add(created);
      return _json(created, 201);
    }

    // /api/v1/profiles/{id}
    final id = segments[3];
    final index = profiles.indexWhere((p) => p['profileId'] == id);
    if (index < 0) {
      return _json({
        'schemaVersion': 1,
        'errorCode': 'PROFILE_NOT_FOUND',
        'message': '테스트용 오류',
        'requestId': 'req_test',
        'retryable': false,
      }, 404);
    }
    switch (request.method) {
      case 'GET':
        return _json(profiles[index], 200);
      case 'PATCH':
        final changes = Map<String, Object?>.from(body as Map);
        final current = Map<String, Object?>.from(profiles[index]);
        final condition = changes.remove('condition') as Map?;
        current.addAll(changes);
        if (condition != null) {
          current['condition'] = {
            ...(current['condition'] as Map),
            ...condition,
          };
        }
        profiles[index] = current;
        return _json(current, 200);
      case 'DELETE':
        profiles.removeAt(index);
        return http.Response('', 204);
    }
    return _json({}, 405);
  }

  /// 명세의 Profile 응답 하나를 만든다.
  static Map<String, Object?> profile({
    required String id,
    String name = '김새록',
    String gender = 'female',
    String birthDate = '1943-03-12',
    String stage = 'mildDementia',
    String setupStatus = 'inProgress',
    String? occupation,
    String? hometown,
    String? hobby,
    String? family,
  }) => {
    'schemaVersion': 1,
    'profileId': id,
    'setupStatus': setupStatus,
    'name': name,
    'gender': gender,
    'birthDate': birthDate,
    'condition': {'stage': stage, 'symptomNote': null},
    'occupation': occupation,
    'hometown': hometown,
    'hobby': hobby,
    'family': family,
    'lifeFacts': <Object>[],
    'photos': <Object>[],
    'createdAt': '2026-10-13T09:00:00+09:00',
  };

  static http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
}
