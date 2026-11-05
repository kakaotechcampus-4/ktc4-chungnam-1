import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 뒤로가기와 제목만 있는 상단바다.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    this.title,
    this.onBack,
    this.showBack = true,
    this.actions,
    super.key,
  });

  final String? title;

  /// 지정하지 않으면 이전 화면으로 돌아간다.
  final VoidCallback? onBack;

  /// 돌아갈 곳이 없으면 [showBack] 이 `true` 라도 버튼을 그리지 않는다.
  final bool showBack;

  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.topBar);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final visible = showBack && (onBack != null || canPop);

    return AppBar(
      leading: visible
          ? IconButton(
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, size: 22),
              tooltip: '뒤로',
            )
          : null,
      title: title == null ? null : Text(title!),
      actions: actions,
    );
  }
}

/// 화면 좌우 여백을 한곳에서 지킨다.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    required this.child,
    this.scrollable = false,
    this.bottom,
    super.key,
  });

  final Widget child;

  /// 내용이 길어 넘칠 수 있으면 `true` 로 둔다.
  final bool scrollable;

  /// 화면 아래에 고정할 영역. 주 버튼을 여기에 둔다.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: child,
    );

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: scrollable
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(child: padded),
                      ),
                    ),
                  )
                : padded,
          ),
          if (bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                AppSpacing.xxl,
              ),
              child: bottom,
            ),
        ],
      ),
    );
  }
}

/// 하단 탭의 종류. 화면에 놓인 순서다.
enum AppTab { album, report, home, myPage, settings }

/// 하단 탭. 고른 탭 위에 검정 막대를 둔다.
///
/// 탭이 있는 화면들이 이 탭 하나를 함께 쓴다(router.dart 의 `_TabShell`). 고른
/// 탭이 바뀌면 막대가 그 자리로 미끄러진다. 움직임 줄이기가 켜져 있으면 바로
/// 옮긴다.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.current,
    required this.onSelected,
    super.key,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final index = current.index.toDouble();
    final still = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: AppShadows.high,
      ),
      child: SafeArea(
        top: false,
        // 기본 높이를 지키되 글자를 키우면 그만큼 높아진다. 글자를 자르지 않는다.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.bottomNav),
          child: IntrinsicHeight(
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Item(
                      tab: AppTab.album,
                      icon: Icons.menu_book_outlined,
                      label: '일대기',
                      current: current,
                      onSelected: onSelected,
                    ),
                    _Item(
                      tab: AppTab.report,
                      icon: Icons.description_outlined,
                      selectedIcon: Icons.description,
                      label: '리포트',
                      current: current,
                      onSelected: onSelected,
                    ),
                    _Item(
                      tab: AppTab.home,
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: '홈',
                      current: current,
                      onSelected: onSelected,
                    ),
                    _Item(
                      tab: AppTab.myPage,
                      icon: Icons.person_outline,
                      label: '마이페이지',
                      current: current,
                      onSelected: onSelected,
                    ),
                    _Item(
                      tab: AppTab.settings,
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                      label: '설정',
                      current: current,
                      onSelected: onSelected,
                    ),
                  ],
                ),
                // 고른 탭 위의 검정 막대. 누름은 아래 탭이 받는다. 높이는 탭이 정한다.
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SlidingIndicator(index: index, still: still),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 고른 탭 위로 미끄러지는 막대.
///
/// 고른 탭이 바뀐 프레임에는 새 화면도 함께 처음 그려진다. 무거운 화면(프로필
/// 설정, 설정 등)은 그 한 프레임이 길어 시간으로 움직이는 막대가 그사이 끝까지
/// 가 버려 순간이동처럼 보였다. 그래서 그 프레임을 다 그린 뒤 다음 프레임부터
/// 0.3초 동안 움직인다. 움직이는 도중 또 바뀌면 지금 자리에서 다시 출발한다.
class _SlidingIndicator extends StatefulWidget {
  const _SlidingIndicator({required this.index, required this.still});

  final double index;

  /// 움직임 줄이기. 켜져 있으면 바로 옮긴다.
  final bool still;

  @override
  State<_SlidingIndicator> createState() => _SlidingIndicatorState();
}

class _SlidingIndicatorState extends State<_SlidingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late double _from = widget.index;
  late double _to = widget.index;

  double get _position =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_slide.value);

  @override
  void didUpdateWidget(_SlidingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _from = _position;
    _to = widget.index;
    _slide.stop();
    if (widget.still) {
      _slide.value = 1;
      return;
    }
    _slide.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _slide.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, _) => Align(
        alignment: Alignment(
          -1 + 2 * _position / (AppTab.values.length - 1),
          -1,
        ),
        child: FractionallySizedBox(
          widthFactor: 1 / AppTab.values.length,
          child: const Align(
            alignment: Alignment.topCenter,
            child: _Indicator(),
          ),
        ),
      ),
    );
  }
}

/// 고른 탭 위의 짧고 둥근 검정 막대.
class _Indicator extends StatelessWidget {
  const _Indicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.tab,
    required this.icon,
    required this.label,
    required this.current,
    required this.onSelected,
    this.selectedIcon,
  });

  final AppTab tab;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final AppTab current;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = tab == current;
    final color = selected ? AppColors.ink : AppColors.textDisabled;

    return Expanded(
      child: InkWell(
        onTap: () => onSelected(tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? (selectedIcon ?? icon) : icon,
                size: 24,
                color: color,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
