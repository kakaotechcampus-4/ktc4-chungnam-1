import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/profile_api.dart';
import '../../data/providers.dart';
import '../auth/auth_providers.dart';
import 'life_story.dart';

/// 지금 보고 있는 어르신의 일대기다. 등록을 마친 분이 없으면 `null` 이다.
///
/// 세부 정보 이야기는 입력한 값에서 만든다. 담은 이야기는 서버에 저장한 분이면
/// 서버의 것([serverLifeFactsProvider])이고, 목 모드면 목 이야기에 보호자가
/// 추가, 수정, 삭제한 것([lifeStoryEditsProvider])을 얹은 것이다.
///
/// 읽는 것만 기다리고 이야기를 합치는 것은 바로 한다. 이야기를 바꿀 때마다
/// 다시 기다리지 않게 하려는 것이다.
final lifeStoryBookProvider = Provider<AsyncValue<LifeStoryBook?>>((ref) {
  final edits = ref.watch(lifeStoryEditsProvider);
  final profile = ref.watch(profileProvider);
  final server = ref.watch(serverLifeFactsProvider);
  if (profile.hasValue && server.hasValue) {
    final bundle = profile.requireValue;
    if (bundle == null) return const AsyncData(null);
    final serverFacts = server.requireValue;
    final stories = serverFacts == null
        ? (edits[bundle.profile.profileId] ?? const LifeStoryEdits()).applyTo([
            for (final fact in bundle.lifeFacts) LifeStory.fromLifeFact(fact),
          ])
        : [for (final fact in serverFacts) LifeStory.fromLifeFact(fact)];
    return AsyncData(
      LifeStoryBook(
        profile: bundle.profile,
        stories: [...detailStoriesOf(bundle.profile), ...stories],
      ),
    );
  }
  if (profile case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }
  if (server case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }
  return const AsyncLoading();
});

/// 서버에 저장한 어르신의 담은 이야기(API 2-3 의 `lifeFacts[]`). 먼저 담은
/// 것부터다.
///
/// 로그인하지 않은 목 모드거나 서버에 없는 분이면 `null` 이다. 이때 일대기는
/// 목 이야기를 쓴다. 담고, 고치고, 지운 결과는 다시 읽지 않고 이 목록에 바로
/// 반영한다([LifeStoryStore]).
final serverLifeFactsProvider =
    AsyncNotifierProvider<ServerLifeFactsNotifier, List<LifeFact>?>(
      ServerLifeFactsNotifier.new,
      // 실패는 일대기 화면의 다시 시도 버튼으로 다시 읽는다.
      retry: (_, _) => null,
    );

class ServerLifeFactsNotifier extends AsyncNotifier<List<LifeFact>?> {
  /// 이 목록이 어느 분의 것인지. 저장하는 사이 다른 분을 고르면 결과를 넣지
  /// 않는다.
  String? _profileId;

  @override
  Future<List<LifeFact>?> build() async {
    final online = ref.watch(sessionProvider.select((s) => s != null));
    final remoteId = ref.watch(
      careProfilesProvider.select((p) => p.selected?.remoteId),
    );
    _profileId = online ? remoteId : null;
    final profileId = _profileId;
    if (profileId == null) return null;
    return (await ref.watch(profileApiProvider).get(profileId)).lifeFacts;
  }

  void _put(String profileId, LifeFact fact) {
    final facts = state.value;
    if (profileId != _profileId || facts == null) return;
    final index = facts.indexWhere((f) => f.factId == fact.factId);
    state = AsyncData(
      index < 0
          ? [...facts, fact]
          : [
              for (final f in facts)
                if (f.factId == fact.factId) fact else f,
            ],
    );
  }

  void _remove(String profileId, String factId) {
    final facts = state.value;
    if (profileId != _profileId || facts == null) return;
    state = AsyncData([
      for (final f in facts)
        if (f.factId != factId) f,
    ]);
  }
}

/// 일대기에서 이야기를 담고, 고치고, 지운다.
///
/// 서버에 저장한 분이면 서버(2-6, 2-7, 2-9)에 보내고, 목 모드면 앱 안
/// ([lifeStoryEditsProvider])에만 둔다. 서버 실패는 [ApiFailure] 로 던지며
/// 이때 일대기는 바뀌지 않는다. 세부 정보 이야기는 프로필 수정에서 고친다.
class LifeStoryStore {
  const LifeStoryStore(this._ref);

  final Ref _ref;

  bool get _onServer => _ref.read(serverLifeFactsProvider).value != null;

  ServerLifeFactsNotifier get _server =>
      _ref.read(serverLifeFactsProvider.notifier);

  ProfileApi get _api => _ref.read(profileApiProvider);

  /// 새 이야기를 담고 돌려준다. 담은 시각은 서버가 정한다.
  Future<LifeStory> add(String profileId, LifeStoryDraft draft) async {
    if (!_onServer) {
      return _ref.read(lifeStoryEditsProvider.notifier).add(profileId, draft);
    }
    final fact = await _api.createLifeFact(
      profileId,
      storyCategory: draft.category.name,
      title: draft.title,
      content: draft.content,
      imageNumber: draft.imageNumber,
    );
    _server._put(profileId, fact);
    return LifeStory.fromLifeFact(fact);
  }

