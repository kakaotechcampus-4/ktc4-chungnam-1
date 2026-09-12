import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'app_buttons.dart';

/// 화면 가운데 로딩 표시와 한 줄 안내다.
///
/// 점 세 개가 차례로 밝아진다. `app/DESIGN.md` 상 뼈대만 깜빡이는 표시
/// (skeleton shimmer)를 쓰지 않는다.
class LoadingView extends StatelessWidget {
  const LoadingView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LoadingDots(),
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

/// 점 세 개가 차례로 밝아지는 기다림 표시다.
class LoadingDots extends StatefulWidget {
  const LoadingDots({this.size = 10, super.key});

  final double size;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  static const _count = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1080),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _count; i++) ...[
              if (i > 0) SizedBox(width: widget.size * 0.8),
              Opacity(
                opacity: _opacityFor(i),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 점마다 시작을 어긋나게 해서 차례로 밝아지게 한다.
  double _opacityFor(int index) {
    final shifted = (_controller.value - index / _count) % 1.0;
    // 앞쪽 절반에서 밝아졌다가 뒤쪽 절반에서 어두워진다.
    final wave = shifted < 0.5 ? shifted * 2 : (1 - shifted) * 2;
    return 0.3 + wave * 0.7;
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
            Icon(icon, size: 48, color: AppColors.textSub),
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
                // 색만으로 알리지 않는다. 테두리와 아이콘을 함께 쓴다.
                border: Border.all(color: AppColors.danger),
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

/// 기획이 보류된 화면의 자리를 채운다. 사용자에게 보여도 되는 안내다.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView.designPending({String? detail, super.key})
    : title = '화면 설계 중입니다',
      detail = detail ?? '준비가 되면 알려드릴게요.';

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
