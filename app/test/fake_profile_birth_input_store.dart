// 나이로 입력했다는 표시를 기억하는 단말 저장소의 대역이다. 메모리에만 둔다.

import 'package:saerok/data/profile_birth_input_store.dart';

class FakeProfileBirthInputStore implements ProfileBirthInputStore {
  /// 계정마다 나이로 입력한 서버 프로필 ID.
  final values = <String, Set<String>>{};

  @override
  Future<bool> readByAge(String accountId, String profileId) async =>
      values[accountId]?.contains(profileId) ?? false;

  @override
  Future<void> writeByAge(
    String accountId,
    String profileId,
    bool byAge,
  ) async {
    final account = values.putIfAbsent(accountId, () => {});
    if (byAge) {
      account.add(profileId);
    } else {
      account.remove(profileId);
    }
  }

  @override
  Future<void> clear(String accountId) async => values.remove(accountId);
}
