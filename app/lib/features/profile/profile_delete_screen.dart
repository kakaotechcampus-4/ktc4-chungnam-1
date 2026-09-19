import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_surfaces.dart';

/// 회원 탈퇴 확인. 프로필 설정의 `회원탈퇴`를 누르면 뜬다(피그마 설계 없음).
///
/// 탈퇴 후 보유 기간과 재가입 가능 여부는 `docs/legal/` 어디에도 정해진 내용이
/// 없어 여기서 임의로 짓지 않는다. 탈퇴 이유는 계약이나 법률 문서에 속하는 값이
/// 아니라 화면에서만 쓰는 설문이라 이 파일에 그대로 둔다.
class ProfileDeleteScreen extends ConsumerWidget {
  const ProfileDeleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorStateView(
          message: '프로필을 불러오지 못했어요.',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (bundle) => _Body(name: bundle.profile.name),
      ),
    );
  }
}

/// 탈퇴 이유 하나. 마지막 [other]만 직접 입력을 받는다.
class _Reason {
  const _Reason(this.label, {this.other = false});

  final String label;
  final bool other;
}

const _reasons = <_Reason>[
  _Reason('부모님의 인지 상태가 변화하여 더 이상 대화 카드가 필요 없어요 (퇴원, 증상 악화 등)'),
  _Reason('생성된 대화 카드가 부모님과 대화하는 데 실제 도움이 되지 않아요'),
  _Reason('면회를 자주 가지 않거나 정기적으로 쓰기 어려워요'),
  _Reason('앱 사용법이 어렵거나 원하는 기능을 찾기 불편해요'),
  _Reason('면회 중 녹음하거나 리포트를 확인하는 과정이 번거롭고 부담돼요'),
  _Reason('기타 (직접 입력)', other: true),
];

class _Body extends StatefulWidget {
  const _Body({required this.name});

  final String name;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _selected = <int>{};
  final _otherReason = TextEditingController();

  void _toggle(int i) {
    setState(() {
      if (_selected.contains(i)) {
        _selected.remove(i);
      } else {
        _selected.add(i);
      }
    });
  }

  @override
  void dispose() {
    _otherReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '탈퇴하기',
        onPressed: () => context.go(AppRoutes.login),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${widget.name} 어르신과 이별인가요?\n너무 아쉬워요.',
            style: AppTypography.screenTitle,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '계정을 삭제하면 대화 카드, 이야기 앨범 등 활동 정보와 개인 정보가 삭제돼요.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.section),

          Text(
            '${widget.name} 어르신이 탈퇴하려는 이유가 궁금해요.',
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: AppSpacing.lg),

          for (final (i, reason) in _reasons.indexed) ...[
            _ReasonRow(
              label: reason.label,
              selected: _selected.contains(i),
              onTap: () => _toggle(i),
            ),
            const SizedBox(height: AppSpacing.md),
            if (reason.other && _selected.contains(i)) ...[
              TextField(
                controller: _otherReason,
                maxLines: 3,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: '이유를 적어주세요',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textDisabled,
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.lg),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: const BorderSide(color: AppColors.ink, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SelectionMark(selected: selected, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTypography.body)),
        ],
      ),
    );
  }
}
