import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'life_story.dart';
import 'life_story_book_loader.dart';
import 'life_story_image.dart';

/// 이야기 한 편. 아래의 이전, 다음 이야기는 같은 분류의 목차 순서를 따른다.
///
/// 이전, 다음으로 넘겨도 화면을 새로 쌓지 않는다. 뒤로 가면 바로 목차다.
class LifeStoryStoryScreen extends StatefulWidget {
  const LifeStoryStoryScreen({
    required this.category,
    required this.storyId,
    super.key,
  });

  final LifeStoryCategory category;

  /// 처음 펼칠 이야기.
  final String storyId;

  @override
  State<LifeStoryStoryScreen> createState() => _LifeStoryStoryScreenState();
}

class _LifeStoryStoryScreenState extends State<LifeStoryStoryScreen> {
  late String _storyId = widget.storyId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: '목차로'),
      body: LifeStoryBookLoader(
        builder: (context, book) {
          final stories = book.storiesIn(widget.category);
          final index = stories.indexWhere((s) => s.id == _storyId);
          if (index < 0) {
            return const EmptyStateView(message: '이야기를 찾을 수 없어요.');
          }
          return _StoryPage(
            // 넘길 때 맨 위부터 다시 읽게 스크롤을 새로 만든다.
            key: ValueKey(_storyId),
            story: stories[index],
            chapter: index + 1,
            onPrevious: index > 0
                ? () => setState(() => _storyId = stories[index - 1].id)
                : null,
            onNext: index < stories.length - 1
                ? () => setState(() => _storyId = stories[index + 1].id)
                : null,
          );
        },
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({
    required this.story,
    required this.chapter,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final LifeStory story;
  final int chapter;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // 이전, 다음 버튼은 글 길이와 상관없이 화면 아래 같은 자리에 둔다.
    return ScreenBody(
      bottom: Row(
        children: [
          Expanded(
            child: _PageButton(label: '이전 이야기', onPressed: onPrevious),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _PageButton(label: '다음 이야기', onPressed: onNext),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        children: [
          Text('${story.category.label} · $chapter장', style: AppTypography.sub),
          const SizedBox(height: AppSpacing.sm),
          Text(story.title, style: AppTypography.screenTitle),
          if (story.createdAt case final createdAt?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(fullDateLabel(createdAt), style: AppTypography.caption),
          ],
          const SizedBox(height: AppSpacing.xl),
          LifeStoryImage(category: story.category, number: story.imageNumber),
          const SizedBox(height: AppSpacing.xl),
          // 오래 읽어도 눈이 편하도록 줄 간격을 본문보다 넓힌다.
          Text(story.content, style: AppTypography.body.copyWith(height: 1.8)),
        ],
      ),
    );
  }
}

/// 이전, 다음 이야기 버튼. 넘길 이야기가 있으면 검정 면에 흰 글자이고,
/// 없으면 회색 면에 흐린 글자라 누를 수 없다는 것이 바로 보인다.
///
/// 검정 면 버튼은 화면에 하나만 두는 것이 원칙(`app/DESIGN.md`)이지만, 여기는
/// 누를 수 있는지를 한눈에 가리는 것이 더 중요해 둘 다 검정 면으로 둔다.
class _PageButton extends StatelessWidget {
  const _PageButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ConstrainedBox(
      // 글자를 키웠을 때 잘리지 않게 높이는 최소만 정한다.
      constraints: const BoxConstraints(minHeight: AppSizes.control),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.button.copyWith(
            color: enabled ? AppColors.background : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}
