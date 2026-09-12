import 'package:flutter/material.dart';

import 'tokens.dart';

/// 화면 전반의 기본값이다. 개별 위젯이 값을 다시 적지 않아도 되게 한다.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accentSurface,
    onSecondary: AppColors.ink,
    surface: AppColors.background,
    onSurface: AppColors.ink,
    surfaceContainer: AppColors.surface,
    error: AppColors.danger,
    onError: AppColors.onAccent,
    errorContainer: AppColors.dangerSurface,
    onErrorContainer: AppColors.danger,
    outline: AppColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    // 누름은 그림자나 크기 변화가 아니라 덮개로 알린다.
    splashFactory: InkRipple.splashFactory,
    splashColor: AppColors.pressOverlay,
    highlightColor: AppColors.pressOverlay,
    textTheme: const TextTheme(
      headlineMedium: AppTypography.screenTitle,
      titleMedium: AppTypography.sectionTitle,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.sub,
      bodySmall: AppTypography.caption,
      labelLarge: AppTypography.button,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: AppSizes.topBar,
      titleTextStyle: AppTypography.bodyStrong,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.line,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
    ),
    // 화면 전환은 안드로이드 기본 동작을 그대로 둔다. `app/DESIGN.md` 의 움직임 규칙 참고.
  );
}
