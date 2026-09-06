import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 흰 면에 옅은 그림자를 둔 카드다.
///
/// 선택할 수 있는 카드는 [selected] 로 상태를 나타낸다. 색이 아니라 테두리 굵기로
/// 구분한다. `app/DESIGN.md` 의 상태 규칙을 따른다.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: selected ? AppColors.ink : AppColors.line,
          width: selected ? 2 : 1,
        ),
        boxShadow: AppShadows.low,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: content,
      ),
    );
  }
}

/// 옅은 회색 면이다. 안내 문단처럼 본문과 구분해야 하는 영역에 쓴다.
class AppSurfaceBox extends StatelessWidget {
  const AppSurfaceBox({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}

/// 칩의 강조 단계. 색이 하나뿐이라 형태로 구분한다.
enum ChipTone {
  /// 검정 면에 흰 글자.
  strong,

  /// 검정 테두리에 검정 글자.
  normal,

  /// 연한 테두리에 흐린 글자.
  weak,
}

class AppChip extends StatelessWidget {
  const AppChip(this.label, {this.tone = ChipTone.normal, super.key});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      ChipTone.strong => (AppColors.ink, AppColors.background, AppColors.ink),
      ChipTone.normal => (AppColors.background, AppColors.ink, AppColors.ink),
      ChipTone.weak => (
        AppColors.background,
        AppColors.textDisabled,
        AppColors.line,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 선택 여부를 나타내는 원형 표시다. 선택되면 검정 원 안의 체크가 된다.
class SelectionMark extends StatelessWidget {
  const SelectionMark({required this.selected, this.size = 28, super.key});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? AppColors.ink : AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.ink : AppColors.line,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.62, color: AppColors.background)
          : null,
    );
  }
}
