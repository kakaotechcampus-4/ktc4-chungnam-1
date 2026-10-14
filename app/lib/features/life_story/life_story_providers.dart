import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'life_story.dart';
import 'life_story_mock.dart';

/// 지금 보고 있는 어르신의 일대기다. 등록을 마친 분이 없으면 `null` 이다.
///
/// 세부 정보 이야기는 입력한 값에서 만들고, 나머지는 목 이야기다. 이야기 조회
/// (API 2-3)를 붙이면 목 이야기 자리를 `lifeFacts[]` 로 바꾼다.
final lifeStoryBookProvider = FutureProvider<LifeStoryBook?>((ref) async {
  final bundle = await ref.watch(profileProvider.future);
  if (bundle == null) return null;
  return LifeStoryBook(
    profile: bundle.profile,
    stories: [...detailStoriesOf(bundle.profile), ...sampleLifeStories],
  );
});
