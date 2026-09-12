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
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.lg,
                AppSpacing.screen,
                AppSpacing.xxl,
              ),
              // 스크롤되는 내용이 버튼에 닿아 겹쳐 보이지 않도록 위쪽을 가린다.
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FFFBF7), AppColors.background],
                  stops: [0, 0.4],
                ),
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
        boxShadow: AppShadows.level3,
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
                selectedIcon: Icons.menu_book,
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
                selectedIcon: Icons.person,
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
    // 지금 탭은 포레스트에 채운 아이콘, 나머지는 흐린 글자에 선 아이콘이다.
    final color = selected ? AppColors.accent : AppColors.textDisabled;

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
