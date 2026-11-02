import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../data/card_api.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../review/review_controller.dart';
import '../visit/visit_camera.dart';
import '../visit/visit_controller.dart';
import '../visit/visit_photos.dart';
import 'card_generation_controller.dart';
import 'cards_controller.dart';

/// C 오늘의 대화 카드.
///
/// 피그마 C-1 ~ C-3 은 별도 화면이 아니라 이 화면의 상태다. 카드를 누르면
/// 꼬리 질문이 펼쳐지고(C-2), 아래로 밀면 카드가 늘어난다(C-3).
class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generation = ref.watch(cardGenerationProvider);
    final controller = ref.read(cardGenerationProvider.notifier);

    return Scaffold(
      appBar: const AppTopBar(),
      body: generation.when(
        loading: () => const LoadingView(message: '오늘의 대화 카드를 만들고 있어요'),
        error: (error, _) => ErrorStateView(
          message: _failureMessage(error),
          onRetry: controller.retry,
        ),
        data: (status) => switch (status) {
          CardGenerationStatus.ready => const _Cards(),
          CardGenerationStatus.needsRefresh => const _Cards(outdated: true),
          // 4-2 는 실패 이유를 주지 않는다. 정보 부족과 그 밖의 실패를 가르지
          // 못하므로 공통 문구만 보여준다.
          CardGenerationStatus.failed => ErrorStateView(
            message: '대화 카드를 만들지 못했어요.\n다시 시도하면 새로 만들어요.',
            onRetry: controller.retry,
          ),
          // 면회를 이어서 하는 흐름은 회차 연결과 함께 붙인다.
          CardGenerationStatus.inVisit => const EmptyStateView(
            message: '아직 마치지 않은 면회가 있어요.',
            icon: Icons.style_outlined,
          ),
          // 생성 흐름은 none 과 running 을 남기지 않는다. 기다리는 도중 화면을
          // 떠난 경우뿐이라 기다리는 화면을 그대로 둔다.
          CardGenerationStatus.none || CardGenerationStatus.running =>
            const LoadingView(message: '오늘의 대화 카드를 만들고 있어요'),
        },
      ),
    );
  }
}

String _failureMessage(Object error) => switch (error) {
  ApiNetworkFailure() => '서버에 연결하지 못했어요.\n인터넷 연결을 확인한 뒤 다시 시도해주세요.',
  _ => '대화 카드를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
};

/// 쓸 묶음이 준비된 뒤의 카드 고르기.
///
/// [outdated] 면 받은 뒤 프로필이나 일대기를 고친 묶음이다. 카드는 보여주되
/// 고르거나 면회를 시작하지 못하게 하고 `다음 대화 준비하기` 를 둔다. 받아 둔
/// 묶음(4-3)이 그렇다고 해도 같다.
class _Cards extends ConsumerWidget {
  const _Cards({this.outdated = false});

