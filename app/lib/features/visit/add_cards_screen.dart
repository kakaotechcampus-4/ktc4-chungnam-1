import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import 'visit_controller.dart';

/// E-5 대화 카드 추가.
///
/// 계약대로 면회 중 보충용으로 남겨 둔 카드를 추천한다. 고른 카드만 이번 회차에
/// 더한다.
class AddCardsScreen extends ConsumerStatefulWidget {
  const AddCardsScreen({super.key});

  @override
  ConsumerState<AddCardsScreen> createState() => _AddCardsScreenState();
}

class _AddCardsScreenState extends ConsumerState<AddCardsScreen> {
  final _picked = <String>{};

  /// 눌러서 질문을 펼친 카드. 한 번에 하나만 펼친다.
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final supplements = ref.watch(supplementCardsProvider);
    final visit = ref.watch(visitControllerProvider).value;
    final already = visit?.cards.map((c) => c.cardId).toSet() ?? const {};

    return Scaffold(
      appBar: const AppTopBar(),
      body: supplements.when(
        loading: () => const LoadingView(),
        error: (error, _) =>
            const ErrorStateView(message: '추가할 카드를 불러오지 못했어요.'),
        data: (cards) {
          final available = cards
              .where((c) => !already.contains(c.cardId))
              .toList();

          if (available.isEmpty) {
            return EmptyStateView(
              message: '추가할 수 있는 카드를 모두 쓰셨어요.',
              icon: Icons.done_all,
              actionLabel: '돌아가기',
              onAction: () => context.pop(),
            );
          }

          return _Body(
            cards: available,
            picked: _picked,
            expandedId: _expandedId,
            onToggle: (id) => setState(() {
              _picked.contains(id) ? _picked.remove(id) : _picked.add(id);
            }),
            onExpand: (id) => setState(() {
              _expandedId = _expandedId == id ? null : id;
            }),
            onAdd: () {
              ref
                  .read(visitControllerProvider.notifier)
                  .addCards(available.where((c) => _picked.contains(c.cardId)));
              context.pop();
            },
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.cards,
    required this.picked,
    required this.expandedId,
    required this.onToggle,
    required this.onExpand,
    required this.onAdd,
  });

  final List<ConversationCard> cards;
  final Set<String> picked;
  final String? expandedId;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onExpand;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: picked.isEmpty ? '카드를 골라주세요' : '${picked.length}장 추가하기',
        onPressed: picked.isEmpty ? null : onAdd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const Text('대화 카드 추가', style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.md),
          const Text('이야기가 더 필요하시면 골라주세요.', style: AppTypography.body),
          const SizedBox(height: AppSpacing.xl),

          for (final card in cards) ...[
            _AddCardTile(
              card: card,
              selected: picked.contains(card.cardId),
              expanded: expandedId == card.cardId,
              onToggleSelected: () => onToggle(card.cardId),
              onToggleExpanded: () => onExpand(card.cardId),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 선택 화면의 카드와 같은 모양이다. 눌러서 질문을 펼치고, 오른쪽 표시로 고른다.
class _AddCardTile extends StatelessWidget {
  const _AddCardTile({
    required this.card,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
  });

  final ConversationCard card;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelected;
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.topicTitle, style: AppTypography.bodyStrong),
                    const SizedBox(height: AppSpacing.sm),
                    Text(card.topicDescription, style: AppTypography.sub),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              GestureDetector(
                onTap: onToggleSelected,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: SelectionMark(selected: selected),
                ),
              ),
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
