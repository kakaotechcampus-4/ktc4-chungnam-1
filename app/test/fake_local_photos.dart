// 이 기기에만 두는 사진 보관소의 대역이다. 파일을 건드리지 않고 메모리에만 둔다.

import 'package:saerok/features/local_photos/local_photos.dart';

/// 고른 경로를 그대로 남긴 경로로 돌려준다.
class FakeLocalPhotos implements LocalPhotos {
  /// 열쇠는 [localPhotoKey], 값은 경로다.
  final saved = <String, String>{};

  /// 탈퇴로 지운 계정.
  final forgottenAccounts = <String>[];

  @override
  bool supported = true;

  @override
  Future<Map<String, String>> load() async => {...saved};

  @override
  Future<String> keep(String profileId, String slot, String pickedPath) async {
    saved[localPhotoKey(profileId, slot)] = pickedPath;
    return pickedPath;
  }

  @override
  Future<void> remove(String profileId, String slot) async =>
      saved.remove(localPhotoKey(profileId, slot));

  @override
  Future<void> forgetProfile(String profileId) async =>
      saved.removeWhere((key, _) => key.startsWith('$profileId/'));

  @override
  Future<void> forgetAccount(String accountId) async {
    forgottenAccounts.add(accountId);
    saved.clear();
  }
}
