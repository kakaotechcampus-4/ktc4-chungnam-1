// 관계를 기억하는 단말 저장소의 대역이다. 메모리에만 둔다.
//
// 실제 보안 저장소는 플랫폼 채널이 필요해 위젯 테스트에서 끝나지 않는다.

import 'package:saerok/data/profile_relationship_store.dart';

class FakeProfileRelationshipStore implements ProfileRelationshipStore {
  /// 계정마다, 서버 프로필 ID 마다 적은 관계.
  final values = <String, Map<String, String>>{};

  @override
  Future<String?> read(String accountId, String profileId) async =>
      values[accountId]?[profileId];

  @override
  Future<void> write(
    String accountId,
    String profileId,
    String? relationship,
  ) async {
    final account = values.putIfAbsent(accountId, () => {});
    if (relationship == null || relationship.trim().isEmpty) {
      account.remove(profileId);
    } else {
      account[profileId] = relationship;
    }
  }

  @override
  Future<void> clear(String accountId) async => values.remove(accountId);
}
