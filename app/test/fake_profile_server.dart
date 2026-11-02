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

  /// [failures] 중 서버가 다시 시도해도 된다고 알릴 `errorCode`.
  final retryableErrors = <String>{};

  /// 사진 업로드(3-1) 요청의 multipart 본문.
  final uploads = <String>[];

  /// 사진마다 3-2 로 물을 때 차례로 돌려줄 `analysisStatus`. 마지막 값은 계속
  /// 돌려준다. `completed` 가 되면 합성 설명을 붙인다.
  final analysisResults = <String, List<String>>{};

  /// 정해 두면 그 요청은 이 Future 가 끝난 뒤에 답한다. 키는 `METHOD path` 다.
  final holds = <String, Future<void>>{};

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
    final multipart =
        request.headers['content-type']?.startsWith('multipart/') ?? false;
    // 사진 바이트는 utf-8 이 아니라 그대로 읽는다.
    final text = multipart ? latin1.decode(request.bodyBytes) : request.body;
    final body = text.isEmpty || multipart ? null : jsonDecode(text);
    requests.add((method: request.method, path: request.url.path, body: body));
    if (offline) throw http.ClientException('오프라인');
    await holds['${request.method} ${request.url.path}'];

    final failure = failures['${request.method} ${request.url.path}'];
    if (failure != null) {
      return _json({
        'schemaVersion': 1,
        'errorCode': failure.errorCode,
        'message': '테스트용 오류',
        'requestId': 'req_test',
        'retryable': retryableErrors.contains(failure.errorCode),
      }, failure.status);
    }

    final segments = request.url.pathSegments;
    // /api/v1/profile-photos/{photoId}
    if (segments.length == 4 && segments[2] == 'profile-photos') {
      return _photo(segments[3]);
    }
    // /api/v1/life-facts/{factId}
    if (segments.length == 4 && segments[2] == 'life-facts') {
      return _lifeFact(request.method, segments[3], body);
    }

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
    // /api/v1/profiles/{id}/photos
    if (segments.length == 5 && segments[4] == 'photos') {
      uploads.add(text);
      final photo = <String, Object?>{
        'schemaVersion': 1,
        'photoId': 'photo-${_next++}',
        'profileId': id,
        'imageUrl': 'https://example.test/photo.jpg',
        'imageUrlExpiresAt': '2026-10-18T10:15:00+09:00',
        'analysisStatus': 'pending',
        'description': null,
        'error': null,
        'createdAt': '2026-10-18T10:00:00+09:00',
      };
      profiles[index] = {
        ...profiles[index],
        'photos': [...profiles[index]['photos'] as List, photo],
      };
      return _json(photo, 201);
    }
    // /api/v1/profiles/{id}/life-facts
    if (segments.length == 5 && request.method == 'POST') {
      final fact = {
        'schemaVersion': 1,
        'factId': 'fact-${_next++}',
        'profileId': id,
        ...(body as Map).cast<String, Object?>(),
        'createdAt': '2026-10-18T10:00:00+09:00',
      };
      profiles[index] = {
        ...profiles[index],
        'lifeFacts': [...profiles[index]['lifeFacts'] as List, fact],
      };
      return _json(fact, 201);
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

  /// 3-2. [analysisResults] 대로 분석 상태를 바꾼 사진을 돌려준다.
  http.Response _photo(String photoId) {
    for (var p = 0; p < profiles.length; p++) {
      final photos = [...profiles[p]['photos'] as List];
      final i = photos.indexWhere(
        (photo) => (photo as Map)['photoId'] == photoId,
      );
      if (i < 0) continue;
      final queue = analysisResults[photoId];
      final status = queue == null || queue.isEmpty
          ? (photos[i] as Map)['analysisStatus']
          : queue.length > 1
          ? queue.removeAt(0)
          : queue.single;
      final updated = {
        ...(photos[i] as Map).cast<String, Object?>(),
        'analysisStatus': status,
        'description': status == 'completed' ? '합성 사진 설명이에요.' : null,
        'error': status == 'failed'
            ? {'errorCode': 'IMAGE_ANALYSIS_FAILED'}
            : null,
      };
      photos[i] = updated;
      profiles[p] = {...profiles[p], 'photos': photos};
      return _json(updated, 200);
    }
    return _json({
      'schemaVersion': 1,
      'errorCode': 'PROFILE_PHOTO_NOT_FOUND',
      'message': '테스트용 오류',
      'requestId': 'req_test',
      'retryable': false,
    }, 404);
  }

  /// 2-7 고치기와 2-9 지우기. 어느 분의 이야기든 `factId` 로 찾는다.
  http.Response _lifeFact(String method, String factId, Object? body) {
    for (var i = 0; i < profiles.length; i++) {
      final facts = (profiles[i]['lifeFacts'] as List)
          .cast<Map<String, Object?>>();
      final fact = facts.where((f) => f['factId'] == factId).firstOrNull;
      if (fact == null) continue;
      final updated = {...fact, ...?(body as Map?)?.cast<String, Object?>()};
      profiles[i] = {
        ...profiles[i],
        'lifeFacts': [
          for (final f in facts)
            if (f != fact) f else if (method == 'PATCH') updated,
        ],
      };
      return method == 'DELETE' ? http.Response('', 204) : _json(updated, 200);
    }
    return _json({
      'schemaVersion': 1,
      'errorCode': 'LIFE_FACT_NOT_FOUND',
      'message': '테스트용 오류',
      'requestId': 'req_test',
      'retryable': false,
    }, 404);
  }

  /// 명세의 LifeFact 응답 하나를 만든다.
  static Map<String, Object?> lifeFact({
    required String id,
    required String profileId,
    String storyCategory = 'work',
    String title = '단골손님',
    String content = '수선집에 오래 다닌 단골손님이 많았어요.',
    int imageNumber = 3,
    String createdAt = '2026-09-01T10:00:00+09:00',
  }) => {
    'schemaVersion': 1,
    'factId': id,
    'profileId': profileId,
    'storyCategory': storyCategory,
    'title': title,
    'content': content,
    'imageNumber': imageNumber,
    'createdAt': createdAt,
  };

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
    List<Map<String, Object?>> lifeFacts = const [],
    List<Map<String, Object?>> photos = const [],
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
    'lifeFacts': lifeFacts,
    'photos': photos,
    'createdAt': '2026-10-13T09:00:00+09:00',
  };

  static http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// 명세의 ProfilePhoto 하나를 만든다.
  static Map<String, Object?> photo({
    required String id,
    String profileId = 'p1',
    String analysisStatus = 'completed',
  }) => {
    'schemaVersion': 1,
    'photoId': id,
    'profileId': profileId,
    'imageUrl': 'https://example.test/$id.jpg',
    'imageUrlExpiresAt': '2026-10-18T10:15:00+09:00',
    'analysisStatus': analysisStatus,
    'description': analysisStatus == 'completed' ? '합성 사진 설명이에요.' : null,
    'error': null,
    'createdAt': '2026-10-18T10:00:00+09:00',
  };
}
