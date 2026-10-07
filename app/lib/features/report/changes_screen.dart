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
import 'story_edit_screen.dart';

/// G-2 변경 사항 확인.
///
/// 계약이 정한 규칙은 다음과 같다(API 7-3, 7-4).
/// - 남겨 둔 항목은 `accepted`, 지운 항목은 `rejected` 로 보낸다.
/// - 회차의 `pending` 제안을 모두 한 번에 보낸다.
/// - 승인 전까지 프로필에 반영하지 않는다.
///
/// 주제 제안은 AI 가 제안한 행동이 처음에 골라져 있고, 보호자가 다른 행동을
/// 고를 수 있다. 제외하기도 그중 하나다. 생애 정보 제안은 보호자가 제목과
/// 내용을 고칠 수 있다.
///
/// 반영 버튼을 누르면 남긴 항목, 고른 행동과 고친 이야기로 7-4 요청
/// ([ProposalReview]) 을 만들어 저장소에 넘기고, 리포트 알림을 지운 뒤 홈으로
/// 간다. 요청의 `action`, `title`, `content` 는 이 화면을 위해 계약에 더한
/// 값이다. **지금은 목 데이터 단계라 저장소가 아무 데도 보내지 않는다.**
/// 서버를 붙이면 [MockRepository.submitProposalReview] 자리가 바뀐다.
class ReportChangesScreen extends ConsumerStatefulWidget {
  const ReportChangesScreen({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<ReportChangesScreen> createState() =>
      _ReportChangesScreenState();
}

class _ReportChangesScreenState extends ConsumerState<ReportChangesScreen> {
  /// 사용자가 지운 제안. 계약상 `rejected` 가 될 항목이지만 지금은 저장하지
  /// 않고 화면 표시에만 쓴다.
  final _removed = <String>{};

  /// 보호자가 고른 주제 행동. 없으면 AI 제안을 따른다.
  final _chosen = <String, TopicAction>{};

  /// 보호자가 고친 이야기. 없으면 AI 가 제안한 제목과 내용을 따른다.
  final _edited = <String, StoryDraft>{};

  /// 이유를 펼친 제안. 한 번에 하나만 펼친다.
  String? _expandedId;

  /// 반영을 보내는 중. 두 번 보내지 않도록 버튼을 막는다.
  bool _submitting = false;

  void _toggleReason(String id) =>
      setState(() => _expandedId = _expandedId == id ? null : id);

  Future<void> _edit(LifeFactProposal fact) async {
    final current =
        _edited[fact.proposalId] ??
        StoryDraft(title: fact.title, content: fact.content);
    final result = await StoryEditScreen.open(
      context,
      reportId: widget.reportId,
      initial: current,
    );
    if (result == null || !mounted) return;
    setState(() {
      // 원래 제안과 같게 되돌렸으면 고친 것으로 치지 않는다.
      if (result.title == fact.title && result.content == fact.content) {
        _edited.remove(fact.proposalId);
      } else {
        _edited[fact.proposalId] = result;
      }
    });
  }

  void _remove(String id) => setState(() {
    _removed.add(id);
    if (_expandedId == id) _expandedId = null;
  });

  /// 남긴 주제의 최종 행동. 보호자가 고르지 않았으면 AI 제안이다.
  TopicAction? _actionOf(TopicProposal topic) =>
      _chosen[topic.proposalId] ?? topic.suggestedAction;

  /// 회차의 제안을 모두 담은 7-4 요청을 만든다. 남긴 항목은 `accepted`, 뺀
  /// 항목은 `rejected` 다. 모두 뺐으면 `반영하지 않고 마치기` 와 같다.
  ProposalReview _review(ChangeProposal proposal) => ProposalReview(
    lifeFacts: [
      for (final fact in proposal.lifeFactProposals)
        if (_removed.contains(fact.proposalId))
          LifeFactReview.rejected(proposalId: fact.proposalId)
        else
          LifeFactReview.accepted(
            proposalId: fact.proposalId,
            title: _edited[fact.proposalId]?.title ?? fact.title,
            content: _edited[fact.proposalId]?.content ?? fact.content,
          ),
    ],
    topics: [
      for (final topic in proposal.topicProposals)
        if (_removed.contains(topic.proposalId))
          TopicReview.rejected(proposalId: topic.proposalId)
        else
          TopicReview.accepted(
            proposalId: topic.proposalId,
            action: _actionOf(topic)!,
          ),
    ],
  );

  Future<void> _apply(ChangeProposal proposal) async {
    setState(() => _submitting = true);
    await ref
        .read(mockRepositoryProvider)
        .submitProposalReview(proposal.sessionId, _review(proposal));
    if (!mounted) return;
    ref.read(reportNoticeProvider.notifier).dismiss();
    context.go(AppRoutes.home);
  }

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
        data: (data) {
          final topics = data.topicProposals
              .where((t) => !_removed.contains(t.proposalId))
              .toList();
          final facts = data.lifeFactProposals
              .where((f) => !_removed.contains(f.proposalId))
              .toList();

          // AI 제안을 읽지 못했고 보호자도 고르지 않은 주제는 보낼 행동이 없다.
          final undecided = topics.any((t) => _actionOf(t) == null);

          return _Body(
            empty: topics.isEmpty && facts.isEmpty,
            undecided: undecided,
            onApply: _submitting || undecided ? null : () => _apply(data),
            sections: [
              if (topics.isNotEmpty)
                _Section(
                  title: '대화 주제',
                  description: '다음 대화 카드를 만들 때 반영해요.',
                  cards: [
                    for (final topic in topics)
                      _TopicCard(
                        proposal: topic,
                        chosen:
                            _chosen[topic.proposalId] ?? topic.suggestedAction,
                        onChoose: (action) =>
                            setState(() => _chosen[topic.proposalId] = action),
                        reasonOpen: _expandedId == topic.proposalId,
                        onToggleReason: () => _toggleReason(topic.proposalId),
                        onRemove: () => _remove(topic.proposalId),
                      ),
                  ],
                ),
              if (facts.isNotEmpty)
                _Section(
                  title: '일대기에 추가',
                  description: '남겨두신 이야기를 일대기에 더해요.',
                  cards: [
                    for (final fact in facts)
                      _LifeFactCard(
                        proposal: fact,
                        edited: _edited[fact.proposalId],
                        onEdit: () => _edit(fact),
                        reasonOpen: _expandedId == fact.proposalId,
                        onToggleReason: () => _toggleReason(fact.proposalId),
                        onRemove: () => _remove(fact.proposalId),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.empty,
    required this.undecided,
    required this.sections,
    required this.onApply,
  });

  final bool empty;

  /// 행동을 고르지 않은 주제가 남아 반영할 수 없다.
  final bool undecided;
  final List<_Section> sections;

  /// `null` 이면 반영 버튼을 막는다.
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (undecided) ...[
            const Text(
              '어떻게 할지 고르지 않은 주제가 있어요.',
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          PrimaryButton(
            label: empty ? '반영하지 않고 마치기' : '이대로 반영하기',
            onPressed: onApply,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '다음 만남 때는\n이렇게 바꿀까요?',
            style: AppTypography.screenTitle,
          ),
          const SizedBox(height: AppSpacing.xl),

          if (empty)
            const EmptyStateView(
              message: '모두 지우셨어요.\n이대로 마쳐도 괜찮아요.',
              icon: Icons.inbox_outlined,
            )
          else
            ...sections,

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// 반영되는 곳이 같은 제안의 묶음. 구역 이름 아래에 어디에 반영되는지 한 줄로
/// 알리고 카드를 한 장씩 쌓는다.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.cards,
  });

  final String title;
  final String description;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(description, style: AppTypography.sub),
          const SizedBox(height: AppSpacing.lg),
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            card,
          ],
        ],
      ),
    );
  }
}

/// 주제 행동마다 화면에 쓰는 문구. 계약상 `more`, `less`, `exclude` 셋이다.
extension on TopicAction {
  String get label => switch (this) {
    TopicAction.more => '더 자주 꺼내기',
    TopicAction.less => '당분간 쉬어가기',
    TopicAction.exclude => '제외하기',
  };

