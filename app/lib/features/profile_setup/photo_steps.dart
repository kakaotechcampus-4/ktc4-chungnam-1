import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_states.dart';

/// B-7 사진 올리기. 선택 항목이며 한 장만 받는다.
///
/// 실제 갤러리 연결은 아직 붙이지 않았다. 목 데이터의 사진으로 자리를 채운다.
class PhotoUploadStep extends StatelessWidget {
  const PhotoUploadStep({
    required this.hasPhoto,
    required this.onPicked,
    required this.onRemoved,
    super.key,
  });

  final bool hasPhoto;
  final VoidCallback onPicked;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Text(
          '어르신과 관련된 사진을\n올려주세요',
          style: AppTypography.screenTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          '사진에서 대화 주제를 추천해드려요. 넣지 않으셔도 괜찮아요.',
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
        const Spacer(flex: 2),

        if (hasPhoto)
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.image),
                child: Image.asset('assets/images/family.webp'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onRemoved,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
                child: const Text('다른 사진 고르기', style: AppTypography.sub),
              ),
            ],
          )
        else
          InkWell(
            onTap: onPicked,
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.image),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 44,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text('사진 추가하기', style: AppTypography.sub),
                ],
              ),
            ),
          ),

        const Spacer(flex: 3),
      ],
    );
  }
}

/// B-8 사진에서 뽑은 태그를 고른다.
///
/// 후보는 AI 가 신뢰도 높은 순으로 정렬해 최대 6개를 준다. 배열 순서가 곧 추천
/// 순위다(`docs/architecture/data-contracts.md`). 사용자가 고른 것만
/// `ProfilePhoto.acceptedTags` 에 저장한다.
class PhotoTagsStep extends ConsumerWidget {
  const PhotoTagsStep({
    required this.accepted,
    required this.onToggle,
    super.key,
  });

  final Set<String> accepted;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () => const SizedBox(
        height: 320,
        child: LoadingView(message: '사진에서 이야기 소재를 찾고 있어요'),
      ),
      error: (error, _) => const SizedBox(
        height: 320,
        child: ErrorStateView(
          message: '사진을 분석하지 못했어요.\n건너뛰고 나중에 다시 시도할 수 있어요.',
        ),
      ),
      data: (bundle) => _Tags(
        candidates: bundle.tagCandidates,
        accepted: accepted,
        onToggle: onToggle,
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({
    required this.candidates,
    required this.accepted,
    required this.onToggle,
  });

  final List<ImageTagCandidate> candidates;
  final Set<String> accepted;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.image),
          child: Image.asset('assets/images/family.webp'),
        ),
        const SizedBox(height: AppSpacing.section),
        const Text(
          '사진과 잘 어울리는 단어를\n모두 골라주세요',
          style: AppTypography.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          '고르지 않은 단어는 저장하지 않아요.',
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),

        if (candidates.isEmpty)
          const EmptyStateView(
            message: '사진에서 찾은 단어가 없어요.\n건너뛰셔도 괜찮아요.',
            icon: Icons.image_search_outlined,
          )
        else
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final candidate in candidates)
                _TagChip(
                  label: candidate.text,
                  selected: accepted.contains(candidate.text),
                  onTap: () => onToggle(candidate.text),
                ),
            ],
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: AppSizes.minTouch,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check : Icons.add,
              size: 18,
              color: selected ? AppColors.background : AppColors.textSub,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.background : AppColors.ink,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
