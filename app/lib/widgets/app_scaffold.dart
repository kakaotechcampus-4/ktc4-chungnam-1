import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 뒤로가기와 제목만 있는 상단바다.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({this.title, this.onBack, this.actions, super.key});

  final String? title;

  /// `null` 이면 뒤로가기를 보여주지 않는다.
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.topBar);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: onBack == null
          ? null
          : IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 22),
              tooltip: '뒤로',
            ),
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
                ? SingleChildScrollView(child: padded)
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

/// 하단 탭의 종류. `마이페이지` 는 화면 이동이 아니라 팝업 메뉴를 연다.
enum AppTab { album, home, myPage }

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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: AppShadows.high,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNav,
          child: Row(
            children: [
              _Item(
                tab: AppTab.album,
                icon: Icons.menu_book_outlined,
                label: '일대기',
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
            ],
          ),
        ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? (selectedIcon ?? icon) : icon, size: 24, color: color),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
