import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';
import '../auth/consent_terms.dart';

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
    final account = ref.watch(accountProvider);

    return Scaffold(
      appBar: const AppTopBar(title: '프로필 설정'),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '프로필을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) => account.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorStateView(
            message: '계정 정보를 불러오지 못했어요.',
            onRetry: () => ref.invalidate(accountProvider),
          ),
          data: (account) => _Body(bundle: bundle, account: account),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.bundle, required this.account});

  final ProfileBundle bundle;
  final Account account;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// 지금 화면에서 동의한 항목의 키. `widget.account.consent` 에서 시작해
  /// 수정하기 전까지는 회원가입 때 고른 값과 같다.
  late final Set<String> _agreed;

  @override
  void initState() {
    super.initState();
    _agreed = {
      for (final entry in widget.account.consent.entries)
        if (entry.value.granted) entry.key,
    };
  }

  bool get _allAgreed => _agreed.length == consentTerms.length;

  void _toggleAll(bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.addAll(consentTerms.map((t) => t.key));
      } else {
        _agreed.clear();
      }
    });
  }

  void _toggle(String key, bool? value) {
    setState(() {
      if (value ?? false) {
        _agreed.add(key);
      } else {
        _agreed.remove(key);
      }
    });
  }

  void _showDetails(ConsentTerm term) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(term.label, style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.md),
              Text(term.statement, style: AppTypography.body),
              const SizedBox(height: AppSpacing.xl),
              for (final line in term.details) ...[
                Text(line, style: AppTypography.sub),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.bundle.profile;
    final bundle = widget.bundle;

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
          const SizedBox(height: AppSpacing.section),

          const Text('약관 동의', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.lg),

          for (final term in consentTerms) ...[
            _ConsentRow(
              term: term,
              checked: _agreed.contains(term.key),
              onChanged: (value) => _toggle(term.key, value),
              onDetails: () => _showDetails(term),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(),
          ),

          InkWell(
            onTap: () => _toggleAll(!_allAgreed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Checkbox(
                    value: _allAgreed,
                    onChanged: _toggleAll,
                    activeColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.line, width: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('전체 동의', style: AppTypography.bodyStrong),
                ],
              ),
            ),
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

/// 동의 항목 한 줄이다. `signup_screen.dart` 의 것과 같은 모양이다.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.term,
    required this.checked,
    required this.onChanged,
    required this.onDetails,
  });

  final ConsentTerm term;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDetails;

  static const _labelOffset = 12.0;
  static const _detailsHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
            activeColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line, width: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: _labelOffset),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: term.required ? '[필수] ' : '[선택] ',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: term.required
                              ? AppColors.danger
                              : AppColors.textSub,
                        ),
                      ),
                      TextSpan(text: term.label, style: AppTypography.body),
                    ],
                  ),
                ),

                if (term.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(term.note!, style: AppTypography.sub),
                ],

                const SizedBox(height: AppSpacing.sm),

                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textDisabled,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, _detailsHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '자세히 보기',
                        style: AppTypography.sub.copyWith(
                          color: AppColors.textDisabled,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.textDisabled,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
