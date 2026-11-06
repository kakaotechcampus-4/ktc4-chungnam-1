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
import '../../widgets/profile_avatar.dart';
import '../profile_setup/setup_steps.dart';
import 'profile_gallery.dart';

/// 프로필 설정. 하단 탭의 마이페이지로 들어온다.
///
/// 피그마에는 `MYPAGE` 로 되어 있으나 화면 이름은 프로필 설정이다. 지금 고른
/// 어르신의 사진, 기본 정보, 세부 정보와 갤러리를 보여준다. 계정 약관 동의,
/// 로그아웃과 회원탈퇴는 설정 탭으로 옮겼다(2026-11-06 디자인 리뉴얼).
///
/// 이름과 생년월일은 계약상 `localOnly` 라 단말에만 두며 외부 요청에 담지 않는다.
///
/// 등록한 어르신이 없으면 등록부터 안내한다.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: const AppTopBar(title: '프로필 설정'),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '프로필을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) => bundle == null
            ? EmptyStateView(
                message: '함께하는 소중한 분을 등록하면\n정보를 볼 수 있어요.',
                icon: Icons.person_add_alt_1_outlined,
                actionLabel: '등록하러 가기',
                onAction: () => context.push(AppRoutes.profileSwitch),
              )
            : _Body(bundle: bundle),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.bundle});

  final ProfileBundle bundle;

  @override
  Widget build(BuildContext context) {
    final profile = bundle.profile;
    void editBasic() => context.push(AppRoutes.profileEditBasic);

    // ScreenBody 의 scrollable 은 내용 높이를 미리 재어(IntrinsicHeight) 화면
    // 높이를 채운다. 갤러리에서 사진을 눌러 펼친 설명 칸은 여러 줄 입력칸이라
    // 그 값이 실제보다 작게 나올 수 있고, 갤러리가 맨 아래라 그 넘침이 저장하기를
    // 가렸다(웹 미리보기에서 1픽셀). 이 화면은 높이를 채울 일이 없어 그냥
    // 스크롤한다.
    return ScreenBody(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Column(
                children: [
                  ProfileAvatar(gender: profile.gender, size: 130),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${profile.name} 어르신',
                          style: AppTypography.sectionTitle,
                        ),
                      ),
                      // 이름도 기본 정보 수정에서 고친다.
                      IconButton(
                        onPressed: editBasic,
                        tooltip: '이름 수정',
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.textSub,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            _Section(
              title: '기본 정보',
              onEdit: editBasic,
              child: Column(
                children: [
                  _InfoRow(label: '성별', value: _genderLabel(profile.gender)),
                  _InfoRow(label: '생년월일', value: _dateLabel(profile.birthDate)),
                  _InfoRow(label: '연령대', value: _ageLabel(profile.ageRange)),
                  _InfoRow(
                    label: '현재 상태',
                    value: profile.stage?.label ?? unsupportedValueLabel,
                  ),
                  if (profile.symptomNote != null)
                    _InfoRow(label: '메모', value: profile.symptomNote!),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            _Section(
              title: '세부 정보',
              onEdit: () => context.push(AppRoutes.profileEditDetails),
              child: _Details(profile: profile),
            ),
            // 세부 정보 네 항목 밖의 생애 정보는 일대기에서 더한다. 여기서는 두지 않는다.
            const SizedBox(height: AppSpacing.section),

            // 사진 설명은 갤러리에서 사진을 눌러 바로 고친다(`ProfileGallery`). 사진을
            // 더하거나 지우는 화면은 없어서 머리글의 수정하기를 두지 않는다.
            _Section(
              title: '갤러리',
              child: _Gallery(mockPhotos: bundle.photos),
            ),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }

  static String _genderLabel(String raw) => switch (raw) {
    'male' => '남성',
    'female' => '여성',
    _ => raw,
  };

  /// `1943-03-12` 를 `1943년 3월 12일` 로 바꾼다.
  static String _dateLabel(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return isoDate;
    return '$year년 $month월 $day일';
  }

  /// `80s` 를 `80대` 로 바꾼다.
  static String _ageLabel(String raw) =>
      raw.endsWith('s') ? '${raw.substring(0, raw.length - 1)}대' : raw;
}

/// 갤러리의 사진. 서버에 저장한 분은 서버의 사진(2-3)을, 로그인 없이 들어온
/// 분은 목 사진을 보여준다.
///
/// 서버 사진을 읽지 못하면 사진이 없다고 하지 않고 다시 시도를 둔다.
class _Gallery extends ConsumerWidget {
  const _Gallery({required this.mockPhotos});

  final List<ProfilePhoto> mockPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverProfilePhotosProvider);
    return server.when(
      data: (photos) => ProfileGallery(photos: photos ?? mockPhotos),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('사진을 불러오지 못했어요.', style: AppTypography.sub),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: '다시 시도',
            onPressed: () => ref.invalidate(serverProfilePhotosProvider),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onEdit});

  final String title;
  final Widget child;

  /// `null` 이면 머리글에 수정하기를 두지 않는다. 눌러도 갈 곳이 없는 버튼을
  /// 보이지 않기 위해서다.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.sectionTitle)),
            if (onEdit case final onEdit?)
              TextButton.icon(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSub,
                  minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('수정하기', style: AppTypography.caption),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: AppTypography.sub)),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

/// 세부 정보 네 항목 중 적어 둔 것만 보여준다. 하나도 없으면 비어 있다고 알린다.
class _Details extends StatelessWidget {
  const _Details({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final filled = [
      for (final step in lifeFactSteps)
        if (profile.detailOf(step.category) case final text?)
          (label: step.label, text: text),
    ];
    if (filled.isEmpty) {
      return const EmptyStateView(
        message: '아직 담긴 이야기가 없어요.',
        icon: Icons.notes_outlined,
      );
    }
    return Column(
      children: [
        for (final detail in filled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _DetailRow(label: detail.label, text: detail.text),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppChip(label, tone: ChipTone.weak),
          const SizedBox(height: AppSpacing.md),
          Text(text, style: AppTypography.body),
        ],
      ),
    );
  }
}
