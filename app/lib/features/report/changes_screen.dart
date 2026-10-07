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
/// 계약이 정한 규칙은 다음과 같다(API 7-3, 7-4).
/// - 남겨 둔 항목은 `accepted`, 지운 항목은 `rejected` 로 보낸다.
/// - 회차의 `pending` 제안을 모두 한 번에 보낸다.
/// - 승인 전까지 프로필에 반영하지 않는다.
///
/// **지금은 목 데이터 단계라 위 저장을 수행하지 않는다.** 지운 항목을 화면
/// 안에 모아 두기만 하고, 반영 버튼은 리포트 알림을 지우고 홈으로 이동한다.
/// 저장은 BE 가 단말 저장 인터페이스를 확정한 뒤 붙인다. `app/README.md` 의
/// 영역 구분을 따른다.
class ReportChangesScreen extends ConsumerStatefulWidget {
  const ReportChangesScreen({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<ReportChangesScreen> createState() =>
      _ReportChangesScreenState();
}

class _ReportChangesScreenState extends ConsumerState<ReportChangesScreen> {
  /// 사용자가 지운 항목. 계약상 `rejected` 가 될 항목이지만 지금은 저장하지
  /// 않고 화면 표시에만 쓴다.
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
          changes: _ChangeItem.listOf(
            data,
          ).where((c) => !_removed.contains(c.id)).toList(),
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

  final List<_ChangeItem> changes;
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
                expanded: expandedId == change.id,
                onTap: () => onExpand(change.id),
                onRemove: () => onRemove(change.id),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 화면에 보여줄 제안 한 건. 주제 제안과 생애 정보 제안을 한 목록으로 편다.
class _ChangeItem {
  const _ChangeItem({
    required this.id,
    required this.kindLabel,
    required this.title,
    required this.reason,
  });

  /// 주제 제안을 먼저, 생애 정보 제안을 뒤에 둔다.
  static List<_ChangeItem> listOf(ChangeProposal proposal) => [
    for (final topic in proposal.topicProposals)
      _ChangeItem(
        id: topic.proposalId,
        kindLabel: _actionLabel(topic.suggestedAction),
        title: topic.topic.title,
        reason: topic.reason,
      ),
    for (final fact in proposal.lifeFactProposals)
      _ChangeItem(
        id: fact.proposalId,
        kindLabel: '새로 알게 된 이야기',
        title: fact.content,
        reason: fact.reason,
      ),
  ];

  /// 계약상 `suggestedAction` 은 `more`, `less`, `exclude` 셋이다.
  static String _actionLabel(TopicAction? action) => switch (action) {
    TopicAction.more => '더 자주 꺼내기',
    TopicAction.less => '당분간 쉬어가기',
    TopicAction.exclude => '제외하기',
    null => unsupportedValueLabel,
  };

  final String id;
  final String kindLabel;
  final String title;
  final String reason;
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

  final _ChangeItem change;
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
              Expanded(child: AppChip(change.kindLabel)),
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
                Text(change.title, style: AppTypography.sectionTitle),

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
}
