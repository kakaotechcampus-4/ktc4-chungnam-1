// 기기에 남기는 녹음 기록의 대역이다. 파일을 건드리지 않고 메모리에만 둔다.

import 'package:saerok/features/visit/pending_uploads.dart';

class FakePendingUploads implements PendingUploads {
  /// 아직 보내지 못한 녹음.
  final saved = <String, PendingUpload>{};

  /// 서버가 받았거나 다시 받지 않아 보냈다고 적은 녹음. 파일은 남아 있다.
  final uploaded = <String, PendingUpload>{};

  /// 지운 녹음 파일 경로.
  final removedPaths = <String>[];

  @override
  Future<void> save(PendingUpload upload) async {
    uploaded.remove(upload.sessionId);
    saved[upload.sessionId] = upload;
  }

  @override
  Future<PendingUpload?> find(String sessionId) async => saved[sessionId];

  @override
  Future<void> markUploaded(PendingUpload upload) async {
    saved.remove(upload.sessionId);
    uploaded[upload.sessionId] = upload;
  }

  /// 탈퇴로 지운 계정.
  final forgottenAccounts = <String>[];

  @override
  Future<void> forgetAccount(String accountId) async {
    forgottenAccounts.add(accountId);
    for (final upload in [...saved.values, ...uploaded.values]) {
      removedPaths.add(upload.audioPath);
    }
    saved.clear();
    uploaded.clear();
  }
}
