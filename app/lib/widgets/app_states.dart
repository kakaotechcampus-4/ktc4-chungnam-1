import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'app_buttons.dart';

/// 화면 가운데 로딩 표시와 한 줄 안내다.
/// `app/DESIGN.md` 상 앱에서 움직이는 것은 이것뿐이다.
class LoadingView extends StatelessWidget {
  const LoadingView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              message!,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// 보여줄 것이 없을 때의 화면이다. 다음에 할 일을 함께 안내한다.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.xl),
            Text(
              message,
              style: AppTypography.body.copyWith(color: AppColors.textSub),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 오류 안내다. 붉은색을 쓰는 몇 안 되는 자리다.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    required this.message,
    this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.dangerSurface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 24,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      message,
                      style: AppTypography.body.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: '다시 시도',
                onPressed: onRetry,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 아직 화면이 없는 자리를 채운다.
///
/// 두 가지를 구분한다. 기획이 보류된 화면은 [PlaceholderView.designPending],
/// 이번 작업에서 아직 만들지 않은 화면은 [PlaceholderView.upcoming] 이다.
/// 뒤엣것은 구현이 끝나면 사라진다.
class PlaceholderView extends StatelessWidget {
  /// 기획이 보류된 화면. 사용자에게 보여도 되는 안내다.
  const PlaceholderView.designPending({String? detail, super.key})
    : title = '화면 설계 중입니다',
      detail = detail ?? '준비가 되면 알려드릴게요.';

  /// 아직 구현하지 않은 화면. 개발 중에만 보인다.
  const PlaceholderView.upcoming({
    required int unit,
    required String screen,
    super.key,
  }) : title = screen,
       detail = '단위 $unit 에서 구현합니다';

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              detail,
              style: AppTypography.sub,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