  final bool outdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsControllerProvider);
    final setOutdated =
        ref.watch(currentCardSetProvider).value?.needsRefresh ?? false;

    return cards.when(
      loading: () => const LoadingView(message: '오늘의 대화 카드를 불러오고 있어요'),
      error: (error, _) => ErrorStateView(
        message: _failureMessage(error),
        // 실패한 묶음 조회를 버려야 다시 받는다.
        onRetry: () => ref.invalidate(currentCardSetProvider),
      ),
      data: (state) => _Body(state: state, outdated: outdated || setOutdated),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.state, required this.outdated});

  final CardsState state;
  final bool outdated;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  /// 끝에 닿은 채로 이만큼 머물러야 카드를 늘린다. 살짝 밀었을 때 우르르
  /// 나오지 않게 하려는 것이다.
  static const _holdToLoad = Duration(milliseconds: 700);

  /// 끝에서 이 안쪽이면 닿은 것으로 본다.
  static const _bottomSlack = 48.0;

  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onScroll(ScrollMetrics metrics) {
    final atBottom = metrics.pixels >= metrics.maxScrollExtent - _bottomSlack;

    if (!atBottom || !widget.state.hasMore) {
      _holdTimer?.cancel();
      _holdTimer = null;
      return;
    }

    // 이미 기다리는 중이면 그대로 둔다.
    if (_holdTimer?.isActive ?? false) return;

    _holdTimer = Timer(_holdToLoad, () {
      if (!mounted) return;
      ref.read(cardsControllerProvider.notifier).showMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final outdated = widget.outdated;
    final controller = ref.read(cardsControllerProvider.notifier);

    if (state.cards.isEmpty) {
      return const EmptyStateView(
        message: '오늘 준비된 대화 카드가 없어요.\n잠시 후 다시 확인해주세요.',
        icon: Icons.style_outlined,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScroll(notification.metrics);
        return false;
      },
      child: ScreenBody(
        scrollable: true,
        bottom: outdated
            ? PrimaryButton(
                label: '다음 대화 준비하기',
                onPressed: ref.read(cardGenerationProvider.notifier).refresh,
              )
            : PrimaryButton(
                label: '대화 시작하기',
                // 한 장도 고르지 않으면 시작하지 않는다.
                onPressed: state.canStart
                    ? () {
                        // 지난 회차의 녹음 시간, 소감과 사진이 남아 있지 않게 비운다.
                        // 지난 사진의 사본은 갤러리에 원본이 있을 때만 지운다
                        // (visit_photos.dart). 못 지워도 면회는 시작한다.
                        ref.invalidate(visitControllerProvider);
                        ref.invalidate(reviewControllerProvider);
                        ref.invalidate(visitPhotoProvider);
                        unawaited(
                          ref
                              .read(visitPhotosProvider)
                              .tidy()
                              .catchError((Object _) {}),
                        );
                        context.push(AppRoutes.visitPhoto);
                      }
                    : null,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Text('오늘의 대화 카드', style: AppTypography.screenTitle),
            const SizedBox(height: AppSpacing.md),
            const Text('오늘은 어떤 이야기를 나눠볼까요?', style: AppTypography.body),
            const SizedBox(height: AppSpacing.xl),

            if (outdated)
              const _OutdatedNotice()
            else
              _SelectionSummary(count: state.selectedIds.length),
            const SizedBox(height: AppSpacing.xl),

            for (final card in state.visibleCards) ...[
              _CardTile(
                card: card,
                // 고친 묶음은 고를 수 없다. 앞서 고른 표시도 남기지 않는다.
                selected: !outdated && state.selectedIds.contains(card.cardId),
                expanded: state.expandedId == card.cardId,
                onToggleSelected: outdated
                    ? null
                    : () => controller.toggleSelected(card.cardId),
                onToggleExpanded: () => controller.toggleExpanded(card.cardId),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (state.hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: controller.showMore,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSub,
                    minimumSize: const Size(
                      AppSizes.minTouch,
                      AppSizes.minTouch,
                    ),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  label: Text(
                    '${state.remaining}장 더 보기',
                    style: AppTypography.sub,
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

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppChip(
          count == 0 ? '아직 고르지 않았어요' : '$count개 선택함',
          tone: count == 0 ? ChipTone.weak : ChipTone.strong,
        ),
        const SizedBox(width: AppSpacing.md),
        Text('최대 ${CardRules.selectableCount}개까지', style: AppTypography.sub),
      ],
    );
  }
}

/// 받은 뒤 정보를 고친 묶음이라는 안내. 선택 수 자리에 둔다.
class _OutdatedNotice extends StatelessWidget {
  const _OutdatedNotice();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceBox(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: const Text(
        '카드를 받은 뒤 어르신 정보가 바뀌었어요.\n'
        '바뀐 정보로 대화 카드를 다시 준비해주세요.',
        style: AppTypography.body,
      ),
    );
  }
}

/// 카드 한 장. 접힌 상태에서는 주제와 안내 문장을, 펼치면 질문까지 보여준다.
class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
  });

  final ConversationCard card;
  final bool selected;
  final bool expanded;

  /// `null` 이면 고를 수 없는 카드라 선택 표시를 두지 않는다.
  final VoidCallback? onToggleSelected;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      selected: selected,
      onTap: onToggleExpanded,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // 선택 표시를 카드 윗부분 높이의 가운데에 둔다.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.cardTitle, style: AppTypography.bodyStrong),
                    const SizedBox(height: AppSpacing.sm),
                    // 이 카드로 무엇을 나누는지 알려주는 설명이다. 주제는
                    // 여러 면회에 걸친 묶음이라 고르는 화면에는 두지 않는다.
                    Text(card.description, style: AppTypography.sub),
                  ],
                ),
              ),
              // 카드 본문을 누르면 펼쳐지고, 이 표시를 눌러야 선택된다.
              if (onToggleSelected case final onTap?) ...[
                const SizedBox(width: AppSpacing.md),
                GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: SelectionMark(selected: selected),
                  ),
                ),
              ],
            ],
          ),

          if (expanded) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            Text(card.primaryQuestion, style: AppTypography.bodyStrong),
            const SizedBox(height: AppSpacing.md),
            for (final question in card.followUpQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('· ', style: AppTypography.sub),
                    Expanded(child: Text(question, style: AppTypography.sub)),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              '눌러서 질문 보기',
              style: AppTypography.caption.copyWith(
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
