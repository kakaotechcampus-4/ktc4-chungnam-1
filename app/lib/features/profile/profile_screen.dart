import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// 프로필 설정.
///
/// 피그마에는 `MYPAGE` 로 되어 있으나 화면 이름은 프로필 설정이다. 하단 탭의
/// 마이페이지를 눌러 뜨는 메뉴에서 들어온다.
///
/// 이름과 생년월일은 계약상 `localOnly` 라 단말에만 두며 외부 요청에 담지 않는다.
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
        data: (bundle) => _Body(bundle: bundle),
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

    return ScreenBody(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),

          Center(
            child: Column(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/images/patient.webp',
                    width: 130,
                    height: 130,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${profile.name} 어르신',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppColors.textSub,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          _Section(
            title: '기본 정보',
            onEdit: () {},
            child: Column(
              children: [
                _InfoRow(label: '성별', value: _genderLabel(profile.gender)),
                _InfoRow(label: '생년월일', value: _dateLabel(profile.birthDate)),
                _InfoRow(label: '연령대', value: _ageLabel(profile.ageRange)),
                _InfoRow(label: '현재 상태', value: profile.stage.label),
                if (profile.symptomNote != null)
                  _InfoRow(label: '메모', value: profile.symptomNote!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),

          _Section(
            title: '세부 정보',
            onEdit: () {},
            child: bundle.lifeFacts.isEmpty
                ? const EmptyStateView(
                    message: '아직 담긴 이야기가 없어요.',
                    icon: Icons.notes_outlined,
                  )
                : Column(
                    children: [
                      for (final fact in bundle.lifeFacts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _FactRow(fact: fact),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SecondaryButton(label: '내용 추가하기', onPressed: () {}),
          const SizedBox(height: AppSpacing.section),

          _Section(
            title: '갤러리',
            onEdit: () {},
            child: _Gallery(tags: bundle.photo.acceptedTags),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    required this.onEdit,
  });

  final String title;
  final Widget child;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.sectionTitle)),
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

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final LifeFact fact;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppChip(_categoryLabel(fact.category), tone: ChipTone.weak),
          const SizedBox(height: AppSpacing.md),
          Text(fact.text, style: AppTypography.body),
        ],
      ),
    );
  }

  /// `LifeFact.category` 값. 계약의 수집 항목과 같다.
  static String _categoryLabel(String raw) => switch (raw) {
    'occupation' => '하시던 일',
    'hometown' => '고향',
    'hobby' => '취미',
    'family' => '가족',
    _ => raw,
  };
}

/// 사진을 누르면 그 사진 아래에 이야기 소재 태그를 보여준다.
///
/// 태그는 사용자가 수락한 것만 담긴다(`ProfilePhoto.acceptedTags`).
class _Gallery extends StatefulWidget {
  const _Gallery({required this.tags});

  final List<String> tags;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  bool _showTags = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: InkWell(
                  onTap: () => setState(() => _showTags = !_showTags),
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.image),
                        child: Image.asset(
                          'assets/images/family.webp',
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (_showTags)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppRadius.image,
                            ),
                            border: Border.all(color: AppColors.ink, width: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            for (var i = 0; i < 2; i++) ...[
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.image),
                    ),
                    child: const Icon(Icons.add, color: AppColors.textDisabled),
                  ),
                ),
              ),
              if (i == 0) const SizedBox(width: AppSpacing.md),
            ],
          ],
        ),

        if (_showTags) ...[
          const SizedBox(height: AppSpacing.md),
          if (widget.tags.isEmpty)
            Text(
              '이 사진에서 담은 이야기 소재가 없어요.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textDisabled,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final tag in widget.tags) _SmallTag(tag)],
            ),
        ],
      ],
    );
  }
}

/// 사진 아래에 붙는 작은 태그다.
class _SmallTag extends StatelessWidget {
  const _SmallTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: AppTypography.caption),
    );
  }
}
