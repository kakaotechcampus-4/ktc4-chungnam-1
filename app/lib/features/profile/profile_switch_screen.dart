import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/profile_avatar.dart';

/// 함께하는 소중한 분.
///
/// 홈 상단의 어르신 알약을 누르면 들어온다. 등록할 수 있는 어르신 수만큼
/// 슬롯을 두고, 채워진 슬롯을 누르면 그 어르신으로 바꿔 홈으로 돌아간다.
/// 빈 슬롯은 어르신을 더 등록하는 자리다.
class ProfileSwitchScreen extends ConsumerWidget {
  const ProfileSwitchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(careProfileSummariesProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: summaries.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '소중한 분 목록을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(careProfileSummariesProvider),
        ),
        data: (profiles) => ScreenBody(
          scrollable: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 알약을 눌러 들어온 사람이 이곳에서 무엇을 하는지 먼저 알린다.
              // 대화 카드 화면처럼 큰 제목과 설명을 둔다.
              const SizedBox(height: AppSpacing.sm),
              const Text('함께하는 소중한 분', style: AppTypography.screenTitle),
              const SizedBox(height: AppSpacing.md),
              Text(
                '누르는 분의 정보로 앱 화면이 전환돼요.\n'
                '최대 ${CareProfiles.max}분까지 함께할 수 있어요.',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.xl),
              for (var i = 0; i < CareProfiles.max; i++) ...[
                if (i < profiles.length)
                  _ProfileSlot(
                    profile: profiles[i],
                    onTap: () => _switchTo(context, ref, profiles[i]),
                  )
                else
                  // 어르신 추가는 다음 작업에서 연결한다.
                  const _EmptySlot(),
                const SizedBox(height: AppSpacing.item),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 고른 어르신으로 바꾸고 홈으로 돌아가 누구로 바뀌었는지 알린다.
  void _switchTo(
    BuildContext context,
    WidgetRef ref,
    CareProfileSummary profile,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.maybePop(context);
    if (profile.selected) return;

    ref.read(careProfilesProvider.notifier).select(profile.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('지금부터 ${profile.name} 어르신과 함께해요')));
  }
}

class _ProfileSlot extends StatelessWidget {
  const _ProfileSlot({required this.profile, required this.onTap});

  final CareProfileSummary profile;
  final VoidCallback onTap;

  static const _photo = 56.0;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      selected: profile.selected,
      onTap: onTap,
      child: Row(
        children: [
          ProfileAvatar(gender: profile.gender, size: _photo),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text('${profile.name} 어르신', style: AppTypography.bodyStrong),
          ),
          const SizedBox(width: AppSpacing.md),
          // 테두리 굵기만으로 알리지 않도록 표시를 함께 둔다.
          SelectionMark(selected: profile.selected),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  static const _photo = 56.0;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: _photo,
            height: _photo,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(Icons.add, color: AppColors.textSub),
          ),
          const SizedBox(width: AppSpacing.lg),
          const Expanded(child: Text('소중한 분 더하기', style: AppTypography.body)),
        ],
      ),
    );
  }
}
