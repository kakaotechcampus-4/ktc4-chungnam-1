import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_states.dart';
import 'life_story.dart';
import 'life_story_providers.dart';

/// 일대기를 읽는 동안과 실패했을 때를 일대기 화면들이 똑같이 보여준다.
///
/// 어르신이 없으면 경로의 등록 안내(`router.dart` 의 `_NeedsProfile`)가 먼저
/// 막으므로 여기서는 빈 안내만 둔다.
class LifeStoryBookLoader extends ConsumerWidget {
  const LifeStoryBookLoader({required this.builder, super.key});

  final Widget Function(BuildContext context, LifeStoryBook book) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(lifeStoryBookProvider);
    return book.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorStateView(
        message: '일대기를 불러오지 못했어요.',
        onRetry: () => ref.invalidate(lifeStoryBookProvider),
      ),
      data: (book) => book == null
          ? const EmptyStateView(message: '함께하는 소중한 분을 먼저 등록해주세요.')
          : builder(context, book),
    );
  }
}
