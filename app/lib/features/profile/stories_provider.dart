import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// 프로필별 합성 이야기 편집 상태. 앱 종료 시 사라지며 서버에 전송하지 않는다.
final storiesProvider =
    NotifierProvider<StoriesNotifier, Map<String, List<LifeFact>>>(
      StoriesNotifier.new,
    );

class StoriesNotifier extends Notifier<Map<String, List<LifeFact>>> {
  @override
  Map<String, List<LifeFact>> build() => {};

  void save(String profileId, List<LifeFact> current, LifeFact fact) {
    state = {
      ...state,
      profileId: [...current.where((item) => item.factId != fact.factId), fact],
    };
  }
}

final profileStoriesProvider = Provider<AsyncValue<List<LifeFact>>>((ref) {
  final edits = ref.watch(storiesProvider);
  return ref.watch(profileProvider).whenData((bundle) {
    final facts = [...(edits[bundle.profile.profileId] ?? bundle.lifeFacts)];
    facts.sort((a, b) {
      final byDate = (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      );
      return byDate != 0 ? byDate : a.factId.compareTo(b.factId);
    });
    return facts;
  });
});
