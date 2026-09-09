import 'package:flutter/material.dart';

import 'tokens.dart';

/// 화면 전반의 기본값이다. 개별 위젯이 값을 다시 적지 않아도 되게 한다.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.ink,
    onPrimary: AppColors.background,
    surface: AppColors.background,
    onSurface: AppColors.ink,
    error: AppColors.danger,
    onError: AppColors.background,
    outline: AppColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
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
      color: AppColors.ink,
      linearTrackColor: AppColors.surface,
    ),
    // 화면 전환은 안드로이드 기본 동작을 그대로 둔다. `app/DESIGN.md` 의 움직임 규칙 참고.
  );
}
