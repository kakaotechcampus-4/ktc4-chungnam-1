import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 화면에서 가장 중요한 행동 하나에만 쓴다. 검정 면에 흰 글자다.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  });

  final String label;

  /// `null` 이면 비활성 상태로 보여준다.
  final VoidCallback? onPressed;

  /// 가로 폭을 가득 채운다.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = SizedBox(
      height: AppSizes.control,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.line,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
          textStyle: AppTypography.button,
        ),
        child: Text(
          label,
          style: AppTypography.button.copyWith(
            color: enabled ? AppColors.background : AppColors.textDisabled,
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 주 버튼보다 약한 행동에 쓴다. 흰 면에 테두리다.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: AppSizes.control,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          disabledForegroundColor: AppColors.textDisabled,
          backgroundColor: AppColors.background,
          side: const BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
        child: Text(label, style: AppTypography.button),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 면 없이 글자만 있는 버튼이다. 밑줄로 누를 수 있음을 알린다.
class AppTextButton extends StatelessWidget {
  const AppTextButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
        ),
        child: Text(
          label,
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
