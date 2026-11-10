// 녹음 파일 공유 창의 대역이다. 공유 창을 열지 않고 연 파일과 지운 횟수만 남긴다.

import 'package:saerok/features/visit/recording_share.dart';

/// 연 파일을 남기고 정해 둔 결과를 돌려준다.
class FakeRecordingShare implements RecordingShare {
  FakeRecordingShare({this.result = RecordingShareResult.opened, this.onShare});

  final RecordingShareResult result;

  /// 공유하는 동안 할 일. 그 사이 파일이 사라진 경우를 흉내 낼 때 쓴다.
  final void Function()? onShare;

  /// 공유 창을 연 파일 경로.
  final paths = <String>[];

  /// 공유하며 남긴 사본을 지운 횟수.
  int forgotCopies = 0;

  @override
  Future<RecordingShareResult> share(String path) async {
    paths.add(path);
    onShare?.call();
    return result;
  }

  @override
  Future<void> forgetCopies() async => forgotCopies++;
}
