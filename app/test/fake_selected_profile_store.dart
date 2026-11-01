// 마지막으로 고른 어르신을 기억하는 단말 저장소의 대역이다. 메모리에만 둔다.
//
// 실제 보안 저장소는 플랫폼 채널이 필요해 위젯 테스트에서 끝나지 않는다.

import 'dart:async';

import 'package:saerok/data/selected_profile_store.dart';

class FakeSelectedProfileStore implements SelectedProfileStore {
  /// 계정마다 고른 서버 프로필 ID.
  final values = <String, String>{};

  /// 채우면 읽기가 이 값을 기다린다. 서버보다 늦게 읽히는 경우다.
  Completer<void>? readGate;

  /// 저장소를 열지 못하는 단말이다. 실제 구현처럼 실패를 삼킨다.
  bool broken = false;

  @override
  Future<String?> read(String accountId) async {
    await readGate?.future;
    return broken ? null : values[accountId];
  }

  @override
  Future<void> write(String accountId, String profileId) async {
    if (!broken) values[accountId] = profileId;
  }

  @override
  Future<void> clear(String accountId) async {
    if (!broken) values.remove(accountId);
  }
}
