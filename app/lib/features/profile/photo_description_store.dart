import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/api_client.dart';
import '../auth/auth_providers.dart';

/// 보호자가 고친 사진 설명을 저장한다.
///
/// 로그인 상태에서는 API 3-3의 저장 응답을 확인한다. 목 저장은 로그인 없이
/// 화면만 확인하는 모드에만 쓴다. 설명 수정을 별도 승인 단계로 만들지 않는다.
abstract interface class PhotoDescriptionStore {
  /// 실패하면 예외를 던진다.
  Future<void> save({required String photoId, required String description});
}

/// 서버에 보내지 않고 잠시 뒤 저장한 것으로 친다.
class MockPhotoDescriptionStore implements PhotoDescriptionStore {
  const MockPhotoDescriptionStore();

  static const _delay = Duration(milliseconds: 500);

  @override
  Future<void> save({required String photoId, required String description}) =>
      Future<void>.delayed(_delay);
}

final photoDescriptionStoreProvider = Provider<PhotoDescriptionStore>(
  (ref) => ref.watch(sessionProvider) == null
      ? const MockPhotoDescriptionStore()
      : ServerPhotoDescriptionStore(ref.watch(apiClientProvider)),
);

class ServerPhotoDescriptionStore implements PhotoDescriptionStore {
  const ServerPhotoDescriptionStore(this.client);
  final ApiClient client;

  @override
  Future<void> save({
    required String photoId,
    required String description,
  }) async {
    final response = await client.patch(
      '/api/v1/profile-photos/$photoId/description',
      {'description': description.trim()},
    );
    if (response['photoId'] != photoId ||
        response['description'] != description.trim() ||
        response['descriptionSource'] != 'caregiver') {
      throw const ApiUnexpectedResponseFailure('사진 설명 저장 응답 불일치');
    }
  }
}

/// 고친 설명 하나가 속한 자리. 같은 휴대폰을 쓰는 계정과 어르신마다 따로 둔다.
///
/// [accountId] 가 `null` 이면 서버 세션 없이 들어온 경우다.
typedef PhotoDescriptionKey = ({
  String? accountId,
  String profileId,
  String photoId,
});

/// 보호자가 고쳐 저장한 설명을 계정, 어르신, 사진마다 들고 있다.
///
/// 서버가 저장한 값을 다시 내려주기 전까지 화면은 이 값을 AI 설명보다 앞세운다.
/// 어르신 정보와 함께 앱이 켜져 있는 동안만 기억하고, 로그아웃이나 탈퇴로
/// 어르신 정보를 지울 때 함께 지운다(`forgetCareProfiles`).
class EditedPhotoDescriptions
    extends Notifier<Map<PhotoDescriptionKey, String>> {
  @override
  Map<PhotoDescriptionKey, String> build() => const {};

  void put(PhotoDescriptionKey key, String description) =>
      state = {...state, key: description};
}

final editedPhotoDescriptionsProvider =
    NotifierProvider<EditedPhotoDescriptions, Map<PhotoDescriptionKey, String>>(
      EditedPhotoDescriptions.new,
    );
