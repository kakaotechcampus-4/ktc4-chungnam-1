import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_states.dart';
import 'visit_controller.dart';

/// E-3, E-4 면회 중 대화 카드.
///
/// 화면이 아니라 녹음 화면 위로 올라오는 팝업이다. 보호자가 휴대전화를 들었다
/// 놨다 하지 않고 바닥에 둔 채 곁눈질로 볼 수 있게 만들었다. 그래서 질문 글자가
/// 다른 화면보다 크고, 화면을 크게 둘로 나눠 위는 메인 질문, 아래는 꼬리 질문을
/// 둔다.
///
/// 내려서 닫으면 녹음 화면으로 돌아가고, 거기서 정지를 눌러 대화를 마친다.
Future<void> showVisitCardsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    // 위쪽 빈 곳을 누르면 닫힌다.
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) => FractionallySizedBox(
      // 화면의 5분의 4까지 올라온다.
      heightFactor: 0.8,
      child: const _SheetBody(),
    ),
  );
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitControllerProvider);

    return visit.when(
      loading: () => const LoadingView(),
      error: (error, _) => const ErrorStateView(message: '대화 카드를 불러오지 못했어요.'),
      data: (state) {
        if (state.cards.isEmpty) {
          return EmptyStateView(
            message: '고른 대화 카드가 없어요.\n카드를 추가해 보세요.',
            icon: Icons.style_outlined,
            actionLabel: '대화 카드 추가',
            onAction: () => context.push(AppRoutes.visitAddCards),
          );
        }
        return _Cards(state: state);
      },
    );
  }
}

class _Cards extends ConsumerWidget {
  const _Cards({required this.state});

  final VisitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(visitControllerProvider.notifier);
    final card = state.currentCard!;

    return Column(
      children: [
        const _DragHandle(),
        _StatusBar(state: state),

        // 남은 자리를 크게 둘로 나눈다.
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  Expanded(
                    child: _MainQuestion(
                      topicTitle: card.topicTitle,
                      question: card.primaryQuestion,
                    ),
                  ),
                  Expanded(
                    child: _FollowUpQuestion(
                      question: state.currentFollowUp ?? '',
                      index: state.followUpCount == 0
                          ? 0
                          : state.followUpIndex % state.followUpCount,
                      count: state.followUpCount,
                      onTap: controller.nextFollowUp,
                    ),
                  ),
                ],
              ),

              // 두 영역의 경계 한가운데에 다음 카드 버튼을 놓는다.
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: _NextCardButton(
                    enabled: !state.isLastCard,
                    onTap: controller.nextCard,
                  ),
                ),
              ),
            ],
          ),
        ),

        _AddCardsBar(onTap: () => context.push(AppRoutes.visitAddCards)),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final VisitState state;

  @override
  Widget build(BuildContext context) {
    final percent = (state.progress * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '오늘의 이야기 카드 ${state.currentIndex + 1}/${state.cards.length}',
                  style: AppTypography.sub,
                ),
              ),
              Text('$percent%', style: AppTypography.sub),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              backgroundColor: AppColors.surface,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 위쪽 절반. 흰 바탕에 어르신께 여쭙는 문장을 크게 둔다.
class _MainQuestion extends StatelessWidget {
  const _MainQuestion({required this.topicTitle, required this.question});

  final String topicTitle;
  final String question;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.lg,
        AppSpacing.screen,
        AppSpacing.xxxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '[ $topicTitle ]',
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  question,
                  // 바닥에 둔 채 곁눈질로 읽으므로 다른 화면보다 크게 둔다.
                  style: AppTypography.screenTitle.copyWith(
                    fontSize: 32,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아래쪽 절반. 회색 바탕으로 위와 구분하고, 누르면 다음 꼬리 질문으로 넘어간다.
class _FollowUpQuestion extends StatelessWidget {
  const _FollowUpQuestion({
    required this.question,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final String question;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line, width: 2)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.xxxl,
            AppSpacing.screen,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      question,
                      style: AppTypography.screenTitle.copyWith(
                        fontSize: 26,
                        height: 1.4,
                        color: AppColors.textSub,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == index
                              ? AppColors.textSub
                              : AppColors.line,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '눌러서 다음 꼬리 질문 보기',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 두 영역 경계에 걸쳐 놓는 다음 카드 버튼이다.
class _NextCardButton extends StatelessWidget {
  const _NextCardButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.ink : AppColors.line,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                enabled ? Icons.arrow_forward : Icons.check,
                size: 24,
                color: enabled ? AppColors.background : AppColors.textDisabled,
              ),
              const SizedBox(height: 2),
              Text(
                enabled ? '다음' : '마지막',
                style: AppTypography.caption.copyWith(
                  color: enabled
                      ? AppColors.background
                      : AppColors.textDisabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCardsBar extends StatelessWidget {
  const _AddCardsBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            height: 64,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 22, color: AppColors.ink),
                SizedBox(width: AppSpacing.sm),
                Text('대화 카드 추가', style: AppTypography.bodyStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
