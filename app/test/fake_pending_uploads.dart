// 기기에 남기는 녹음 기록의 대역이다. 파일을 건드리지 않고 메모리에만 둔다.

import 'package:saerok/features/visit/pending_uploads.dart';

class FakePendingUploads implements PendingUploads {
  final saved = <String, PendingUpload>{};

  /// 지운 녹음 파일 경로.
  final removedPaths = <String>[];

  @override
  Future<void> save(PendingUpload upload) async =>
      saved[upload.sessionId] = upload;

  @override
  Future<PendingUpload?> find(String sessionId) async => saved[sessionId];

  @override
  Future<void> remove(String sessionId, {String? audioPath}) async {
    final upload = saved.remove(sessionId);
    final path = audioPath ?? upload?.audioPath;
    if (path != null) removedPaths.add(path);
  }

  /// 탈퇴로 지운 계정.
  final forgottenAccounts = <String>[];

  @override
  Future<void> forgetAccount(String accountId) async {
    forgottenAccounts.add(accountId);
    for (final upload in saved.values) {
      removedPaths.add(upload.audioPath);
    }
    saved.clear();
  }
}
