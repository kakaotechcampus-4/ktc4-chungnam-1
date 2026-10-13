import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 이름표와 입력 상자를 함께 두는 입력 항목이다.
///
/// 필수 항목은 이름표 옆에 붉은 별표를 붙인다. `app/DESIGN.md` 상 붉은색을
/// 쓰는 몇 안 되는 자리다.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.hintText,
    this.required = false,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
    this.onChanged,
    this.suffix,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool required;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  /// 글자 수 상한. 주면 입력칸 아래에 쓴 글자 수와 상한을 함께 보여주고 넘는
  /// 입력은 받지 않는다.
  final int? maxLength;

  /// 여러 줄을 받을 때 처음 보이는 줄 수.
  final int? minLines;

  /// `null` 이면 내용만큼 늘어난다. 기본은 한 줄이다.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, required: required),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          maxLength: maxLength,
          minLines: minLines,
          maxLines: maxLines,
          style: AppTypography.body,
          decoration: InputDecoration(
            counterStyle: AppTypography.caption,
            hintText: hintText,
            hintStyle: AppTypography.body.copyWith(
              color: AppColors.textDisabled,
            ),
            errorText: errorText,
            errorStyle: AppTypography.caption.copyWith(color: AppColors.danger),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            border: _border(AppColors.line),
            enabledBorder: _border(AppColors.line),
            focusedBorder: _border(AppColors.ink, width: 2),
            errorBorder: _border(AppColors.danger),
            focusedErrorBorder: _border(AppColors.danger, width: 2),
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// 입력 항목의 이름표다. 선택 상자나 직접 만든 입력에도 같은 모양으로 쓴다.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {this.required = false, super.key});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTypography.bodyStrong),
        if (required) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            '*',
            style: AppTypography.bodyStrong.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}
