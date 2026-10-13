// 프로필 API(`lib/data/profile_api.dart`)가 명세 2절대로 요청하고 읽는지 확인한다.
//
// 서버 대신 `MockClient` 를 쓴다. 값은 모두 합성 데이터다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/data/profile_api.dart';
import 'package:saerok/data/providers.dart';

const _id = '00000000-0000-4000-8000-000000000101';

ProfileApi _api(Future<http.Response> Function(http.Request request) handler) =>
    ProfileApi(
      ApiClient(
        authorization: () => 'Bearer test-token',
        baseUrl: 'http://api.test',
        client: MockClient(handler),
      ),
    );

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

/// 명세의 Profile 응답이다.
Map<String, Object?> _profile({
  String setupStatus = 'inProgress',
  String stage = 'mildDementia',
  String? occupation,
  String? family,
}) => {
  'schemaVersion': 1,
  'profileId': _id,
  'setupStatus': setupStatus,
  'name': '김새록',
  'gender': 'female',
  'birthDate': '1943-03-12',
  'condition': {'stage': stage, 'symptomNote': null},
  'occupation': occupation,
  'hometown': null,
  'hobby': null,
  'family': family,
  'lifeFacts': <Object>[],
  'photos': <Object>[],
  'createdAt': '2026-10-13T09:00:00+09:00',
};

const _info = EnteredBasicInfo(
  name: '김새록',
  gender: 'female',
  birthDate: '1943-03-12',
  stage: ConditionStage.mildDementia,
);

void main() {
  test('2-1 목록을 만든 순서대로 읽는다', () async {
    late http.Request sent;
    final api = _api((request) async {
      sent = request;
      return _json({
        'schemaVersion': 1,
        'profiles': [
          {
            'profileId': _id,
            'name': '김새록',
            'gender': 'female',
            'setupStatus': 'completed',
          },
        ],
      }, 200);
    });

    final profiles = await api.list();

    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/v1/profiles');
    expect(profiles.single.profileId, _id);
    expect(profiles.single.setupStatus, SetupStatus.completed);
  });

  test('2-2 기본 정보로 만들고 메모는 비워 보낸다', () async {
    late http.Request sent;
    final api = _api((request) async {
      sent = request;
      return _json(_profile(), 201);
    });

    final profile = await api.create(_info);

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/profiles');
    expect(jsonDecode(sent.body), {
      'name': '김새록',
      'gender': 'female',
      'birthDate': '1943-03-12',
      'condition': {'stage': 'mildDementia', 'symptomNote': null},
    });
    expect(profile.profileId, _id);
    expect(profile.setupStatus, SetupStatus.inProgress);
    expect(profile.basicInfo.stage, ConditionStage.mildDementia);
  });

  test('2-3 세부 정보 네 항목을 읽고 없는 항목은 null 이다', () async {
    final api = _api(
      (request) async => _json(
        _profile(occupation: '재봉 일을 오래 하셨어요.', family: '2남 1녀를 두셨어요.'),
        200,
      ),
    );

    final profile = await api.get(_id);

    expect(profile.details.occupation, '재봉 일을 오래 하셨어요.');
    expect(profile.details.family, '2남 1녀를 두셨어요.');
    expect(profile.details.hometown, isNull);
    expect(profile.details.hobby, isNull);
  });

  test('2-4 기본 정보를 고칠 때 메모는 보내지 않아 그대로 둔다', () async {
    late http.Request sent;
    final api = _api((request) async {
      sent = request;
      return _json(_profile(), 200);
    });

    await api.updateBasicInfo(_id, _info);

    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/v1/profiles/$_id');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['condition'], {'stage': 'mildDementia'});
    expect(
      (body['condition'] as Map).containsKey('symptomNote'),
      isFalse,
      reason: 'symptomNote 를 빼면 서버가 저장된 메모를 그대로 둔다',
    );
    expect(body.containsKey('occupation'), isFalse, reason: '세부 정보는 보내지 않는다');
  });

  test('2-4 세부 정보를 고칠 때 비운 항목은 null 로 보내 지운다', () async {
    late http.Request sent;
    final api = _api((request) async {
      sent = request;
      return _json(_profile(occupation: '수선집을 하셨어요.'), 200);
    });

    await api.updateDetails(
      _id,
      const EnteredDetails(occupation: '수선집을 하셨어요.'),
    );

    expect(jsonDecode(sent.body), {
      'occupation': '수선집을 하셨어요.',
      'hometown': null,
      'hobby': null,
      'family': null,
    });
  });

  test('2-8 프로필을 지운다', () async {
    late http.Request sent;
    final api = _api((request) async {
      sent = request;
      return http.Response('', 204);
    });

    await api.delete(_id);

    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/api/v1/profiles/$_id');
  });

  test('3명을 넘기면 서버의 오류 코드를 그대로 전한다', () async {
    final api = _api(
      (request) async => _json({
        'schemaVersion': 1,
        'errorCode': 'PROFILE_LIMIT_EXCEEDED',
        'message': '테스트용 오류',
        'requestId': 'req_test',
        'retryable': false,
      }, 409),
    );

    expect(
      api.create(_info),
      throwsA(
        isA<ApiServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 409)
            .having((f) => f.errorCode, 'errorCode', 'PROFILE_LIMIT_EXCEEDED'),
      ),
    );
  });

  test('응답 모양이 다르면 성공으로 넘기지 않는다', () async {
    final missingName = _profile()..remove('name');
    final unknownStage = _profile(stage: 'severe');

    expect(
      _api((request) async => _json(missingName, 200)).get(_id),
      throwsA(isA<ApiUnexpectedResponseFailure>()),
    );
    expect(
      _api((request) async => _json(unknownStage, 200)).get(_id),
      throwsA(isA<ApiUnexpectedResponseFailure>()),
      reason: '모르는 상태를 다른 값으로 바꿔 넣지 않는다',
    );
  });
}
