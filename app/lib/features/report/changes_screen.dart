import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

const topicActionLabels = {
  'more': '더 자주 꺼내기',
  'less': '덜 꺼내기',
  'exclude': '추천하지 않기',
};

/// 검토 결과만 보관하는 목 상태. AI 원안은 변경하지 않는다.
class ProposalDecision {
  const ProposalDecision(this.title, this.content, this.action, this.accepted);
  final String title;
  final String content;
  final String? action;
  final bool accepted;
}

class ProposalReviews
    extends Notifier<Map<String, Map<String, ProposalDecision>>> {
  @override
  Map<String, Map<String, ProposalDecision>> build() => {};
  void settle(String reportId, Map<String, ProposalDecision> decisions) {
    state = {...state, reportId: Map.unmodifiable(decisions)};
  }
}

final proposalReviewsProvider =
    NotifierProvider<
      ProposalReviews,
      Map<String, Map<String, ProposalDecision>>
    >(ProposalReviews.new);

class ReportChangesScreen extends ConsumerStatefulWidget {
  const ReportChangesScreen({required this.reportId, super.key});
  final String reportId;
  @override
  ConsumerState<ReportChangesScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReportChangesScreen> {
  final _removed = <String>{};
  final _actions = <String, String>{};
  final _edits = <String, (String, String)>{};

  String? _suggested(ProposedChange c) =>
      c.suggestedAction ??
      switch (c.direction) {
        'up' => 'more',
        'down' => 'less',
        _ => null,
      };
  String _title(ProposedChange c) =>
      _edits[c.changeId]?.$1 ??
      (c.changeType == 'topicPriority' ? c.topicTitle : c.title) ??
      '새로 알게 된 이야기';
  String _content(ProposedChange c) =>
      _edits[c.changeId]?.$2 ??
      (c.changeType == 'topicPriority' ? c.description : c.text) ??
      '';

  Future<void> _edit(ProposedChange c) async {
    final value = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute(
        builder: (_) => _ProposalEditor(
          topic: c.changeType == 'topicPriority',
          title: _title(c),
          content: _content(c),
        ),
      ),
    );
    if (mounted && value != null) {
      setState(() => _edits[c.changeId] = value);
    }
  }

