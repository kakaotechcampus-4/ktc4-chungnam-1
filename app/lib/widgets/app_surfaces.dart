import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 크림 면에 옅은 그림자와 테두리를 둔 카드다.
///
/// 밝은 면끼리는 대비가 1.1 안팎이라 면만으로는 배경과 구분되지 않는다.
/// 그래서 테두리를 함께 쓴다. 선택된 카드는 세이지 면에 굵은 포레스트
/// 테두리와 체크 표시로 알린다. `app/DESIGN.md` 의 상태 규칙을 따른다.
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
    final content = AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.line,
          width: selected ? 2 : 1,
        ),
        boxShadow: AppShadows.level1,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        splashColor: AppColors.pressOverlay,
        highlightColor: AppColors.pressOverlay,
        child: content,
      ),
    );
  }
}

/// 크림 면이다. 안내 문단처럼 본문과 구분해야 하는 영역에 쓴다.
///
/// 그림자 없이 테두리로만 배경과 나눈다.
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
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// 칩의 강조 단계.
enum ChipTone {
  /// 포레스트 면에 아이보리 글자.
  strong,

  /// 배경 면에 포레스트 테두리와 포레스트 글자.
  normal,

  /// 배경 면에 라인 테두리와 흐린 글자.
  weak,
}

class AppChip extends StatelessWidget {
  const AppChip(this.label, {this.tone = ChipTone.normal, super.key});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      ChipTone.strong => (
        AppColors.accent,
        AppColors.onAccent,
        AppColors.accent,
      ),
      ChipTone.normal => (
        AppColors.background,
        AppColors.ink,
        AppColors.accent,
      ),
      ChipTone.weak => (
        AppColors.background,
        AppColors.textDisabled,
        AppColors.line,
      ),
    };

    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
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

/// 선택 여부를 나타내는 원형 표시다.
///
/// 선택되면 포레스트 원 안의 체크가 된다. 색만으로 알리지 않기 위해
/// 체크 표시를 함께 쓴다.
class SelectionMark extends StatelessWidget {
  const SelectionMark({required this.selected, this.size = 28, super.key});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.line,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.62, color: AppColors.onAccent)
          : null,
    );
  }
}