  /// [story] 를 [draft] 로 고치고 돌려준다. 담은 시각은 그대로다.
  Future<LifeStory> update(
    String profileId,
    LifeStory story,
    LifeStoryDraft draft,
  ) async {
    assert(!story.isProfileDetail, '세부 정보 이야기는 프로필 수정에서 고친다');
    if (!_onServer) {
      return _ref
          .read(lifeStoryEditsProvider.notifier)
          .update(profileId, story, draft);
    }
    final fact = await _guard(
      () => _api.updateLifeFact(
        story.id,
        storyCategory: draft.category.name,
        title: draft.title,
        content: draft.content,
        imageNumber: draft.imageNumber,
      ),
    );
    _server._put(profileId, fact);
    return LifeStory.fromLifeFact(fact);
  }

  Future<void> delete(String profileId, LifeStory story) async {
    assert(!story.isProfileDetail, '세부 정보 이야기는 지우지 않는다');
    if (!_onServer) {
      _ref.read(lifeStoryEditsProvider.notifier).delete(profileId, story);
      return;
    }
    await _guard(() => _api.deleteLifeFact(story.id));
    _server._remove(profileId, story.id);
  }

  /// 없는 이야기라는 답이면 목록이 낡은 것이라 다시 읽게 한다.
  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiServerFailure catch (failure) {
      if (failure.errorCode == 'LIFE_FACT_NOT_FOUND') {
        _ref.invalidate(serverLifeFactsProvider);
      }
      rethrow;
    }
  }
}

final lifeStoryStoreProvider = Provider<LifeStoryStore>(LifeStoryStore.new);

/// 한 어르신의 일대기에서 보호자가 바꾼 것.
class LifeStoryEdits {
  const LifeStoryEdits({
    this.added = const [],
    this.changed = const {},
    this.deleted = const {},
  });

  final List<LifeStory> added;

  /// 목 이야기를 고친 것. 이야기 ID 로 찾는다.
  final Map<String, LifeStory> changed;

  /// 지운 목 이야기의 ID.
  final Set<String> deleted;

  List<LifeStory> applyTo(List<LifeStory> base) => [
    for (final story in base)
      if (!deleted.contains(story.id)) changed[story.id] ?? story,
    ...added,
  ];

  bool _isAdded(String id) => added.any((s) => s.id == id);

  LifeStoryEdits _add(LifeStory story) => LifeStoryEdits(
    added: [...added, story],
    changed: changed,
    deleted: deleted,
  );

  LifeStoryEdits _update(LifeStory story) => _isAdded(story.id)
      ? LifeStoryEdits(
          added: [for (final s in added) s.id == story.id ? story : s],
          changed: changed,
          deleted: deleted,
        )
      : LifeStoryEdits(
          added: added,
          changed: {...changed, story.id: story},
          deleted: deleted,
        );

  LifeStoryEdits _delete(String id) => _isAdded(id)
      ? LifeStoryEdits(
          added: added.where((s) => s.id != id).toList(),
          changed: changed,
          deleted: deleted,
        )
      : LifeStoryEdits(
          added: added,
          changed: {...changed}..remove(id),
          deleted: {...deleted, id},
        );
}

/// 일대기에서 추가, 수정, 삭제한 이야기를 어르신 ID 별로 기억한다.
///
/// 로그인하지 않은 목 모드에서만 쓰며 **앱이 켜져 있는 동안만** 기억한다.
/// 어르신 목록과 같은 범위이며, 로그아웃과 탈퇴 때 `forgetCareProfiles` 가
/// 함께 지운다. 세부 정보 이야기는 여기서 바꾸지 않고 프로필 수정에서 고친다.
class LifeStoryEditsNotifier extends Notifier<Map<String, LifeStoryEdits>> {
  var _nextId = 1;

  @override
  Map<String, LifeStoryEdits> build() => const {};

  LifeStoryEdits _of(String profileId) =>
      state[profileId] ?? const LifeStoryEdits();

  /// 새 이야기를 담고 돌려준다. 담은 시각은 지금이다.
  LifeStory add(String profileId, LifeStoryDraft draft) {
    final story = LifeStory(
      id: 'local-story-${_nextId++}',
      category: draft.category,
      title: draft.title,
      content: draft.content,
      imageNumber: draft.imageNumber,
      createdAt: DateTime.now(),
    );
    state = {...state, profileId: _of(profileId)._add(story)};
    return story;
  }

  /// [story] 의 제목, 내용, 분류와 이미지를 [draft] 로 바꾼다. 담은 시각은
  /// 그대로라 목차 순서가 바뀌지 않는다.
  LifeStory update(String profileId, LifeStory story, LifeStoryDraft draft) {
    assert(!story.isProfileDetail, '세부 정보 이야기는 프로필 수정에서 고친다');
    final updated = LifeStory(
      id: story.id,
      category: draft.category,
      title: draft.title,
      content: draft.content,
      imageNumber: draft.imageNumber,
      createdAt: story.createdAt,
    );
    state = {...state, profileId: _of(profileId)._update(updated)};
    return updated;
  }

  void delete(String profileId, LifeStory story) {
    assert(!story.isProfileDetail, '세부 정보 이야기는 지우지 않는다');
    state = {...state, profileId: _of(profileId)._delete(story.id)};
  }
}

final lifeStoryEditsProvider =
    NotifierProvider<LifeStoryEditsNotifier, Map<String, LifeStoryEdits>>(
      LifeStoryEditsNotifier.new,
    );

/// 새 이야기의 기본 이미지를 처음에 고를 때 쓴다. 테스트에서 바꿔 끼운다.
final lifeStoryRandomProvider = Provider<Random>((ref) => Random());