  void _apply(ChangeProposal data) {
    if (ref.read(proposalReviewsProvider).containsKey(widget.reportId)) return;
    final bundle = ref.read(profileProvider).asData?.value;
    if (bundle == null) return;
    final decisions = <String, ProposalDecision>{};
    for (final c in data.changes) {
      final accepted = !_removed.contains(c.changeId);
      final action = c.changeType == 'topicPriority'
          ? _actions[c.changeId] ?? _suggested(c)
          : null;
      decisions[c.changeId] = ProposalDecision(
        _title(c),
        _content(c),
        action,
        accepted,
      );
    }
    ref
        .read(proposalReviewsProvider.notifier)
        .settle(widget.reportId, decisions);
    ref.read(reportNoticeProvider.notifier).dismiss();
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final settled = ref
        .watch(proposalReviewsProvider)
        .containsKey(widget.reportId);
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: const AppTopBar(title: '변경 사항 확인'),
      body: ref
          .watch(changeProposalProvider)
          .when(
            loading: () => const LoadingView(),
            error: (_, _) => ErrorStateView(
              message: '변경 사항을 불러오지 못했어요.',
              onRetry: () => ref.invalidate(changeProposalProvider),
            ),
            data: (data) {
              if (data.reportId != widget.reportId) {
                return const EmptyStateView(message: '이 리포트의 변경 제안을 찾을 수 없어요.');
              }
              if (settled) {
                return const EmptyStateView(message: '이미 확인을 마친 제안이에요.');
              }
              final active = data.changes
                  .where((c) => !_removed.contains(c.changeId))
                  .toList();
              final invalid = active.any(
                (c) =>
                    !['topicPriority', 'lifeFactAdd'].contains(c.changeType) ||
                    (c.changeType == 'topicPriority' &&
                        !topicActionLabels.containsKey(
                          _actions[c.changeId] ?? _suggested(c),
                        )),
              );
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.screen),
                children: [
                  const Text(
                    '다음 만남을 위해\n함께 확인해 주세요',
                    style: AppTypography.screenTitle,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '주제 추천 방식을 고르고,\n새로 알게 된 이야기를 확인해 주세요.',
                    style: AppTypography.body,
                  ),
                  for (final kind in ['topicPriority', 'lifeFactAdd']) ...[
                    const SizedBox(height: 32),
                    Text(
                      kind == 'topicPriority' ? '대화 주제' : '쌓아온 이야기에 추가',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kind == 'topicPriority'
                          ? '주제별로 추천 방식을 선택해 주세요.'
                          : '맞는 내용인지 확인하고 필요하면 수정해 주세요.',
                      style: AppTypography.sub,
                    ),
                    if (!data.changes.any((c) => c.changeType == kind))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('이번에는 제안된 항목이 없어요.'),
                      ),
                    for (final c in data.changes.where(
                      (c) => c.changeType == kind,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _card(c),
                      ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  Text(
                    '주제 ${active.where((c) => c.changeType == 'topicPriority').length}개 · '
                    '이야기 ${active.where((c) => c.changeType == 'lifeFactAdd').length}개를 반영해요',
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '×는 이번 제안만 반영하지 않아요.\n주제를 계속 제외하려면 ‘추천하지 않기’를 선택하세요.',
                    style: AppTypography.sub,
                  ),
                  if (invalid) const Text('확인할 수 없는 제안이 있어 반영할 수 없어요.'),
                  if (profile.hasError)
                    TextButton(
                      onPressed: () => ref.invalidate(profileProvider),
                      child: const Text('프로필을 불러오지 못했어요. 다시 시도'),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: invalid || profile.asData == null
                        ? null
                        : () => _apply(data),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        active.isEmpty
                            ? '반영 없이 마치기'
                            : '선택한 ${active.length}개 반영하기',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  Widget _card(ProposedChange c) {
    if (_removed.contains(c.changeId)) {
      return AppSurfaceBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(c), style: AppTypography.bodyStrong),
            const Text('이번 반영에서 뺐어요.', style: AppTypography.sub),
            TextButton(
              onPressed: () => setState(() => _removed.remove(c.changeId)),
              child: const Text('되돌리기'),
            ),
          ],
        ),
      );
    }
    final topic = c.changeType == 'topicPriority';
    final action = _actions[c.changeId] ?? _suggested(c);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  topic
                      ? 'AI 제안 · ${topicActionLabels[_suggested(c)] ?? '확인 필요'}'
                      : '확인이 필요한 이야기',
                  style: AppTypography.sub,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _removed.add(c.changeId)),
                tooltip: '${_title(c)} 이번 반영에서 빼기',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(_title(c), style: AppTypography.sectionTitle),
          const SizedBox(height: 8),
          Text(_content(c), style: AppTypography.body),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _edit(c),
              child: Text(topic ? '주제 이름·설명 수정' : '이야기 수정'),
            ),
          ),
          if (topic) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in topicActionLabels.entries)
                  Semantics(
                    selected: action == entry.key,
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _actions[c.changeId] = entry.key),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: action == entry.key
                            ? AppColors.ink
                            : AppColors.background,
                        foregroundColor: action == entry.key
                            ? AppColors.background
                            : AppColors.ink,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '${action == entry.key ? '✓ ' : ''}${entry.value}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(switch (action) {
              'exclude' => '앞으로 이 주제를 추천하지 않아요. 과거 기록은 유지해요.',
              'less' => '다음 추천에서 이 주제의 우선순위를 낮춰요.',
              'more' => '다음 추천에서 이 주제의 우선순위를 높여요.',
              _ => '추천 방식을 선택해 주세요.',
            }, style: AppTypography.sub),
          ],
          Material(
            color: AppColors.background,
            child: ExpansionTile(
              key: PageStorageKey(c.changeId),
              tilePadding: EdgeInsets.zero,
              title: const Text('AI 제안 이유 보기', style: AppTypography.sub),
              children: [
                AppSurfaceBox(child: Text(c.reason, style: AppTypography.body)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalEditor extends StatefulWidget {
  const _ProposalEditor({
    required this.topic,
    required this.title,
    required this.content,
  });
  final bool topic;
  final String title, content;
  @override
  State<_ProposalEditor> createState() => _EditorState();
}

class _EditorState extends State<_ProposalEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.title);
  late final _content = TextEditingController(text: widget.content);
  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: widget.topic ? '주제 표현 수정' : '이야기 수정'),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.topic
                ? '같은 주제의 이름과 설명을 다듬어 주세요. 다른 주제로 바꾸는 기능은 아니에요.'
                : '확인하신 내용으로 고쳐 주세요.',
            style: AppTypography.sub,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '제목'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? '제목을 입력해 주세요.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _content,
            minLines: 4,
            maxLines: null,
            decoration: InputDecoration(labelText: widget.topic ? '설명' : '내용'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? '내용을 입력해 주세요.' : null,
          ),
          const SizedBox(height: 16),
          const Text('수정 내용은 마지막에 ‘반영하기’를 눌러야 적용돼요.', style: AppTypography.sub),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, (
                  _title.text.trim(),
                  _content.text.trim(),
                ));
              }
            },
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('수정 완료'),
            ),
          ),
        ],
      ),
    ),
  );
}
