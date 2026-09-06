import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_states.dart';
import 'visit_cards_sheet.dart';
import 'visit_controller.dart';

/// E-1, E-2 녹음 안내와 녹음 중.
///
/// 둘은 별도 화면이 아니라 이 화면의 상태다.
///
/// **녹음 기능 자체는 만들지 않는다.** 녹음 라이브러리와 음성 형식, STT 연결은
/// AI 영역이 소유한다(`app/CLAUDE.md`). 여기서는 화면과 시간 표시만 다룬다.
class RecordScreen extends ConsumerWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitControllerProvider);

    return Scaffold(
      appBar: const AppTopBar(),
      body: visit.when(
        loading: () => const LoadingView(),
        error: (error, _) =>
            const ErrorStateView(message: '면회를 시작하지 못했어요.\n잠시 후 다시 시도해주세요.'),
        // 한 번 시작하면 잠시 멈춰도 녹음 화면에 머문다.
        data: (state) =>
            state.started ? _Recording(state: state) : const _Intro(),
      ),
    );
  }
}

/// E-1. 녹음 전 안내와 피보호자 동의 확인.
///
/// 계약의 `VisitSession.consent.careRecipientConfirmation` 과
/// `docs/legal/consent-draft.md` 의 필수 동의 항목에 해당한다. 가입 화면이 아니라
/// 면회를 시작하는 이 자리에서 받는다.
class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(visitControllerProvider).value;
    final controller = ref.read(visitControllerProvider.notifier);
    final confirmed = state?.careRecipientConfirmed ?? false;

    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '네, 좋아요',
        onPressed: confirmed ? controller.startRecording : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          const Text(
            '소중한 대화 내용을\n놓치지 않게 녹음할게요',
            style: AppTypography.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '녹음은 리포트를 만드는 데만 쓰고\n분석이 끝나면 바로 지워요.',
            style: AppTypography.sub,
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 2),

          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 56, color: AppColors.ink),
            ),
          ),

          const Spacer(flex: 2),

          // 필수 확인이다. 체크해야 녹음을 시작할 수 있다.
          InkWell(
            onTap: () => controller.confirmCareRecipient(confirmed: !confirmed),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: confirmed,
                    onChanged: (value) => controller.confirmCareRecipient(
                      confirmed: value ?? false,
                    ),
                    activeColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.line, width: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '[필수] ',
                            style: AppTypography.body.copyWith(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(
                            text: '어르신께 녹음한다는 것을 알려드렸고 동의를 확인했어요.',
                            style: AppTypography.body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// E-2. 녹음 중.
class _Recording extends ConsumerWidget {
  const _Recording({required this.state});

  final VisitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(visitControllerProvider.notifier);

    return ScreenBody(
      scrollable: true,
      bottom: PrimaryButton(
        label: '대화 카드 살펴보기',
        onPressed: () => showVisitCardsSheet(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Text(
            state.recording ? '녹음 중이에요' : '잠시 멈췄어요',
            style: AppTypography.screenTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            state.elapsedLabel,
            style: AppTypography.screenTitle.copyWith(
              fontSize: 34,
              color: AppColors.textSub,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 2),

          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: state.recording ? AppColors.ink : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                state.recording ? Icons.mic : Icons.pause,
                size: 56,
                color: state.recording
                    ? AppColors.background
                    : AppColors.textSub,
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                icon: state.recording ? Icons.pause : Icons.play_arrow,
                label: state.recording ? '잠시 멈춤' : '이어서 녹음',
                onTap: state.recording
                    ? controller.pauseRecording
                    : controller.startRecording,
              ),
              const SizedBox(width: AppSpacing.xxl),
              _ControlButton(
                icon: Icons.stop,
                label: '만남 끝내기',
                onTap: () {
                  controller.stopRecording();
                  context.push(AppRoutes.visitReview);
                },
              ),
            ],
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line, width: 2),
            ),
            child: Icon(icon, size: 30, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: AppTypography.sub),
      ],
    );
  }
}
