import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// G-2 변경 사항 확인.
///
/// 계약을 그대로 따른다.
/// - 남겨 둔 항목은 `accepted`, 지운 항목은 `rejected` 로 저장한다.
/// - 반영하면 `proposalStatus` 를 `reviewed` 로 바꾼다.
/// - 승인 전까지 프로필에 반영하지 않는다.
class ReportChangesScreen extends ConsumerStatefulWidget {
  const ReportChangesScreen({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<ReportChangesScreen> createState() =>
      _ReportChangesScreenState();
}

class _ReportChangesScreenState extends ConsumerState<ReportChangesScreen> {
  /// 사용자가 지운 항목. 반영할 때 `rejected` 가 된다.
  final _removed = <String>{};

  /// 이유를 펼친 항목. 한 번에 하나만 펼친다.
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final proposal = ref.watch(changeProposalProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: proposal.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '변경 사항을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(changeProposalProvider),
        ),
        data: (data) => _Body(
          changes: data.changes
              .where((c) => !_removed.contains(c.changeId))
              .toList(),
          expandedId: _expandedId,
          onExpand: (id) =>
              setState(() => _expandedId = _expandedId == id ? null : id),
          onRemove: (id) => setState(() {
            _removed.add(id);
            if (_expandedId == id) _expandedId = null;
          }),
          onApply: () {
            ref.read(reportNoticeProvider.notifier).dismiss();
            context.go(AppRoutes.home);
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.changes,
    required this.expandedId,
    required this.onExpand,
    required this.onRemove,
    required this.onApply,
  });

  final List<ProposedChange> changes;
  final String? expandedId;
  final ValueChanged<String> onExpand;
  final ValueChanged<String> onRemove;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: changes.isEmpty ? '반영하지 않고 마치기' : '이대로 반영하기',
        onPressed: onApply,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '다음 만남 때는\n이렇게 바꿀까요?',
            style: AppTypography.screenTitle,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('남겨두신 것만 프로필에 반영해요.', style: AppTypography.body),
          const SizedBox(height: AppSpacing.xl),

          Text(
            changes.isEmpty ? '반영할 항목이 없어요' : '${changes.length}개를 반영해요',
            style: AppTypography.sub,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (changes.isEmpty)
            const EmptyStateView(
              message: '모두 지우셨어요.\n이대로 마쳐도 괜찮아요.',
              icon: Icons.inbox_outlined,
            )
          else
            for (final change in changes) ...[
              _ChangeCard(
                change: change,
                expanded: expandedId == change.changeId,
                onTap: () => onExpand(change.changeId),
                onRemove: () => onRemove(change.changeId),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 변경 제안 한 건.
///
/// 위에 종류를, 그 아래 어떤 주제인지 크게 보여준다. 눌러야 이유가 펼쳐진다.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.change,
    required this.expanded,
    required this.onTap,
    required this.onRemove,
  });

  final ProposedChange change;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: AppChip(_kindLabel)),
              IconButton(
                onPressed: onRemove,
                tooltip: '이 제안 지우기',
                iconSize: 22,
                color: AppColors.textSub,
                constraints: const BoxConstraints(
                  minWidth: AppSizes.minTouch,
                  minHeight: AppSizes.minTouch,
                ),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
                Text(_title, style: AppTypography.sectionTitle),

                if (expanded) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppSurfaceBox(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppColors.textSub,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(change.reason, style: AppTypography.sub),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '눌러서 이유 보기',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textDisabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 계약상 `changeType` 은 `topicPriority` 와 `lifeFactAdd` 둘이고,
  /// `direction` 은 `up` 과 `down` 이다.
  String get _kindLabel {
    if (change.changeType == 'lifeFactAdd') return '새로 알게 된 이야기';
    return change.direction == 'up' ? '더 자주 꺼내기' : '당분간 쉬어가기';
  }

  /// `topicPriority` 는 주제 이름을, `lifeFactAdd` 는 더할 이야기를 보여준다.
  /// 계약상 `lifeFactAdd` 는 `topicTitle` 을 갖지 않는다.
  String get _title => change.changeType == 'lifeFactAdd'
      ? (change.text ?? '')
      : (change.topicTitle ?? '');
}
