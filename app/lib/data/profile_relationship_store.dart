/// 보호자가 적은 관계("어머니", "아버지")를 계정과 프로필마다 단말에 기억한다.
///
/// 관계는 앱에서 `김철수님 (아버지)` 처럼 부를 때만 쓰는 별명이라 서버에 보내지
/// 않는다(`api-spec.md` 2절에 없는 값). 서버 목록을 불러올 때 여기서 읽어
/// 기본 정보에 붙인다. 화면과 테스트는 [ProfileRelationshipStore] 만 보고
/// 저장소를 직접 부르지 않는다(`ADR-005` 의 주입 방식과 같다).
///
/// 단말 보관 범위는 아직 정해지지 않아(`docs/architecture/README.md`) 개발과
/// 테스트를 위한 가정이다. 저장한 값은 로그에 남기지 않는다(`CLAUDE.md`).
/// 프로필을 지우면 그 값을, 탈퇴하면 계정의 값을 모두 지운다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProfileRelationshipStore {
  /// [accountId] 의 서버 프로필 [profileId] 에 적은 관계다. 없거나 읽을 수
  /// 없으면 `null` 이다.
  Future<String?> read(String accountId, String profileId);

  /// [relationship] 이 `null` 이면 지운다.
  Future<void> write(String accountId, String profileId, String? relationship);

  /// 계정을 탈퇴했을 때 그 계정의 관계를 모두 지운다.
  Future<void> clear(String accountId);
}

/// 단말의 보안 저장소에 둔다. 세션, 고른 분과 같은 곳이다.
class SecureProfileRelationshipStore implements ProfileRelationshipStore {
  SecureProfileRelationshipStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// 계정마다 앞부분을 나눠 다른 계정의 값을 읽지 않는다. 프로필마다 키를
  /// 따로 두어 동시에 써도 서로 덮지 않는다.
  static String _prefixOf(String accountId) =>
      'saerok.profile.relationship.$accountId.';

  static String _keyOf(String accountId, String profileId) =>
      '${_prefixOf(accountId)}$profileId';

  @override
  Future<String?> read(String accountId, String profileId) async {
    try {
      final value = await _storage.read(key: _keyOf(accountId, profileId));
      return value == null || value.trim().isEmpty ? null : value;
    } catch (_) {
      // 읽지 못하면 이름만 부른다. 앱을 멈출 일은 아니다.
      return null;
    }
  }

  @override
  Future<void> write(
    String accountId,
    String profileId,
    String? relationship,
  ) async {
    final key = _keyOf(accountId, profileId);
    try {
      if (relationship == null || relationship.trim().isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: relationship);
      }
    } catch (_) {
      // 기억하지 못해도 지금 화면의 관계는 그대로 쓴다. 다음 실행에서 이름만
      // 보일 뿐이다.
    }
  }

  @override
  Future<void> clear(String accountId) async {
    final prefix = _prefixOf(accountId);
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(prefix))) {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // 남은 값은 그 계정으로 다시 로그인해야만 읽힌다.
    }
  }
}

final profileRelationshipStoreProvider = Provider<ProfileRelationshipStore>(
  (ref) => SecureProfileRelationshipStore(),
);
