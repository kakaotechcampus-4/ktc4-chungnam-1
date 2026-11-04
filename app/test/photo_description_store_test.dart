import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saerok/data/api_client.dart';
import 'package:saerok/data/models.dart';
import 'package:saerok/features/profile/photo_description_store.dart';

void main() {
  test('서버에 정정한 설명을 보내고 저장 응답을 확인한다', () async {
    final client = ApiClient(
      authorization: () => 'Bearer synthetic',
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/profile-photos/photo-1/description');
        expect(jsonDecode(request.body), {'description': '직접 고친 설명'});
        return http.Response(
          jsonEncode({
            'photoId': 'photo-1',
            'description': '직접 고친 설명',
            'descriptionSource': 'caregiver',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await ServerPhotoDescriptionStore(
      client,
    ).save(photoId: 'photo-1', description: ' 직접 고친 설명 ');
  });

  test('저장을 거절하거나 다른 사진 응답이면 성공으로 처리하지 않는다', () async {
    for (final response in [
      http.Response(
        jsonEncode({'errorCode': 'CARD_GENERATION_IN_PROGRESS'}),
        409,
      ),
      http.Response(
        jsonEncode({
          'photoId': 'different',
          'description': '수정',
          'descriptionSource': 'caregiver',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ]) {
      final client = ApiClient(
        authorization: () => 'Bearer synthetic',
        client: MockClient((_) async => response),
      );
      await expectLater(
        ServerPhotoDescriptionStore(
          client,
        ).save(photoId: 'photo-1', description: '수정'),
        throwsA(isA<ApiFailure>()),
      );
    }
  });

  test('서버가 돌려준 보호자 설명과 출처를 다시 읽는다', () {
    final photo = ProfilePhoto.fromJson({
      'photoId': 'photo-1',
      'profileId': 'profile-1',
      'imageUrl': 'asset:synthetic',
      'analysisStatus': 'failed',
      'description': '저장된 설명',
      'descriptionSource': 'caregiver',
      'createdAt': '2026-11-03T00:00:00Z',
    });
    expect(photo.description, '저장된 설명');
    expect(photo.descriptionSource, 'caregiver');
    expect(photo.forProfile('profile-2').descriptionSource, 'caregiver');
  });
}
