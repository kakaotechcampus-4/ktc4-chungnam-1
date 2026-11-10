/// 생년월일을 나이로 입력한 분인지 계정과 프로필마다 단말에 기억한다.
///
/// 나이로 입력하면 앱이 오늘에서 그 나이만큼 뺀 날을 `birthDate` 로 보낸다
/// (`birth_date.dart`). 서버 계약(2-2, 2-4)에는 이 표시가 없어 서버 값만으로는
/// 지어낸 날짜인지 알 수 없다. 화면이 날짜 대신 `82세(나이로 입력)` 로 보여주도록
/// 관계(`ProfileRelationshipStore`)와 같은 방식으로 단말에 둔다.
///
/// 단말 보관 범위는 아직 정해지지 않아(`docs/architecture/README.md`) 개발과
/// 테스트를 위한 가정이다. 프로필을 지우면 그 값을, 탈퇴하면 계정의 값을 모두
/// 지운다. 다른 휴대폰이나 앱을 다시 설치한 뒤에는 날짜로 보인다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProfileBirthInputStore {
  /// [accountId] 의 서버 프로필 [profileId] 를 나이로 입력했는지. 없거나 읽을 수
  /// 없으면 `false` 다.
  Future<bool> readByAge(String accountId, String profileId);

  /// [byAge] 가 `false` 면 지운다.
  Future<void> writeByAge(String accountId, String profileId, bool byAge);

  /// 계정을 탈퇴했을 때 그 계정의 값을 모두 지운다.
  Future<void> clear(String accountId);
}

/// 단말의 보안 저장소에 둔다. 관계와 같은 곳이다.
class SecureProfileBirthInputStore implements ProfileBirthInputStore {
  SecureProfileBirthInputStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _prefixOf(String accountId) =>
      'saerok.profile.birthByAge.$accountId.';

  static String _keyOf(String accountId, String profileId) =>
      '${_prefixOf(accountId)}$profileId';

  @override
  Future<bool> readByAge(String accountId, String profileId) async {
    try {
      return await _storage.read(key: _keyOf(accountId, profileId)) == '1';
    } catch (_) {
      // 읽지 못하면 날짜로 보여준다. 앱을 멈출 일은 아니다.
      return false;
    }
  }

  @override
  Future<void> writeByAge(
    String accountId,
    String profileId,
    bool byAge,
  ) async {
    final key = _keyOf(accountId, profileId);
    try {
      if (byAge) {
        await _storage.write(key: key, value: '1');
      } else {
        await _storage.delete(key: key);
      }
    } catch (_) {
      // 기억하지 못해도 지금 화면은 그대로 쓴다. 다음 실행에서 날짜로 보일
      // 뿐이다.
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

final profileBirthInputStoreProvider = Provider<ProfileBirthInputStore>(
  (ref) => SecureProfileBirthInputStore(),
);
