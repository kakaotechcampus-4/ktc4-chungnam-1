import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import 'life_story.dart';
import 'life_story_book_loader.dart';

/// 한 분류의 목차. 먼저 담은 이야기부터 1장, 2장으로 늘어선다.
class LifeStoryCategoryScreen extends StatelessWidget {
  const LifeStoryCategoryScreen({required this.category, super.key});

  final LifeStoryCategory category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: LifeStoryBookLoader(
        builder: (context, book) {
          final stories = book.storiesIn(category);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.sm,
                AppSpacing.screen,
                AppSpacing.section,
              ),
              children: [
                Text(
                  '${book.profile.name}님의 ${category.label}에 대한\n이야기입니다.',
                  style: AppTypography.screenTitle,
                ),
                const SizedBox(height: AppSpacing.xxxl),
                Container(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.ink, width: 2),
                    ),
                  ),
                  child: const Text('목차', style: AppTypography.bodyStrong),
                ),
                if (stories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Text('아직 담긴 이야기가 없어요.', style: AppTypography.sub),
                  ),
                for (final (i, story) in stories.indexed) ...[
                  if (i > 0) const Divider(),
                  _TocItem(number: i + 1, story: story),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TocItem extends StatelessWidget {
  const _TocItem({required this.number, required this.story});

  final int number;
  final LifeStory story;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () =>
          context.push(AppRoutes.albumStoryOf(story.category.name, story.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 32,
                child: Text('$number', style: AppTypography.bodyStrong),
              ),
              Expanded(child: Text(story.title, style: AppTypography.body)),
              if (story.createdAt case final createdAt?) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(shortDateLabel(createdAt), style: AppTypography.caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
