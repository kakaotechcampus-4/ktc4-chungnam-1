import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import 'album_story_detail_screen.dart';

/// 일대기 이야기 목록. 전체 보기로 들어오면 [stage] 가 없고, 인생 시기
/// 카드를 눌러 들어오면 그 시기로 걸러 보여준다.
///
/// 날짜는 `LifeFact.createdAt` 을 쓴다. "어느 면회에서 나온 이야기인지"를
/// 가리키는 진짜 값이 계약에 없어서다(`docs/architecture/data-contracts.md`
/// 참고). 항목을 누르면 상세 화면으로 가는데, `app/lib/app/` 을 건드리지
/// 않기로 해서 go_router 경로 대신 `Navigator.push` 로 연다.
class AlbumStoriesScreen extends ConsumerStatefulWidget {
  const AlbumStoriesScreen({this.stage, super.key});

  final LifeStage? stage;

  @override
  ConsumerState<AlbumStoriesScreen> createState() =>
      _AlbumStoriesScreenState();
}

enum _Sort { newest, oldest }

class _AlbumStoriesScreenState extends ConsumerState<AlbumStoriesScreen> {
  var _sort = _Sort.newest;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '이야기를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) {
          final facts = bundle.lifeFacts
              .where((f) => widget.stage == null || f.lifeStage == widget.stage)
              .toList()
            ..sort(
              (a, b) => _sort == _Sort.newest
                  ? b.createdAt.compareTo(a.createdAt)
                  : a.createdAt.compareTo(b.createdAt),
            );

          return _Body(
            title: widget.stage?.label ?? '전체 보기',
            subtitle: _subtitleOf(widget.stage),
            sort: _sort,
            onSortChanged: (value) => setState(() => _sort = value),
            facts: facts,
          );
        },
      ),
    );
  }

  static String _subtitleOf(LifeStage? stage) => switch (stage) {
    null => '차곡차곡 쌓인 대화 일기',
    LifeStage.childhood => '포근했던 어린 시절',
    LifeStage.adolescence => '설레던 그 시절 이야기',
    LifeStage.youngAdult => '한 걸음씩 나아가던 날들',
    LifeStage.marriageParenting => '가족과 함께한 이야기',
    LifeStage.middleAge => '무르익은 삶의 이야기',
    LifeStage.other => '그 밖의 소중한 순간들',
  };
}

class _Body extends StatelessWidget {
  const _Body({
    required this.title,
    required this.subtitle,
    required this.sort,
    required this.onSortChanged,
    required this.facts,
  });

  final String title;
  final String subtitle;
  final _Sort sort;
  final ValueChanged<_Sort> onSortChanged;
  final List<LifeFact> facts;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title, style: AppTypography.screenTitle),
              ),
              _SortToggle(value: sort, onChanged: onSortChanged),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: AppTypography.sub),
          const SizedBox(height: AppSpacing.section),

          if (facts.isEmpty)
            const EmptyStateView(
              message: '아직 담긴 이야기가 없어요.',
              icon: Icons.menu_book_outlined,
            )
          else
            for (final fact in facts) ...[
              _StoryRow(fact: fact),
              const SizedBox(height: AppSpacing.md),
            ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.value, required this.onChanged});

  final _Sort value;
  final ValueChanged<_Sort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SortOption(
          label: '최신순',
          selected: value == _Sort.newest,
          onTap: () => onChanged(_Sort.newest),
        ),
        const SizedBox(width: AppSpacing.xs),
        _SortOption(
          label: '오래된순',
          selected: value == _Sort.oldest,
          onTap: () => onChanged(_Sort.oldest),
        ),
      ],
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
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
      child: AppChip(
        label,
        tone: selected ? ChipTone.strong : ChipTone.weak,
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({required this.fact});

  final LifeFact fact;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumStoryDetailScreen(fact: fact),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.image),
            ),
            child: const Icon(Icons.person_outline, color: AppColors.textSub),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fact.lifeStage != null)
                  Text(fact.lifeStage!.label, style: AppTypography.caption),
                Text(
                  fact.title ?? fact.text,
                  style: AppTypography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(_dateLabel(fact.createdAt), style: AppTypography.sub),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSub),
        ],
      ),
    );
  }

  /// `2026-06-15T12:10:00+09:00` 를 `2026.06.15` 로 바꾼다.
  static String _dateLabel(String isoDateTime) {
    final datePart = isoDateTime.split('T').first;
    final parts = datePart.split('-');
    if (parts.length != 3) return datePart;
    return parts.join('.');
  }
}
