import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/profile_avatar.dart';
import '../profile_setup/setup_controller.dart';

/// 함께하는 소중한 분.
///
/// 홈 상단의 어르신 알약을 누르면 들어온다. 등록할 수 있는 어르신 수만큼
/// 슬롯을 두고, 채워진 슬롯을 누르면 그 어르신으로 바꿔 홈으로 돌아간다.
/// 빈 슬롯은 어르신을 더 등록하는 자리다. 등록하다 나간 분은 `입력 중` 슬롯으로
/// 남아, 누르면 멈춘 단계부터 이어서 입력한다.
///
/// 채워진 슬롯과 `입력 중` 슬롯은 꾹 눌러 끌면 순서를 바꿀 수 있다. 이 순서가
/// 홈의 전환 버튼이 넘어가는 순서다.
class ProfileSwitchScreen extends ConsumerWidget {
  const ProfileSwitchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(careProfileSummariesProvider);
    final pendingSetups = ref.watch(pendingSetupsProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: summaries.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '소중한 분 목록을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(careProfileSummariesProvider),
        ),
        data: (profiles) => SafeArea(
          top: false,
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            // 끌 수 있는 자리는 각 슬롯이 직접 정한다.
            buildDefaultDragHandles: false,
            onReorderItem: ref.read(careProfilesProvider.notifier).reorder,
            // 끄는 동안에도 카드 모양 그대로 보이게 기본 그림자 상자를 쓰지 않는다.
            proxyDecorator: (child, _, _) =>
                Material(color: Colors.transparent, child: child),
            header: const _Header(),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = profiles.length; i < CareProfiles.max; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.item),
                    child: _EmptySlot(onTap: () => _startAdding(context, ref)),
                  ),
              ],
            ),
            children: [
              for (var i = 0; i < profiles.length; i++)
                Padding(
                  key: ValueKey(profiles[i].id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.item),
                  child: ReorderableDelayedDragStartListener(
                    index: i,
                    child: profiles[i].pending
                        ? _PendingSlot(
                            index: i,
                            name:
                                pendingSetups[profiles[i].id]?.draft.name
                                    .trim() ??
                                '',
                            onTap: () =>
                                _resumeAdding(context, ref, profiles[i].id),
                          )
                        : _ProfileSlot(
                            index: i,
                            profile: profiles[i],
                            onTap: () => _switchTo(context, ref, profiles[i]),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 새로운 분을 등록하기 시작한다. 다른 분을 입력하던 중이어도 그 입력은
  /// `입력 중` 으로 남겨 두고 새로 시작한다.
  void _startAdding(BuildContext context, WidgetRef ref) {
    final id = ref.read(careProfilesProvider.notifier).beginAdding();
    if (id == null) return;
    ref.invalidate(setupControllerProvider);
    ref.read(pendingSetupsProvider.notifier).save(id, const SetupState());
    context.push(AppRoutes.profileAddOf(id));
  }

  /// `입력 중` 인 분의 입력을 멈춘 단계부터 다시 연다.
  void _resumeAdding(BuildContext context, WidgetRef ref, String id) {
    final saved = ref.read(pendingSetupsProvider)[id] ?? const SetupState();
    ref.read(setupControllerProvider.notifier).restore(saved);
    context.push(AppRoutes.profileAddOf(id));
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

/// 알약을 눌러 들어온 사람이 이곳에서 무엇을 하는지 먼저 알린다. 대화 카드
/// 화면처럼 큰 제목과 설명을 둔다.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const Text('함께하는 소중한 분', style: AppTypography.screenTitle),
        const SizedBox(height: AppSpacing.md),
        Text(
          '누르는 분의 정보로 앱 화면이 전환돼요.\n'
          '최대 ${CareProfiles.max}분까지 함께할 수 있어요.',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// 순서를 바꿀 수 있다는 표시다. 바로 끌어도 되고, 슬롯 어디든 꾹 눌러 끌어도
/// 된다.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: const Padding(
        padding: EdgeInsets.only(right: AppSpacing.sm),
        child: Icon(
          Icons.drag_indicator,
          color: AppColors.textSub,
          semanticLabel: '순서 바꾸기',
        ),
      ),
    );
  }
}

class _ProfileSlot extends StatelessWidget {
  const _ProfileSlot({
    required this.index,
    required this.profile,
    required this.onTap,
  });

  final int index;
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
          _DragHandle(index: index),
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

/// 등록하다 마치지 않고 나간 분이다.
class _PendingSlot extends StatelessWidget {
  const _PendingSlot({
    required this.index,
    required this.name,
    required this.onTap,
  });

  final int index;

  /// 아직 이름을 적지 않았으면 비어 있다.
  final String name;
  final VoidCallback onTap;

  static const _photo = 56.0;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          _DragHandle(index: index),
          Container(
            width: _photo,
            height: _photo,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(Icons.edit_outlined, color: AppColors.textSub),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              name.isEmpty ? '새로운 소중한 분' : '$name 어르신',
              style: AppTypography.bodyStrong,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const AppChip('입력 중', tone: ChipTone.weak),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.onTap});

  final VoidCallback onTap;

  static const _photo = 56.0;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
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
