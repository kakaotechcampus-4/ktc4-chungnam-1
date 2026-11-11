// 지운 실패 알림을 기억하는 단말 저장소의 대역이다. 메모리에만 둔다.
//
// 실제 보안 저장소는 플랫폼 채널이 필요해 위젯 테스트에서 끝나지 않는다.

import 'package:saerok/data/dismissed_failed_report_store.dart';

class FakeDismissedFailedReportStore implements DismissedFailedReportStore {
  /// 계정마다 지운 회차 ID.
  final values = <String, Set<String>>{};

  @override
  Future<Set<String>> read(String accountId) async => {...?values[accountId]};

  @override
  Future<void> add(String accountId, String sessionId) async =>
      (values[accountId] ??= {}).add(sessionId);

  @override
  Future<void> clear(String accountId) async => values.remove(accountId);
}
