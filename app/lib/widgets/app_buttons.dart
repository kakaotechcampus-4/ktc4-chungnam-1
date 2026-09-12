import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 화면에서 가장 중요한 행동 하나에만 쓴다. 포레스트 면에 아이보리 글자다.
///
/// 비활성은 색을 바꾸지 않고 전체 투명도를 낮춘다. `app/DESIGN.md` 의
/// 눌림과 비활성 규칙을 따른다.
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
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          // 비활성도 같은 색을 쓰고 투명도로만 구분한다.
          disabledBackgroundColor: AppColors.accent,
          disabledForegroundColor: AppColors.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppRadius.control56),
            ),
          ),
          textStyle: AppTypography.button,
        ),
        child: Text(
          label,
          style: AppTypography.button.copyWith(color: AppColors.onAccent),
        ),
      ),
    );

    final sized = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;

    return enabled
        ? sized
        : Opacity(opacity: kDisabledOpacity, child: sized);
  }
}

/// 주 버튼보다 약한 행동에 쓴다. 배경 면에 포레스트 테두리다.
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
    final enabled = onPressed != null;
    final button = SizedBox(
      height: AppSizes.control,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          disabledForegroundColor: AppColors.ink,
          backgroundColor: AppColors.background,
          side: const BorderSide(color: AppColors.accent),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppRadius.control56),
            ),
          ),
        ),
        child: Text(label, style: AppTypography.button),
      ),
    );

    final sized = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;

    return enabled
        ? sized
        : Opacity(opacity: kDisabledOpacity, child: sized);
  }
}

/// 면 없이 글자만 있는 버튼이다. 밑줄로 누를 수 있음을 알린다.
class AppTextButton extends StatelessWidget {
  const AppTextButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          disabledForegroundColor: AppColors.ink,
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

    return enabled
        ? button
        : Opacity(opacity: kDisabledOpacity, child: button);
  }
}