  /// 골랐을 때 바로 아래에 보여주는 설명.
  String get effect => switch (this) {
    TopicAction.more => '다음 추천에서 이 주제의 우선순위를 높여요.',
    TopicAction.less => '다음 추천에서 이 주제의 우선순위를 낮춰요.',
    TopicAction.exclude => '앞으로 이 주제는 추천하지 않아요.',
  };
}

/// 주제 제안 한 장.
///
/// 위에 주제 제목과 설명, 그 아래 행동 세 줄, 선 아래에 접힌 AI 제안 이유를
/// 둔다. 행동은 글자가 길어 한 줄에 셋을 두지 않고 한 줄에 하나씩 둔다.
class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.proposal,
    required this.chosen,
    required this.onChoose,
    required this.reasonOpen,
    required this.onToggleReason,
    required this.onRemove,
  });

  final TopicProposal proposal;

  /// 지금 고른 행동. AI 제안을 읽지 못했고 아직 고르지 않았으면 `null` 이다.
  final TopicAction? chosen;
  final ValueChanged<TopicAction> onChoose;
  final bool reasonOpen;
  final VoidCallback onToggleReason;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final description = proposal.topic.description;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // 지우기 버튼은 카드 모서리 가까이 올리고, 제목은 그만큼 내려
            // 카드 위 여백을 지킨다.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposal.topic.title,
                          style: AppTypography.sectionTitle,
                        ),
                        if (description != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(description, style: AppTypography.sub),
                        ],
                      ],
                    ),
                  ),
                ),
                _RemoveButton(onPressed: onRemove),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, action) in TopicAction.values.indexed) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _ActionOption(
                    action: action,
                    selected: chosen == action,
                    suggested: proposal.suggestedAction == action,
                    onTap: () => onChoose(action),
                  ),
                  if (chosen == action)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Text(action.effect, style: AppTypography.sub),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _ReasonFold(
            reason: proposal.reason,
            open: reasonOpen,
            onToggle: onToggleReason,
          ),
        ],
      ),
    );
  }
}

