import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import 'review_controller.dart';

/// F-1 보호자 소감 작성.
///
/// 피그마의 네 물음을 계약의 `CaregiverEvaluation` 필드에 그대로 맞춘다.
/// Q1 대화 만족도, Q2 어르신 반응, Q3 카드별 평가, Q4 남기고 싶은 말.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reviewControllerProvider);
    final controller = ref.read(reviewControllerProvider.notifier);
    final cards = ref.watch(reviewCardsProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: ScreenBody(
        scrollable: true,
        bottom: PrimaryButton(
          label: '리포트 만들기',
          onPressed: draft.canSubmit
              ? () => context.go(AppRoutes.visitProcessing)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Text('오늘 만남은\n어떠셨나요?', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '남겨주신 이야기로 리포트를 만들어요.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.section),

            _Question(
              number: 'Q1',
              title: '오늘 대화는 어떠셨나요?',
              required: true,
              child: _SatisfactionPicker(
                value: draft.satisfaction,
                onChanged: controller.setSatisfaction,
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            _Question(
              number: 'Q2',
              title: '어르신의 반응은 어땠나요?',
              required: true,
              child: _ReactionPicker(
                value: draft.reaction,
                onChanged: controller.setReaction,
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            _Question(
              number: 'Q3',
              title: '대화 카드는 어떠셨나요?',
              detail: '다루지 않은 카드는 비워두셔도 돼요.',
              child: cards.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: LoadingView(),
                ),
                error: (error, _) => const ErrorStateView(
                  message: '카드를 불러오지 못했어요.',
                ),
                data: (list) => list.isEmpty
                    ? const EmptyStateView(
                        message: '이번 만남에서 다룬 카드가 없어요.',
                        icon: Icons.style_outlined,
                      )
                    : Column(
                        children: [
                          for (final card in list) ...[
                            _CardReactionRow(
                              title: card.topicTitle,
                              value: draft.cardReactions[card.cardId],
                              onChanged: (reaction) => controller
                                  .setCardReaction(card.cardId, reaction),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            _Question(
              number: 'Q4',
              title: '남기고 싶은 말이 있으신가요?',
              detail: '적지 않으셔도 괜찮아요.',
              child: TextField(
                controller: _note,
                onChanged: controller.setFreeNote,
                maxLines: 4,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: '오늘 기억에 남는 순간을 적어보세요.',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textDisabled,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.all(AppSpacing.lg),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.ink, width: 2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.number,
    required this.title,
    required this.child,
    this.detail,
    this.required = false,
  });

  final String number;
  final String title;
  final Widget child;
  final String? detail;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              number,
              style: AppTypography.bodyStrong.copyWith(
                color: AppColors.textDisabled,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: AppTypography.sectionTitle)),
            if (required)
              Text(
                '*',
                style: AppTypography.sectionTitle.copyWith(
                  color: AppColors.danger,
                ),
              ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(detail!, style: AppTypography.sub),
        ],
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    );
  }
}

/// Q1. 계약상 1 이상 5 이하의 정수다.
class _SatisfactionPicker extends StatelessWidget {
  const _SatisfactionPicker({required this.value, required this.onChanged});

  static const _labels = ['많이 아쉬웠어요', '아쉬웠어요', '보통이었어요', '좋았어요', '아주 좋았어요'];

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var score = 1; score <= 5; score++) ...[
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(score),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Container(
                    height: AppSizes.control,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == score
                          ? AppColors.ink
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: value == score
                            ? AppColors.ink
                            : AppColors.line,
                        width: value == score ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      '$score',
                      style: AppTypography.bodyStrong.copyWith(
                        color: value == score
                            ? AppColors.background
                            : AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              if (score < 5) const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          value == null ? '점수를 골라주세요' : _labels[value! - 1],
          style: AppTypography.sub,
        ),
      ],
    );
  }
}

/// Q2. 계약의 `careRecipientReaction` 다섯 값이다.
class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.value, required this.onChanged});

  final CareRecipientReaction? value;
  final ValueChanged<CareRecipientReaction> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final reaction in CareRecipientReaction.values)
          InkWell(
            onTap: () => onChanged(reaction),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: AppSizes.minTouch,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value == reaction
                    ? AppColors.ink
                    : AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: value == reaction ? AppColors.ink : AppColors.line,
                  width: value == reaction ? 2 : 1,
                ),
              ),
              child: Text(
                reaction.label,
                style: AppTypography.body.copyWith(
                  color: value == reaction
                      ? AppColors.background
                      : AppColors.ink,
                  fontWeight: value == reaction
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Q3. 카드 한 장에 대한 평가다. 고르지 않으면 다루지 않은 것으로 본다.
class _CardReactionRow extends StatelessWidget {
  const _CardReactionRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final CaregiverReaction? value;
  final ValueChanged<CaregiverReaction> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final reaction in CaregiverReaction.values) ...[
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(reaction),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Container(
                      height: AppSizes.minTouch,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: value == reaction
                            ? AppColors.ink
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: value == reaction
                              ? AppColors.ink
                              : AppColors.line,
                        ),
                      ),
                      child: Text(
                        reaction.label,
                        style: AppTypography.sub.copyWith(
                          color: value == reaction
                              ? AppColors.background
                              : AppColors.textSub,
                          fontWeight: value == reaction
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
                if (reaction != CaregiverReaction.values.last)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
