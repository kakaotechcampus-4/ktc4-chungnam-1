// 등록하다 멈춘 입력 초안을 두는 단말 저장소의 대역이다. 메모리에만 둔다.
//
// 실제 보안 저장소는 플랫폼 채널이 필요해 위젯 테스트에서 끝나지 않는다. 앱을
// 다시 켜는 것은 같은 대역으로 새 컨테이너나 화면을 만드는 것으로 대신한다.

import 'package:saerok/data/setup_draft_store.dart';

class FakeSetupDraftStore implements SetupDraftStore {
  /// `계정/프로필` 마다 저장한 값. 실제 저장소처럼 인코딩한 글로 둔다.
  final values = <String, String>{};

  /// 받은 쓰기 수. 글자마다 쓰지 않고 모아 쓰는지 볼 때 쓴다.
  int writes = 0;

  static String keyOf(String accountId, String profileId) =>
      '$accountId/$profileId';

  SavedSetupDraft? draftOf(String accountId, String profileId) =>
      SavedSetupDraft.decode(values[keyOf(accountId, profileId)]);

  @override
  Future<SavedSetupDraft?> read(String accountId, String profileId) async =>
      draftOf(accountId, profileId);

  @override
  Future<void> write(
    String accountId,
    String profileId,
    SavedSetupDraft draft,
  ) async {
    writes += 1;
    values[keyOf(accountId, profileId)] = draft.encode();
  }

  @override
  Future<void> clear(String accountId, String profileId) async =>
      values.remove(keyOf(accountId, profileId));

  @override
  Future<void> clearAccount(String accountId) async =>
      values.removeWhere((key, _) => key.startsWith('$accountId/'));
}
