import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api_client.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import 'upload_retry_controller.dart';

/// 보내지 못한 면회 녹음 다시 보내기.
///
/// 피그마 설계는 없다. 앱을 다시 켠 뒤 홈의 `음성 다시 보내기` 배너가
/// `/visit/upload?session=<회차 ID>` 로 연다. 들어오자마자 보내고, 결과에 따라
/// 안내와 버튼만 바꾼다.
class UploadRetryScreen extends ConsumerWidget {
  const UploadRetryScreen({required this.sessionId, super.key});

  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = uploadRetryProvider(sessionId);
    final result = ref.watch(provider);
    void goHome() => context.go(AppRoutes.home);

    return Scaffold(
      appBar: const AppTopBar(),
      // 다시 보내기를 누르면 지난 실패 대신 보내는 중을 다시 보여준다.
      body: result.when(
        skipLoadingOnRefresh: false,
        loading: () => const _Notice(
          loading: true,
          title: '녹음을 보내고 있어요',
          body: '잠시만 기다려 주세요',
        ),
        error: (error, _) => _Notice(
          danger: true,
          title: '녹음을 보내지 못했어요.',
          body: error is ApiNetworkFailure
              ? '인터넷 연결을 확인한 뒤 다시 보내주세요.'
              : '잠시 후 다시 보내주세요.',
          primaryLabel: '다시 보내기',
          onPrimary: ref.read(provider.notifier).retry,
          onHome: goHome,
        ),
        data: (outcome) => switch (outcome) {
          UploadRetryOutcome.sent => _Notice(
            icon: Icons.check_circle_outline,
            title: '녹음을 보냈어요',
            body: '리포트가 만들어지면 홈에서 알려드릴게요',
            onHome: goHome,
          ),
          UploadRetryOutcome.notFound => _Notice(
            title: '이 휴대전화에서 녹음 파일을 찾을 수 없어요.',
            body: '녹음한 휴대전화에서 다시 보내주세요.',
            onHome: goHome,
          ),
          UploadRetryOutcome.alreadyClosed => _Notice(
            title: '이미 처리된 면회예요.',
            body: '결과는 홈에서 확인해 주세요.',
            onHome: goHome,
          ),
        },
      ),
    );
  }
}

/// 결과 안내 한 장.
///
/// 보내는 중과 결과가 같은 자리에 보이게, 안내는 버튼과 상관없이 화면의 같은
/// 높이에 두고 버튼은 아래에 따로 붙인다. 버튼 수가 달라도 안내가 움직이지
/// 않는다. 홈으로 버튼은 늘 두고, 다시 할 일이 있으면 그 버튼을 위에 둔다.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.onHome,
    this.icon,
    this.loading = false,
    this.danger = false,
    this.primaryLabel,
    this.onPrimary,
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
