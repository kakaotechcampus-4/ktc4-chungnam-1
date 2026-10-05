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

/// 보호자가 고쳐 저장한 설명을 `photoId` 별로 들고 있다.
///
/// 서버가 저장한 값을 다시 내려주기 전까지 화면은 이 값을 AI 설명보다 앞세운다.
class EditedPhotoDescriptions extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void put(String photoId, String description) =>
      state = {...state, photoId: description};
}

final editedPhotoDescriptionsProvider =
    NotifierProvider<EditedPhotoDescriptions, Map<String, String>>(
      EditedPhotoDescriptions.new,
    );
