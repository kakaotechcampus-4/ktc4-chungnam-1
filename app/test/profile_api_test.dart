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
  List<Object> lifeFacts = const [],
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
  'lifeFacts': lifeFacts,
  'photos': <Object>[],
  'createdAt': '2026-10-13T09:00:00+09:00',
};

const _factId = '00000000-0000-4000-8000-000000000111';

/// 명세의 LifeFact 응답이다.
Map<String, Object?> _fact({
  String storyCategory = 'work',
  String title = '단골손님',
  int imageNumber = 3,
}) => {
  'schemaVersion': 1,
  'factId': _factId,
  'profileId': _id,
  'storyCategory': storyCategory,
  'title': title,
  'content': '수선집에 오래 다닌 단골손님이 많았어요.',
  'imageNumber': imageNumber,
  'createdAt': '2026-08-21T12:10:00+09:00',
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

  group('일대기 이야기', () {
    test('2-3 담은 이야기를 분류, 그림 번호와 함께 읽는다', () async {
      final api = _api(
        (request) async => _json(
          _profile(
            lifeFacts: [
              _fact(),
              {
                ..._fact(storyCategory: 'travel', imageNumber: 1),
                'factId': 'fact-2',
              },
            ],
          ),
          200,
        ),
      );

      final profile = await api.get(_id);

      expect(profile.lifeFacts.map((f) => f.factId), [_factId, 'fact-2']);
      final first = profile.lifeFacts.first;
      expect(first.storyCategory, 'work');
      expect(first.title, '단골손님');
      expect(first.content, '수선집에 오래 다닌 단골손님이 많았어요.');
      expect(first.imageNumber, 3);
      expect(first.createdAt, '2026-08-21T12:10:00+09:00');
      expect(profile.lifeFacts.last.storyCategory, 'travel');
    });

    test('2-6 네 항목을 보내고 서버가 만든 이야기를 받는다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json(_fact(), 201);
      });

      final fact = await api.createLifeFact(
        _id,
        storyCategory: 'work',
        title: '단골손님',
        content: '수선집에 오래 다닌 단골손님이 많았어요.',
        imageNumber: 3,
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/profiles/$_id/life-facts');
      expect(jsonDecode(sent.body), {
        'storyCategory': 'work',
        'title': '단골손님',
        'content': '수선집에 오래 다닌 단골손님이 많았어요.',
        'imageNumber': 3,
      });
      expect(fact.factId, _factId);
    });

    test('2-7 네 항목을 모두 보내고 고친 이야기를 받는다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return _json(
          _fact(storyCategory: 'friend', title: '계모임', imageNumber: 2),
          200,
        );
      });

      final fact = await api.updateLifeFact(
        _factId,
        storyCategory: 'friend',
        title: '계모임',
        content: '수선집에 오래 다닌 단골손님이 많았어요.',
        imageNumber: 2,
      );

      expect(sent.method, 'PATCH');
      expect(sent.url.path, '/api/v1/life-facts/$_factId');
      expect(jsonDecode(sent.body), {
        'storyCategory': 'friend',
        'title': '계모임',
        'content': '수선집에 오래 다닌 단골손님이 많았어요.',
        'imageNumber': 2,
      });
      expect(fact.storyCategory, 'friend');
      expect(fact.imageNumber, 2);
    });

    test('2-9 이야기를 지운다', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return http.Response('', 204);
      });

      await api.deleteLifeFact(_factId);

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/api/v1/life-facts/$_factId');
    });

    test('없는 이야기는 서버의 오류 코드를 그대로 전한다', () async {
      final api = _api(
        (request) async => _json({
          'schemaVersion': 1,
          'errorCode': 'LIFE_FACT_NOT_FOUND',
          'message': '테스트용 오류',
          'requestId': 'req_test',
          'retryable': false,
        }, 404),
      );

      await expectLater(
        api.deleteLifeFact(_factId),
        throwsA(
          isA<ApiServerFailure>()
              .having((f) => f.statusCode, 'statusCode', 404)
              .having((f) => f.errorCode, 'errorCode', 'LIFE_FACT_NOT_FOUND'),
        ),
      );
      expect(
        profileFailureMessage(
          const ApiServerFailure(
            statusCode: 404,
            errorCode: 'LIFE_FACT_NOT_FOUND',
          ),
        ),
        '이야기를 찾지 못했어요. 이미 지운 이야기일 수 있어요.',
      );
    });

    test('이야기 응답 모양이 다르면 성공으로 넘기지 않는다', () async {
      final missingTitle = _fact()..remove('title');
      final textNumber = {..._fact(), 'imageNumber': '3'};

      expect(
        _api((request) async => _json(missingTitle, 201)).createLifeFact(
          _id,
          storyCategory: 'work',
          title: '단골손님',
          content: '내용',
          imageNumber: 3,
        ),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
      expect(
        _api(
          (request) async => _json(_profile(lifeFacts: [textNumber]), 200),
        ).get(_id),
        throwsA(isA<ApiUnexpectedResponseFailure>()),
      );
    });
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
