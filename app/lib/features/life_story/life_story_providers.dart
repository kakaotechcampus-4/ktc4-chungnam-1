import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'life_story.dart';
import 'life_story_mock.dart';

/// 지금 보고 있는 어르신의 일대기다. 등록을 마친 분이 없으면 `null` 이다.
///
/// 세부 정보 이야기는 입력한 값에서 만들고, 나머지는 목 이야기에 보호자가
/// 추가, 수정, 삭제한 것([lifeStoryEditsProvider])을 얹는다. 이야기 조회
/// (API 2-3)를 붙이면 목 이야기 자리를 `lifeFacts[]` 로 바꾼다.
///
/// 프로필을 읽는 것만 기다리고 이야기를 합치는 것은 바로 한다. 이야기를 바꿀
/// 때마다 다시 기다리지 않게 하려는 것이다.
final lifeStoryBookProvider = Provider<AsyncValue<LifeStoryBook?>>((ref) {
  final edits = ref.watch(lifeStoryEditsProvider);
  return ref.watch(profileProvider).whenData((bundle) {
    if (bundle == null) return null;
    final profile = bundle.profile;
    return LifeStoryBook(
      profile: profile,
      stories: [
        ...detailStoriesOf(profile),
        ...(edits[profile.profileId] ?? const LifeStoryEdits()).applyTo(
          sampleLifeStories,
        ),
      ],
    );
  });
});

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
/// 분류와 삭제 API 가 서버에 아직 없어 **앱이 켜져 있는 동안만** 기억한다.
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