/// 주제 행동 한 줄.
///
/// 고른 줄은 검정 면에 흰 글자로 강조하고, 색만으로 알리지 않도록 왼쪽에
/// 체크 표시를 함께 둔다. AI 가 제안한 줄은 오른쪽에 `AI 제안` 을 적는다.
class _ActionOption extends StatelessWidget {
  const _ActionOption({
    required this.action,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  final TopicAction action;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.background : AppColors.ink;
    final radius = BorderRadius.circular(AppRadius.button);

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? AppColors.ink : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected ? AppColors.background : AppColors.line,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      action.label,
                      style: AppTypography.bodyStrong.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                  if (suggested) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'AI 제안',
                      style: AppTypography.caption.copyWith(
                        color: selected
                            ? AppColors.background
                            : AppColors.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드 아래의 접힌 AI 제안 이유. 누르면 연한 회색 상자에 이유가 펼쳐진다.
class _ReasonFold extends StatelessWidget {
  const _ReasonFold({
    required this.reason,
    required this.open,
    required this.onToggle,
  });

  final String reason;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            borderRadius: open
                ? null
                : const BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.card),
                  ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('AI 제안 이유 보기', style: AppTypography.sub),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSub,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: AppSurfaceBox(child: Text(reason, style: AppTypography.sub)),
          ),
      ],
    );
  }
}

/// 이번 반영에서 이 제안만 빼는 버튼. 주제의 제외하기와 다르다.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: '이 제안 지우기',
      iconSize: 22,
      color: AppColors.textSub,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouch,
        minHeight: AppSizes.minTouch,
      ),
      icon: const Icon(Icons.close),
    );
  }
}

/// 생애 정보 제안 한 장.
///
/// 주제 카드와 같은 틀이다. 위에 새 이야기 표시와 제목, 그 아래 내용, 그 아래
/// `이야기 수정하기`, 선 아래에 접힌 AI 제안 이유를 둔다. 보호자가 고친 값이
/// 있으면 그 값을 보여주고 고쳤다고 알린다. 제안 이유는 AI 가 처음 제안한
/// 내용에 대한 것이라 그대로 둔다.
class _LifeFactCard extends StatelessWidget {
  const _LifeFactCard({
    required this.proposal,
    required this.edited,
    required this.onEdit,
    required this.reasonOpen,
    required this.onToggleReason,
    required this.onRemove,
  });

  final LifeFactProposal proposal;

  /// 보호자가 고친 제목과 내용. 고치지 않았으면 `null` 이다.
  final StoryDraft? edited;
  final VoidCallback onEdit;
  final bool reasonOpen;
  final VoidCallback onToggleReason;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final title = edited?.title ?? proposal.title;
    final content = edited?.content ?? proposal.content;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // 지우기 버튼은 카드 모서리 가까이 올리고, 제목은 그만큼 내려
            // 카드 위 여백을 지킨다. 주제 카드와 같다.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          // 제목 첫 줄의 가운데에 맞춘다.
                          padding: EdgeInsets.only(top: 3),
                          child: _NewBadge(),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(title, style: AppTypography.sectionTitle),
                        ),
                      ],
                    ),
                  ),
                ),
                _RemoveButton(onPressed: onRemove),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(content, style: AppTypography.sub),
                if (edited != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '직접 고친 이야기예요.',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(label: '이야기 수정하기', onPressed: onEdit),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          _ReasonFold(
            reason: proposal.reason,
            open: reasonOpen,
            onToggle: onToggleReason,
          ),
        ],
      ),
    );
  }
}

/// 일대기에 새로 더해질 이야기라는 표시. 화면 낭독기에는 `새 이야기` 로 읽힌다.
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '새 이야기',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            'NEW',
            style: AppTypography.caption.copyWith(
              color: AppColors.background,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
