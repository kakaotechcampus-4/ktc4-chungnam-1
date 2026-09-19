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
import '../home/my_page_menu.dart';

/// H 일대기. 이야기를 인생 시기별로 묶어 몇 개씩 있는지 보여준다.
///
/// `LifeFact.lifeStage`로 묶는다. 이 필드는 이번에 새로 추가됐고, 누가 값을
/// 정하는지(보호자 선택 / AI 추정)는 아직 정해지지 않았다
/// (`docs/architecture/data-contracts.md` 참고). 그 결정이 나기 전까지는
/// mock 데이터로 화면만 먼저 만든다.
///
/// "전체 보기"로 갈 목록 화면이 아직 없어 눌러도 반응하지 않는다.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '이야기를 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) => _Body(facts: bundle.lifeFacts),
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.album,
        onSelected: (tab) {
          switch (tab) {
            case AppTab.album:
              break;
            case AppTab.home:
              context.go(AppRoutes.home);
            case AppTab.myPage:
              showMyPageMenu(context);
          }
        },
      ),
    );
  }
}

class _StageInfo {
  const _StageInfo(this.stage, this.icon);

  final LifeStage stage;
  final IconData icon;
}

const _stages = <_StageInfo>[
  _StageInfo(LifeStage.childhood, Icons.emoji_emotions_outlined),
  _StageInfo(LifeStage.adolescence, Icons.eco_outlined),
  _StageInfo(LifeStage.youngAdult, Icons.star_outline),
  _StageInfo(LifeStage.marriageParenting, Icons.favorite_outline),
  _StageInfo(LifeStage.middleAge, Icons.wb_sunny_outlined),
  _StageInfo(LifeStage.other, Icons.more_horiz),
];

class _Body extends StatelessWidget {
  const _Body({required this.facts});

  final List<LifeFact> facts;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          Image.asset('assets/images/album-pouch.webp', width: 180),
          const SizedBox(height: AppSpacing.section),

          AppCard(
            child: Column(
              children: [
                const Text('이야기 현황', style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.lg),

                for (var row = 0; row < _stages.length; row += 2) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _StageTile(
                          info: _stages[row],
                          count: _countOf(_stages[row].stage),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StageTile(
                          info: _stages[row + 1],
                          count: _countOf(_stages[row + 1].stage),
                        ),
                      ),
                    ],
                  ),
                  if (row + 2 < _stages.length)
                    const SizedBox(height: AppSpacing.md),
                ],

                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: '전체 보기',
                  // 이야기를 모두 나열해 볼 목록 화면이 아직 없다.
                  onPressed: null,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  int _countOf(LifeStage stage) =>
      facts.where((f) => f.lifeStage == stage).length;
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.info, required this.count});

  final _StageInfo info;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Icon(info.icon, color: AppColors.ink),
          const SizedBox(height: AppSpacing.sm),
          Text(info.stage.label, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppChip('$count개', tone: ChipTone.weak),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSub,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
