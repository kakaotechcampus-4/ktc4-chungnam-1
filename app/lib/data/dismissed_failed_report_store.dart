/// 사용자가 지운 `리포트를 만들지 못했어요` 알림을 계정마다 단말에 기억한다.
///
/// 서버는 알림을 지운 것을 저장하지 않는다(api-spec 미정 사항 2). 앱을 다시
/// 켜면 서버가 그 회차를 계속 `failed` 로 주므로, 지운 회차를 여기 남겨 다시
/// 띄우지 않는다. 화면과 테스트는 [DismissedFailedReportStore] 만 보고 저장소를
/// 직접 부르지 않는다(`ADR-005` 의 주입 방식과 같다).
///
/// 보관하는 값은 계정마다 서버 회차 ID 목록이다. 실패 이유나 날짜는 두지 않는다.
/// 단말 보관 범위는 아직 정해지지 않아(`docs/architecture/README.md`) 개발과
/// 테스트를 위한 가정이다. 저장한 값은 로그에 남기지 않는다(`CLAUDE.md`).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DismissedFailedReportStore {
  /// [accountId] 가 지운 회차 ID 들이다. 없거나 읽을 수 없으면 비어 있다.
  Future<Set<String>> read(String accountId);

  /// [sessionId] 의 실패 알림을 지웠다.
  Future<void> add(String accountId, String sessionId);

  /// 계정을 탈퇴했을 때 쓴다.
  Future<void> clear(String accountId);
}

/// 단말의 보안 저장소에 둔다. 세션과 같은 곳이다(`SecureSessionStore`).
class SecureDismissedFailedReportStore implements DismissedFailedReportStore {
  SecureDismissedFailedReportStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// 오래된 것부터 버린다. 홈은 가장 최근 회차만 알리므로 지난 회차는 다시
  /// 뜨지 않는다.
  static const _limit = 50;

  /// 계정마다 키를 나눠 다른 계정의 기록을 읽지 않는다.
  static String _keyOf(String accountId) =>
      'saerok.report.dismissedFailed.$accountId';

  Future<List<String>> _list(String accountId) async {
    final value = await _storage.read(key: _keyOf(accountId));
    if (value == null || value.isEmpty) return [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return [];
    return [
      for (final id in decoded)
        if (id is String) id,
    ];
  }

  @override
  Future<Set<String>> read(String accountId) async {
    try {
      return (await _list(accountId)).toSet();
    } catch (_) {
      // 읽지 못하면 지운 알림이 다시 뜰 뿐이다. 앱을 멈출 일은 아니다.
      return {};
    }
  }

  @override
  Future<void> add(String accountId, String sessionId) async {
    try {
      List<String> ids;
      try {
        ids = await _list(accountId);
      } on FormatException {
        // 깨진 값은 버리고 새로 적는다.
        ids = [];
      }
      ids
        ..remove(sessionId)
        ..add(sessionId);
      final kept = ids.length > _limit ? ids.sublist(ids.length - _limit) : ids;
      await _storage.write(key: _keyOf(accountId), value: jsonEncode(kept));
    } catch (_) {
      // 기억하지 못해도 이번 실행에서는 지운 채로 둔다. 다음 실행에서 다시
      // 뜰 뿐이다.
    }
  }

  @override
  Future<void> clear(String accountId) async {
    try {
      await _storage.delete(key: _keyOf(accountId));
    } catch (_) {
      // 남은 값은 회차 ID 뿐이라 다른 계정이 읽지 않는다.
    }
  }
}

final dismissedFailedReportStoreProvider = Provider<DismissedFailedReportStore>(
  (ref) => SecureDismissedFailedReportStore(),
);
