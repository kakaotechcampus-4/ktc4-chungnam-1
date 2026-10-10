import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 보호자가 고친 사진 설명을 저장한다.
///
/// **저장 API 는 아직 없다.** AI 가 만든 설명을 보호자가 확인하거나 고치는 방식과
/// 확인 여부의 저장 위치(`docs/architecture/api-spec.md` 3-3)는 PM 확인 뒤 정한다.
/// 그때까지는 [MockPhotoDescriptionStore] 가 앱 안에서만 저장한 것으로 친다.
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
  (ref) => const MockPhotoDescriptionStore(),
);

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
