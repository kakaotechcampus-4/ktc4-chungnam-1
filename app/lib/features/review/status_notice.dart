import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';

/// 면회 기록을 보내거나 찾는 화면의 안내 한 장.
///
/// 음성 다시 보내기와 평가 이어서 하기가 같은 자리에 안내를 두도록 함께 쓴다.
///
/// 보내는 중과 결과가 같은 자리에 보이게, 안내는 버튼과 상관없이 화면의 같은
/// 높이에 두고 버튼은 아래에 따로 붙인다. 버튼 수가 달라도 안내가 움직이지
/// 않는다. 홈으로 버튼은 늘 두고, 다시 할 일이 있으면 그 버튼을 위에 둔다.
class StatusNotice extends StatelessWidget {
  const StatusNotice({
    required this.title,
    required this.body,
    this.onHome,
    this.icon,
    this.loading = false,
    this.danger = false,
    this.primaryLabel,
    this.onPrimary,
    super.key,
  });

  final String title;
  final String body;

  /// 보내는 중에는 버튼을 두지 않는다.
  final VoidCallback? onHome;
  final IconData? icon;

  /// 아이콘 자리에 로딩 표시를 둔다.
  final bool loading;

  /// 실패라 붉은 안내로 보여준다.
  final bool danger;

  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// 안내를 둘 높이. 가운데보다 조금 위다.
  static const _alignment = Alignment(0, -0.25);

  /// 아이콘과 로딩 표시가 같은 크기의 자리를 차지하게 한다.
  static const _markSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    final retry = primaryLabel != null && onPrimary != null;

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: Align(
                alignment: _alignment,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: _markSize,
                      child: loading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Icon(
                              icon ??
                                  (danger
                                      ? Icons.error_outline
                                      : Icons.info_outline),
                              size: _markSize,
                              color: color,
                            ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      title,
                      style: AppTypography.sectionTitle.copyWith(color: color),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      body,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSub,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onHome != null)
            Positioned(
              left: AppSpacing.screen,
              right: AppSpacing.screen,
              bottom: AppSpacing.xxl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (retry) ...[
                    PrimaryButton(label: primaryLabel!, onPressed: onPrimary),
                    const SizedBox(height: AppSpacing.md),
                    SecondaryButton(label: '홈으로', onPressed: onHome),
                  ] else
                    PrimaryButton(label: '홈으로', onPressed: onHome),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
