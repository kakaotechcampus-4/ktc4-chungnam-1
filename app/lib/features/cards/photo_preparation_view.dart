import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import 'card_generation_controller.dart';

/// 홈과 카드 화면에서 같은 진행 상태와 선택을 보여준다.
///
/// AI 사진 분석 동의가 꺼져 있으면(`consentRequired`) 서버가 `사진 분석 다시
/// 시도` 를 늘 거절하므로(`PHOTO_ANALYSIS_CONSENT_REQUIRED`) 그 버튼을 두지
/// 않는다. 대신 준비된 설명으로 바로 만드는 주 버튼과 계정 약관 동의 화면을
/// 여는 보조 버튼을 둔다(2026-11-10 UX 점검 18번). 주 버튼을 바로 만들기로 둔
/// 것은 카드를 받으러 온 화면이고, 선택 동의를 끈 보호자에게 동의를 앞세우지
/// 않으려는 것이다.
class PhotoPreparationView extends ConsumerWidget {
  const PhotoPreparationView({
    required this.profileId,
    this.recheck,
    this.resolve,
    super.key,
  });
  final String profileId;

  /// 이미 접수한 작업의 상태를 다시 읽는다. 홈은 이어 물은 결과를 버튼 아래와
  /// 알림창으로 알리려고 자기 것을 넘긴다. 없으면 생성 흐름의 `resume` 이다.
  final Future<void> Function()? recheck;

  /// 사진 준비 선택(`retry`, `continue`)을 보낸다. 홈은 기다려 만든 결과를 홈
  /// 버튼을 누른 때와 같이 알리려고 자기 것을 넘긴다. 없으면 생성 흐름의
  /// `resolvePhotos` 다. 카드 화면은 결과를 그 화면에서 보여준다.
  final Future<void> Function(String action)? resolve;

  Future<void> _recheck(WidgetRef ref) async {
    final recheck = this.recheck;
    if (recheck != null) return recheck();
    await ref.read(cardGenerationProvider(profileId).notifier).resume();
  }

  Future<void> _resolve(WidgetRef ref, String action) async {
    final resolve = this.resolve;
    if (resolve != null) return resolve(action);
    await ref
        .read(cardGenerationProvider(profileId).notifier)
        .resolvePhotos(action);
  }

  /// 계정 약관 동의 화면을 열고, 돌아오면 사진 준비 상태를 다시 읽는다. 동의를
  /// 켰으면 서버가 사진 분석을 이어 가 선택이 바뀐다.
  Future<void> _openConsents(BuildContext context, WidgetRef ref) async {
    await context.push(AppRoutes.settingsConsents);
    if (!context.mounted) return;
    await _recheck(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(cardPhotoPreparationProvider(profileId));
    if (photos == null) return const SizedBox.shrink();
    final generation = ref.watch(cardGenerationProvider(profileId));
    final busy = generation.isLoading;
    final message = !photos.needsChoice
        ? '사진을 분석하고 있어요. ${photos.completed}/${photos.total}장 완료\n'
              '분석이 끝나면 사진과 이야기를 함께 사용해 카드를 만들어요. 앱을 닫아도 계속 진행돼요.'
        : switch (photos.reason) {
            'analysisFailed' =>
              '사진 ${photos.failed}장을 분석하지 못했어요. '
                  '${photos.completed}/${photos.total}장 준비됐어요.',
            'consentRequired' =>
              photos.completed == 0
                  ? 'AI 사진 분석 동의가 꺼져 있어요. 사진 없이 카드를 만들거나, 설정에서 동의를 켤 수 있어요.'
                  : 'AI 사진 분석 동의가 꺼져 있어요. 준비된 설명으로 카드를 만들거나, 설정에서 동의를 켤 수 있어요.',
            _ =>
              '사진 분석이 예상보다 오래 걸려요. ${photos.completed}/${photos.total}장 준비됐어요.',
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(message, style: AppTypography.sub),
        ),
        if (generation.hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            photos.needsChoice
                ? '선택을 처리하지 못했어요. 연결과 동의 상태를 확인한 뒤 다시 눌러주세요.'
                : '사진 준비 상태를 확인하지 못했어요. 인터넷 연결을 확인한 뒤 다시 확인해 주세요.',
            style: AppTypography.sub.copyWith(color: AppColors.danger),
          ),
          if (!photos.needsChoice)
            TextButton(
              onPressed: busy ? null : () => unawaited(_recheck(ref)),
              child: const Text('상태 다시 확인'),
            ),
        ],
        if (photos.needsChoice && photos.reason == 'consentRequired') ...[
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: photos.completed == 0 ? '사진 없이 카드 만들기' : '준비된 설명으로 카드 만들기',
            color: HomeColors.accent,
            loadingColor: HomeColors.accentLoading,
            onPressed: busy ? null : () => unawaited(_resolve(ref, 'continue')),
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: '설정에서 동의 켜기',
            borderColor: HomeColors.outline,
            onPressed: busy
                ? null
                : () => unawaited(_openConsents(context, ref)),
          ),
        ] else if (photos.needsChoice) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? null : () => unawaited(_resolve(ref, 'retry')),
            child: const Text('사진 분석 다시 시도'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? null : () => unawaited(_resolve(ref, 'continue')),
            child: Text(
              photos.completed == 0 ? '사진 없이 카드 만들기' : '완료된 사진으로 카드 만들기',
            ),
          ),
        ],
      ],
    );
  }
}
