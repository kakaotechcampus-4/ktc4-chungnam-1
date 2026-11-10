import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/setup_draft_store.dart';

/// 입력 초안을 단말 저장소([SetupDraftStore])에 차례대로 쓴다.
///
/// 글로 쓰는 동안에는 글자마다 초안이 바뀐다. 쓰기를 프로필마다 한 줄로 세우고,
/// 기다리는 동안 바뀐 값은 마지막 것 하나만 쓴다. 지우기도 같은 줄에 세워, 등록을
/// 마친 뒤 늦게 끝난 쓰기가 지운 초안을 되살리지 않게 한다.
class SetupDraftKeeper {
  SetupDraftKeeper(this._store);

  final SetupDraftStore _store;

  /// 프로필마다 마지막으로 세운 일. 다음 일은 이것이 끝난 뒤에 한다.
  final _tails = <String, Future<void>>{};

  /// 아직 쓰지 않은 가장 새 초안.
  final _pending = <String, SavedSetupDraft>{};

  /// 마지막으로 쓰기로 한 초안. 같은 값이면 다시 쓰지 않는다.
  final _requested = <String, String>{};

  static String _keyOf(String accountId, String profileId) =>
      '$accountId/$profileId';

  /// [draft] 를 남긴다. 기다리지 않는다.
  void keep(String accountId, String profileId, SavedSetupDraft draft) {
    final key = _keyOf(accountId, profileId);
    final encoded = draft.encode();
    if (_requested[key] == encoded) return;
    _requested[key] = encoded;
    final scheduled = _pending.containsKey(key);
    _pending[key] = draft;
    if (scheduled) return;
    _enqueue(key, () async {
      final latest = _pending.remove(key);
      if (latest != null) await _store.write(accountId, profileId, latest);
    });
  }

  /// 남긴 초안을 지운다. 아직 쓰지 않은 초안도 버린다.
  Future<void> clear(String accountId, String profileId) {
    final key = _keyOf(accountId, profileId);
    _requested.remove(key);
    _pending.remove(key);
    return _enqueue(key, () => _store.clear(accountId, profileId));
  }

  /// 남긴 초안을 읽는다. 쓰는 중이면 끝난 뒤에 읽는다.
  Future<SavedSetupDraft?> read(String accountId, String profileId) async {
    await _tails[_keyOf(accountId, profileId)];
    return _store.read(accountId, profileId);
  }

  /// 탈퇴한 계정의 초안을 모두 지운다. 쓰는 중인 것이 끝난 뒤에 지운다.
  Future<void> clearAccount(String accountId) async {
    final prefix = '$accountId/';
    bool mine(String key) => key.startsWith(prefix);
    _pending.removeWhere((key, _) => mine(key));
    _requested.removeWhere((key, _) => mine(key));
    await Future.wait([
      for (final MapEntry(:key, :value) in _tails.entries)
        if (mine(key)) value,
    ]);
    await _store.clearAccount(accountId);
  }

  Future<void> _enqueue(String key, Future<void> Function() job) {
    final next = (_tails[key] ?? Future<void>.value())
        .then((_) => job())
        // 저장소가 실패를 삼키지만, 하나가 던져도 뒤의 일은 이어 간다.
        .catchError((Object _) {});
    _tails[key] = next;
    return next;
  }
}

final setupDraftKeeperProvider = Provider<SetupDraftKeeper>(
  (ref) => SetupDraftKeeper(ref.watch(setupDraftStoreProvider)),
);
