import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_scaffold.dart';
import 'basic_info_step.dart';
import 'life_fact_step.dart';
import 'photo_steps.dart';
import 'setup_controller.dart';

/// B-2 ~ B-8 환자 정보 최초 입력.
///
/// 여러 단계를 한 경로에서 다룬다. 뒤로 가기는 이전 단계로 돌아가고, 첫 단계에서
/// 누르면 화면을 벗어난다.
class ProfileSetupScreen extends ConsumerWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return PopScope(
      canPop: state.stepIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.back();
      },
      child: Scaffold(
        appBar: AppTopBar(
          onBack: () {
            if (!controller.back()) context.pop();
          },
        ),
        body: Column(
          children: [
            _Progress(value: state.progress),
            Expanded(
              child: ScreenBody(
                scrollable: true,
                // 기본 정보는 이름, 성별, 생년월일, 현재 상태를 한 화면에서 받아
                // 스크롤이 길다. 버튼을 아래에 고정하면 그만큼 입력란이 보이는
                // 높이를 가져가므로 본문과 함께 흘려보낸다. 나머지 단계는 한
                // 화면에 들어가므로 고정한 채로 둔다.
                bottom: state.isBasicInfo
                    ? null
                    : _Actions(state: state, controller: controller),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: state.isBasicInfo
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StepBody(state: state, controller: controller),
                            const SizedBox(height: AppSpacing.xxl),
                            _Actions(state: state, controller: controller),
                            const SizedBox(height: AppSpacing.xxl),
                          ],
                        )
                      : _StepBody(state: state, controller: controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: value,
      minHeight: 4,
      backgroundColor: AppColors.surface,
      color: AppColors.ink,
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({required this.state, required this.controller});

  final SetupState state;
  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    if (state.isBasicInfo) {
      return BasicInfoStep(
        draft: state.draft,
        onChanged: controller.updateDraft,
      );
    }

    final step = state.lifeFactStep;
    if (step != null) {
      return LifeFactStepView(
        // 항목이 바뀌면 상태를 새로 잡는다.
        key: ValueKey(step.category),
        step: step,
        onCaptured: (text) => controller.recordFact(step.category, text),
        onCleared: () => controller.skipFact(step.category),
      );
    }

    if (state.isPhoto) {
      return PhotoUploadStep(
        hasPhoto: state.draft.hasPhoto,
        onPicked: () =>
            controller.updateDraft(state.draft.copyWith(hasPhoto: true)),
        onRemoved: () =>
            controller.updateDraft(state.draft.copyWith(hasPhoto: false)),
      );
    }

    return PhotoTagsStep(
      accepted: state.draft.acceptedTags,
      onToggle: (tag) {
        final next = Set<String>.from(state.draft.acceptedTags);
        next.contains(tag) ? next.remove(tag) : next.add(tag);
        controller.updateDraft(state.draft.copyWith(acceptedTags: next));
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.controller});

  final SetupState state;
  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    // 기본 정보는 모두 채워야 넘어간다.
    if (state.isBasicInfo) {
      return PrimaryButton(
        label: '다음',
        onPressed: state.draft.basicInfoFilled ? controller.next : null,
      );
    }

    // 생애 정보는 선택 사항이라 건너뛸 수 있다.
    final step = state.lifeFactStep;
    if (step != null) {
      final captured = state.draft.facts.containsKey(step.category);
      return captured
          ? PrimaryButton(label: '다음', onPressed: controller.next)
          : SecondaryButton(label: '건너뛰기', onPressed: controller.next);
    }

    if (state.isPhoto) {
      return state.draft.hasPhoto
          ? PrimaryButton(label: '다음', onPressed: controller.next)
          : SecondaryButton(label: '건너뛰기', onPressed: controller.next);
    }

    return PrimaryButton(
      label: '마치기',
      onPressed: () => context.go(AppRoutes.home),
    );
  }
}
