import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 흰 면에 옅은 그림자를 둔 카드다.
///
/// 선택할 수 있는 카드는 [selected] 로 상태를 나타낸다. 색이 아니라 테두리 굵기로
/// 구분한다. `app/DESIGN.md` 의 상태 규칙을 따른다.
///
/// 눌러서 펼치는 카드는 [expanded] 를 넘긴다. 화면 낭독기가 버튼과 펼침 여부를
/// 함께 읽는다. 테두리의 [selected] 는 화면 낭독기에 알리지 않는다. 고르는
/// 동작은 [SelectionToggle] 이 따로 알린다.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.expanded,
    this.selected = false,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 펼치는 카드면 지금 펼쳐졌는지. `null` 이면 펼치는 카드가 아니다.
  final bool? expanded;

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

    return Semantics(
      button: true,
      expanded: expanded,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: content,
        ),
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
  const AppChip(
    this.label, {
    this.tone = ChipTone.normal,
    this.style,
    super.key,
  });

  final String label;
  final ChipTone tone;

  /// 글자 묶음을 바꿔 끼울 때 쓴다. 색과 굵기는 [tone] 이 정하므로 크기만
  /// 넘기면 된다. 지정하지 않으면 캡션이다.
  final TextStyle? style;

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      // 높이를 못 박으면 글자를 키웠을 때 잘린다(`app/DESIGN.md` 접근성).
      // 캡션에서는 이 최소 높이가 이겨서 예전과 같은 30 이 된다.
      constraints: const BoxConstraints(minHeight: 30),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: (style ?? AppTypography.caption).copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 선택 여부를 나타내는 원형 표시다. 선택되면 검정 원 안의 체크가 된다.
///
/// 고르지 않은 빈 원의 테두리는 [AppColors.textDisabled] 다. 흰 배경과의 대비가
/// 4.5:1 이라 눌러서 고를 수 있는 자리로 보인다. 예전의 [AppColors.line] 은
/// 1.3:1 이라 흰 카드 위에서 잘 보이지 않았다(접근성 보고서 14쪽). 카드 테두리
/// 같은 다른 선은 그대로 둔다.
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
        // 빈 원은 3:1 하한을 지키는 가장 연한 회색과 가는 선으로 둔다. 너무
        // 진해 카드 내용보다 눈에 띄었다.
        border: Border.all(
          color: selected ? AppColors.ink : AppColors.selectionRing,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.62, color: AppColors.background)
          : null,
    );
  }
}

/// 오른쪽에 고르기 표시가 있는 카드다.
///
/// 카드 본문을 누르면 [onTap] 으로 펼쳐지고, 카드 오른쪽 3분의 1을 누르면
/// [onToggleSelected] 로 고른다. 원만 누르기 어렵다는 의견이 있어 원 둘레가
/// 아니라 오른쪽 3분의 1 전체 높이를 고르는 자리로 둔다. 원의 자리와 글자 폭은
/// 예전(여백 24, 사이 12, 자리 48)과 같다.
///
/// 화면 낭독기가 두 동작을 따로 읽도록 고르는 자리를 독립된 항목으로 두고,
/// [selectLabel] 에 무엇을 고르는지 적어 선택 여부와 함께 알린다.
class SelectableCard extends StatelessWidget {
  const SelectableCard({
    required this.child,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.selectLabel,
    required this.onToggleSelected,
    super.key,
  });

  final Widget child;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  /// 화면 낭독기가 읽는 이름. 예: `옛 동네 이야기 카드 고르기`.
  final String selectLabel;
  final VoidCallback onToggleSelected;

  /// 글자가 원과 겹치지 않게 비워 두는 오른쪽 여백. 예전 24 + 48 + 12.
  static const _contentRight = 84.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Stack 은 자식에게 폭을 강제하지 않아, 그대로 두면 카드가 글자 폭만큼
        // 줄고 원이 카드 밖에 그려진다. 받은 폭을 다 쓰게 한다.
        SizedBox(
          width: double.infinity,
          child: AppCard(
            selected: selected,
            onTap: onTap,
            expanded: expanded,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              _contentRight,
              AppSpacing.xl,
            ),
            child: child,
          ),
        ),
        // 카드 전체 높이에 걸치므로 원은 카드 높이의 가운데에 오고, 펼치면
        // 펼친 카드의 가운데로 함께 옮겨 간다.
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: SelectionToggle(
                label: selectLabel,
                selected: selected,
                onTap: onToggleSelected,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [SelectableCard] 오른쪽 3분의 1의 고르는 자리다.
///
/// 받은 자리 전체를 누를 수 있고, 원은 오른쪽 끝에서 [SelectableCard] 가 정한
/// 자리에 그린다. 화면 낭독기는 [label] 과 선택 여부를 읽는다.
class SelectionToggle extends StatelessWidget {
  const SelectionToggle({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// 화면 낭독기가 읽는 이름. 예: `옛 동네 이야기 카드 고르기`.
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      checked: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouch,
            minHeight: AppSizes.minTouch,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              // 원(28)의 가운데가 카드 오른쪽 끝에서 48 에 온다. 예전 여백 24와
              // 자리 48의 절반을 더한 자리다.
              padding: const EdgeInsets.only(right: 48 - 14),
              child: SelectionMark(selected: selected),
            ),
          ),
        ),
      ),
    );
  }
}
