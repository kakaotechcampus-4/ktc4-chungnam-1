// 기기에 남기는 면회 사진 보관소의 대역이다. 파일을 건드리지 않고 메모리에만 둔다.

import 'package:saerok/features/visit/visit_photos.dart';

/// 카메라가 준 경로를 그대로 남긴 경로로 돌려준다. 지우는 기준은
/// [DeviceVisitPhotos] 와 같다.
class FakeVisitPhotos implements VisitPhotos {
  /// 남겨 둔 사진. 값은 올린 회차 ID 이며 올리지 않았으면 `null` 이다.
  final kept = <String, String?>{};

  /// [kept] 가운데 갤러리에 원본을 남긴 사진.
  final inGallery = <String>{};

  /// 지운 사진 경로.
  final discarded = <String>[];

  /// 탈퇴로 지운 계정.
  final forgottenAccounts = <String>[];

  /// 새 면회를 시작하며 정리한 횟수.
  int tidied = 0;

  /// 있으면 [keep] 이 이 실패로 끝난다.
  Object? keepFailure;

  @override
  Future<String> keep(String capturedPath, {required bool inGallery}) async {
    if (keepFailure case final failure?) throw failure;
    kept[capturedPath] = null;
    if (inGallery) this.inGallery.add(capturedPath);
    return capturedPath;
  }

  @override
  Future<void> markUploaded(String path, String sessionId) async {
    if (inGallery.contains(path)) return _remove(path);
    kept[path] = sessionId;
  }

  @override
  Future<void> discard(String path) async {
    if (inGallery.contains(path)) _remove(path);
  }

  @override
  Future<void> tidy() async {
    tidied++;
    inGallery.toList().forEach(_remove);
  }

  @override
  Future<void> forgetAccount(String accountId) async {
    forgottenAccounts.add(accountId);
    discarded.addAll(kept.keys);
    kept.clear();
    inGallery.clear();
  }

  void _remove(String path) {
    inGallery.remove(path);
    kept.remove(path);
    discarded.add(path);
  }
}
