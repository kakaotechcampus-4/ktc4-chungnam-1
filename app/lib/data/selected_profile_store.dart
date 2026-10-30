/// 마지막으로 고른 어르신을 계정마다 단말에 기억한다.
///
/// 앱을 다시 켜면 첫 분으로 돌아가, 모르고 녹음하면 면회 기록이 다른 어르신에게
/// 저장될 수 있다(이슈 144). 화면과 테스트는 [SelectedProfileStore] 만 보고
/// 저장소를 직접 부르지 않는다(`ADR-005` 의 주입 방식과 같다).
///
/// 보관하는 값은 계정마다 서버 프로필 ID 하나다. 이름이나 사진은 두지 않는다.
/// 단말 보관 범위는 아직 정해지지 않아(`docs/architecture/README.md`) 개발과
/// 테스트를 위한 가정이다. 저장한 값은 로그에 남기지 않는다(`CLAUDE.md`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SelectedProfileStore {
  /// [accountId] 가 마지막으로 고른 서버 프로필 ID 다. 없거나 읽을 수 없으면
  /// `null` 이다.
  Future<String?> read(String accountId);

  Future<void> write(String accountId, String profileId);

  /// 고른 분이 없어졌거나 계정을 탈퇴했을 때 쓴다.
  Future<void> clear(String accountId);
}

/// 단말의 보안 저장소에 둔다. 세션과 같은 곳이다(`SecureSessionStore`).
class SecureSelectedProfileStore implements SelectedProfileStore {
  SecureSelectedProfileStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// 계정마다 키를 나눠 다른 계정의 선택을 읽지 않는다.
  static String _keyOf(String accountId) =>
      'saerok.profile.selected.$accountId';

  @override
  Future<String?> read(String accountId) async {
    try {
      final value = await _storage.read(key: _keyOf(accountId));
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      // 읽지 못하면 첫 분으로 연다. 앱을 멈출 일은 아니다.
      return null;
    }
  }

  @override
  Future<void> write(String accountId, String profileId) async {
    try {
      await _storage.write(key: _keyOf(accountId), value: profileId);
    } catch (_) {
      // 기억하지 못해도 지금 고른 분은 그대로 쓴다. 다음 실행에서 첫 분으로
      // 열릴 뿐이다.
    }
  }

  @override
  Future<void> clear(String accountId) async {
    try {
      await _storage.delete(key: _keyOf(accountId));
    } catch (_) {
      // 남은 값은 다음에 읽을 때 목록에 없으면 쓰지 않는다.
    }
  }
}

final selectedProfileStoreProvider = Provider<SelectedProfileStore>(
  (ref) => SecureSelectedProfileStore(),
);
