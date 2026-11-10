import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/sleeping_mascot.dart';
import '../home/home_talk.dart';
import 'comfort_messages.dart';
import 'review_controller.dart';

/// 보호자 평가를 제출한 뒤 홈으로 가기 전에 보는 위로 화면이다.
///
/// 피그마 설계는 없고 PM 초안을 따른다. 서버와 AI 를 부르지 않는다.
/// Q1 대화 만족도는 소감 화면이 남긴 [reviewControllerProvider] 에서 읽는다.
class ComfortScreen extends ConsumerWidget {
  const ComfortScreen({super.key});

  /// 잠든 마스코트 한 변. 기준 화면 폭 412 에서 글보다 먼저 눈에 들어오되
  /// 첫 화면에 문단까지 함께 보이는 크기다.
  static const _mascotSize = 184.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final satisfaction = ref.watch(
      reviewControllerProvider.select((draft) => draft.satisfaction),
    );
    final message = comfortMessageFor(satisfaction);

    // 홈 말풍선이 이야기 대신 면회 뒤 인사를 하게 한다.
    void goHome() {
      ref.read(homeAfterVisitProvider.notifier).returning();
      context.go(AppRoutes.home);
    }

    // 평가는 이미 제출했다. 뒤로 가기로 소감 화면에 돌아가면 두 번 제출하게
    // 되므로 홈으로 보낸다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goHome();
      },
      child: Scaffold(
        backgroundColor: HomeColors.background,
        appBar: const AppTopBar(
          backgroundColor: HomeColors.background,
          showBack: false,
        ),
        body: ScreenBody(
          scrollable: true,
          bottom: PrimaryButton(
            color: HomeColors.accent,
            loadingColor: HomeColors.accentLoading,
            label: '홈으로',
            onPressed: goHome,
          ),
          child: Column(
            children: [
              const Spacer(),
              const SleepingMascot(size: _mascotSize),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                '제출 완료!',
                style: AppTypography.screenTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                comfortFixedMessage,
                style: AppTypography.body.copyWith(color: AppColors.textSub),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.section),
                AppSurfaceBox(
                  color: HomeColors.bubble,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.title, style: AppTypography.sectionTitle),
                      const SizedBox(height: AppSpacing.sm),
                      Text(message.body, style: AppTypography.body),
                    ],
                  ),
                ),
              ],
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
