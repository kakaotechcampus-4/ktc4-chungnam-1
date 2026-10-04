import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';

/// 소중한 분의 정보를 지우기 전에 한 번 더 묻는다.
///
/// 지우기를 누르면 `true`, 취소하거나 창을 닫으면 `false` 다. [name] 이 비어
/// 있으면 이름을 적기 전에 나간 `입력 중` 슬롯이다.
Future<bool> showRemoveProfileDialog(
  BuildContext context, {
  required String name,
  required bool pending,
}) async {
  final title = name.isEmpty ? '입력하던 정보를 지울까요?' : '$name 어르신의 정보를 지울까요?';
  final detail = pending
      ? '입력하던 내용이 지워지고 되돌릴 수 없어요.'
      // 서버에서 무엇까지 지울지는 BE 와 정하기 전이라 범위를 말하지 않는다.
      : '지운 정보는 되돌릴 수 없어요.';

  final removed = await showDialog<bool>(
    context: context,
    builder: (context) => _ChoiceDialog(
      title: title,
      detail: detail,
      primaryLabel: '지우기',
      secondaryLabel: '취소',
    ),
  );
  return removed ?? false;
}

/// 마지막 한 분을 지우려 할 때 띄운다.
///
/// 남은 분이 없으면 앱을 쓸 수 없으므로 지우지 않고 회원 탈퇴를 안내한다.
/// 회원 탈퇴로 가기를 누르면 `true` 다.
Future<bool> showLastProfileDialog(BuildContext context) async {
  final goWithdraw = await showDialog<bool>(
    context: context,
    builder: (context) => const _ChoiceDialog(
      title: '마지막 한 분은 지울 수 없어요',
      detail: '모든 정보를 지우려면\n회원 탈퇴를 해주세요.',
      primaryLabel: '회원 탈퇴하러 가기',
      secondaryLabel: '닫기',
    ),
  );
  return goWithdraw ?? false;
}

/// 제목, 설명과 두 버튼만 있는 창이다. 만남 끝내기 확인 창과 같은 모양이다.
class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog({
    required this.title,
    required this.detail,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String title;
  final String detail;
  final String primaryLabel;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTypography.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                style: AppTypography.sub,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: primaryLabel,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: secondaryLabel,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
