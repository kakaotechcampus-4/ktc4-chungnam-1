import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'stories_provider.dart';

String storySource(LifeFact fact) => switch (fact.sourceType) {
  'visitConfirmed' => '면회 후 확인',
  'caregiverTextInput' || 'caregiverVoiceInput' => '직접 추가',
  _ => '출처 확인 필요',
};

String storyDate(LifeFact fact) {
  final date = fact.createdAt?.toLocal();
  if (date == null) return '저장 날짜 없음';
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} 저장';
}

class StoryTile extends StatelessWidget {
  const StoryTile({required this.fact, super.key});
  final LifeFact fact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.profileStoryOf(fact.factId)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fact.title.isEmpty ? '남겨 둔 이야기' : fact.title,
                      style: AppTypography.bodyStrong,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                fact.text,
                style: AppTypography.sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(storySource(fact), style: AppTypography.caption),
                  Text(storyDate(fact), style: AppTypography.caption),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StoriesScreen extends ConsumerWidget {
  const StoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: const AppTopBar(title: '쌓아온 이야기'),
    body: ref
        .watch(profileStoriesProvider)
        .when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorStateView(
            message: '이야기를 불러오지 못했어요.',
            onRetry: () => ref.invalidate(profileProvider),
          ),
          data: (facts) => ListView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            children: [
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.profileStoryAdd),
                icon: const Icon(Icons.add),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('이야기 추가하기'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('알고 계신 이야기를 하나씩 남겨 주세요.', style: AppTypography.sub),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                children: [
                  Text('전체 ${facts.length}개', style: AppTypography.sub),
                  const Text('최근 저장순', style: AppTypography.sub),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (facts.isEmpty)
                const EmptyStateView(
                  message: '아직 쌓아온 이야기가 없어요.\n첫 이야기를 추가해 주세요.',
                  icon: Icons.notes_outlined,
                ),
              for (final fact in facts) StoryTile(fact: fact),
            ],
          ),
        ),
  );
}

class StoryDetailScreen extends ConsumerWidget {
  const StoryDetailScreen({required this.factId, super.key});
  final String factId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: const AppTopBar(title: '이야기 상세'),
    body: ref
        .watch(profileStoriesProvider)
        .when(
          loading: () => const LoadingView(),
          error: (_, _) => ErrorStateView(
            message: '이야기를 불러오지 못했어요.',
            onRetry: () => ref.invalidate(profileProvider),
          ),
          data: (facts) {
            final fact = facts.where((f) => f.factId == factId).firstOrNull;
            if (fact == null) {
              return const EmptyStateView(message: '이야기를 찾을 수 없어요.');
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                Text(
                  fact.title.isEmpty ? '남겨 둔 이야기' : fact.title,
                  style: AppTypography.sectionTitle,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(storySource(fact), style: AppTypography.sub),
                    Text(storyDate(fact), style: AppTypography.sub),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(fact.text, style: AppTypography.body),
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoryEditorScreen(fact: fact),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('이야기 수정하기'),
                  ),
                ),
              ],
            );
          },
        ),
  );
}

class StoryEditorScreen extends ConsumerStatefulWidget {
  const StoryEditorScreen({this.fact, super.key});
  final LifeFact? fact;
  @override
  ConsumerState<StoryEditorScreen> createState() => _StoryEditorState();
}

class _StoryEditorState extends ConsumerState<StoryEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.fact?.title);
  late final _text = TextEditingController(text: widget.fact?.text);
  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final bundle = ref.read(profileProvider).asData?.value;
    final facts = ref.read(profileStoriesProvider).asData?.value;
    if (bundle == null || facts == null) return;
    final now = DateTime.now();
    ref
        .read(storiesProvider.notifier)
        .save(
          bundle.profile.profileId,
          facts,
          LifeFact(
            factId:
                widget.fact?.factId ??
                'fact_mock_${now.microsecondsSinceEpoch}',
            category: widget.fact?.category,
            title: _title.text.trim(),
            text: _text.text.trim(),
            sourceType: widget.fact?.sourceType ?? 'caregiverTextInput',
            createdAt: widget.fact?.createdAt ?? now,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: widget.fact == null ? '이야기 추가' : '이야기 수정'),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            const Text(
              '어르신에 대해 알고 계신 이야기를 남겨 주세요.\n다음 대화를 준비할 때 참고할 수 있어요.',
              style: AppTypography.sub,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              controller: _title,
              maxLength: 100,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 손수 만들던 명절 옷',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '제목을 입력해 주세요.' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _text,
              minLines: 5,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '내용',
                alignLabelWithHint: true,
                hintText: '어떤 이야기인지 구체적으로 적어 주세요.',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '내용을 입력해 주세요.' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '한 번에 하나의 이야기를 남기면 다시 찾기 쉬워요.',
              style: AppTypography.sub,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: ref.watch(profileStoriesProvider).asData == null
                  ? null
                  : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(widget.fact == null ? '이야기 저장하기' : '수정한 내용 저장'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
