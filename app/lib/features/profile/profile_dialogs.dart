import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
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

/// 등록한 어르신이 없을 때 어르신이 있어야 하는 기능을 누르면 띄운다.
///
/// 대화 카드, 면회, 리포트와 알림은 어르신을 등록하고 고른 뒤에 쓴다.
/// `등록하러 가기` 를 누르면 함께하는 소중한 분 화면으로 간다.
Future<void> showProfileRequiredDialog(BuildContext context) async {
  final goRegister = await showDialog<bool>(
    context: context,
    builder: (context) => const _ChoiceDialog(
      title: '어르신을 먼저 등록해주세요',
      detail: '함께하는 소중한 분을 등록한 뒤\n이용할 수 있어요.',
      primaryLabel: '등록하러 가기',
      secondaryLabel: '닫기',
    ),
  );
  if ((goRegister ?? false) && context.mounted) {
    context.push(AppRoutes.profileSwitch);
  }
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
