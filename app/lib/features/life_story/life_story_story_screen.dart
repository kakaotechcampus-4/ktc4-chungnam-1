import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../data/profile_api.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../profile/profile_dialogs.dart';
import 'life_story.dart';
import 'life_story_book_loader.dart';
import 'life_story_image.dart';
import 'life_story_providers.dart';

/// 이야기 한 편. 아래의 이전, 다음 이야기는 같은 분류의 목차 순서를 따른다.
///
/// 이전, 다음으로 넘겨도 화면을 새로 쌓지 않는다. 뒤로 가면 바로 목차다.
/// 오른쪽 위의 연필로 고치고 휴지통으로 지운다. 세부 정보 이야기는 프로필
/// 수정에서 고치므로 연필이 그 화면을 열고 휴지통은 없다.
class LifeStoryStoryScreen extends ConsumerStatefulWidget {
  const LifeStoryStoryScreen({
    required this.category,
    required this.storyId,
    super.key,
  });

  final LifeStoryCategory category;

  /// 처음 펼칠 이야기.
  final String storyId;

  @override
  ConsumerState<LifeStoryStoryScreen> createState() =>
      _LifeStoryStoryScreenState();
}

class _LifeStoryStoryScreenState extends ConsumerState<LifeStoryStoryScreen> {
  late String _storyId = widget.storyId;

  /// 지우는 중이다. 이때는 연필과 휴지통을 막는다.
  bool _deleting = false;

  /// 지우고 목차로 돌아가는 중인 이야기.
  LifeStory? _leavingWith;

  Future<void> _edit(LifeStory story) async {
    if (story.isProfileDetail) {
      context.push(AppRoutes.profileEditDetails);
      return;
    }
    final router = GoRouter.of(context);
    final saved = await context.push<LifeStory>(
      AppRoutes.albumStoryEditOf(story.id),
    );
    if (saved == null || saved.category == story.category || !mounted) return;
    // 분류를 바꿨으면 새 분류의 목차 위에서 이 이야기를 다시 연다.
    router
      ..pop()
      ..pushReplacement(AppRoutes.albumCategoryOf(saved.category.name))
      ..push(AppRoutes.albumStoryOf(saved.category.name, saved.id));
  }

  Future<void> _delete(String profileId, LifeStory story) async {
    final confirmed = await showChoiceDialog(
      context,
      title: '이 이야기를 지울까요?',
      // 이야기만 지우고 그 이야기로 만든 카드와 면회 기록은 남긴다(api-spec 2-9).
      detail: '지운 이야기는 되돌릴 수 없어요.\n이 이야기로 이미 만든 대화 카드와 리포트는\n그대로 남아요.',
      primaryLabel: '지우기',
      secondaryLabel: '취소',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await ref.read(lifeStoryStoreProvider).delete(profileId, story);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(profileFailureMessage(failure))));
      return;
    }
    if (!mounted) return;
    // 목차로 돌아가는 동안 지운 이야기가 '찾을 수 없어요' 로 보이지 않게 둔다.
    setState(() => _leavingWith = story);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('이야기를 지웠어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(lifeStoryBookProvider).value;
    final story = book?.find(_storyId) ?? _leavingWith;

    return Scaffold(
      appBar: AppTopBar(
        title: '목차로',
        actions: [
          if (book != null && story != null) ...[
            IconButton(
              onPressed: _deleting ? null : () => _edit(story),
              tooltip: '이야기 수정',
              icon: const Icon(Icons.edit_outlined, size: 22),
            ),
            if (!story.isProfileDetail)
              IconButton(
                onPressed: _deleting
                    ? null
                    : () => _delete(book.profile.profileId, story),
                tooltip: '이야기 지우기',
                icon: const Icon(Icons.delete_outline, size: 22),
              ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
      body: LifeStoryBookLoader(
        builder: (context, book) {
          final story = book.find(_storyId) ?? _leavingWith;
          if (story == null) {
            return const EmptyStateView(message: '이야기를 찾을 수 없어요.');
          }
          // 경로의 분류가 아니라 이야기의 분류를 따른다. 고치며 분류를 바꿔도
          // 그 분류의 몇 장인지 맞게 보인다.
          final stories = book.storiesIn(story.category);
          final index = stories.indexOf(story);
          return _StoryPage(
            // 넘길 때 맨 위부터 다시 읽게 스크롤을 새로 만든다.
            key: ValueKey(_storyId),
            story: story,
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
