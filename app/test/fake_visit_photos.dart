// 기기에 남기는 면회 사진 보관소의 대역이다. 파일을 건드리지 않고 메모리에만 둔다.

import 'package:saerok/features/visit/visit_photos.dart';

/// 카메라가 준 경로를 그대로 남긴 경로로 돌려준다.
class FakeVisitPhotos implements VisitPhotos {
  /// 남겨 둔 사진. 값은 올린 회차 ID 이며 올리지 않았으면 `null` 이다.
  final kept = <String, String?>{};

  /// 지운 사진 경로.
  final discarded = <String>[];

  /// 탈퇴로 지운 계정.
  final forgottenAccounts = <String>[];

  @override
  Future<String> keep(String capturedPath) async {
    kept[capturedPath] = null;
    return capturedPath;
  }

  @override
  Future<void> markUploaded(String path, String sessionId) async {
    kept[path] = sessionId;
  }

  @override
  Future<void> discard(String path) async {
    if (kept[path] != null) return;
    kept.remove(path);
    discarded.add(path);
  }

  @override
  Future<void> forgetAccount(String accountId) async {
    forgottenAccounts.add(accountId);
    discarded.addAll(kept.keys);
    kept.clear();
  }
}
