import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/profile_avatar.dart';
import 'life_story.dart';
import 'life_story_book_loader.dart';

/// 책을 펼친 첫 장. 어르신 사진, 이름과 생년월일, 분류, 최근 담은 이야기와
/// 맨 아래의 `이야기 추가하기` 다.
class LifeStoryBookScreen extends StatelessWidget {
  const LifeStoryBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: LifeStoryBookLoader(
        builder: (context, book) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.section),
            children: [
              // 프로필부터 분류까지는 옅은 회색 면에 두고, 최근 이야기와 끊는다.
              ColoredBox(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.xxxl,
                    AppSpacing.screen,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileHeader(book: book),
                      const SizedBox(height: AppSpacing.xxxl),
                      const Text(
                        '어떤 이야기를 볼까요?',
                        style: AppTypography.sectionTitle,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _CategoryGrid(book: book),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.xxxl,
                  AppSpacing.screen,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('최근 추가된 이야기', style: AppTypography.sectionTitle),
                    const SizedBox(height: AppSpacing.sm),
                    _RecentList(book: book),
                    const SizedBox(height: AppSpacing.xxxl),
                    PrimaryButton(
                      label: '이야기 추가하기',
                      onPressed: () => context.push(AppRoutes.albumStoryNew),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.book});

  final LifeStoryBook book;

  @override
  Widget build(BuildContext context) {
    final profile = book.profile;
    return Column(
      children: [
        // 회색 면과 구분되게 흰 테를 두르고 바깥에 얇은 선과 그림자를 둔다.
        Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
            boxShadow: AppShadows.low,
          ),
          child: ProfileAvatar(gender: profile.gender, size: 112),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          profile.name,
          style: AppTypography.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          birthDateLabel(profile.birthDate),
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 여섯 분류는 세 칸씩 두 줄, `기타` 는 그 아래 한 줄을 다 쓴다.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.book});

  final LifeStoryBook book;

  static const _rows = [
    [LifeStoryCategory.family, LifeStoryCategory.hobby, LifeStoryCategory.work],
    [
      LifeStoryCategory.hometown,
      LifeStoryCategory.friend,
      LifeStoryCategory.travel,
    ],
  ];

  void _open(BuildContext context, LifeStoryCategory category) =>
      context.push(AppRoutes.albumCategoryOf(category.name));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows) ...[
          // 글자를 키워도 한 줄의 칸 높이를 맞춘다. 높이를 못 박지 않는다.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, category) in row.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppCard(
                      onTap: () => _open(context, category),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xl,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(category.icon, size: 28, color: AppColors.ink),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            category.label,
                            style: AppTypography.bodyStrong,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${book.storiesIn(category).length}편',
                            style: AppTypography.caption,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppCard(
          onTap: () => _open(context, LifeStoryCategory.other),
          child: Row(
            children: [
              Icon(
                LifeStoryCategory.other.icon,
                size: 28,
                color: AppColors.ink,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  LifeStoryCategory.other.label,
                  style: AppTypography.bodyStrong,
                ),
              ),
              Text(
                '${book.storiesIn(LifeStoryCategory.other).length}편',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.book});

  final LifeStoryBook book;

  @override
  Widget build(BuildContext context) {
    final recent = book.recent();
    if (recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text('아직 추가된 이야기가 없어요.', style: AppTypography.sub),
      );
    }
    return Column(
      children: [
        for (final (i, story) in recent.indexed) ...[
          if (i > 0) const Divider(),
          InkWell(
            // 목차를 거쳐 열어서, 이야기에서 뒤로 가면 그 분류의 목차가 나온다.
            onTap: () {
              context.push(AppRoutes.albumCategoryOf(story.category.name));
              context.push(
                AppRoutes.albumStoryOf(story.category.name, story.id),
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    AppChip(story.category.label, tone: ChipTone.strong),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        story.title,
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      shortDateLabel(story.createdAt!),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
