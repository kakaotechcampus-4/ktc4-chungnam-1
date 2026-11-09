import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import 'card_generation_controller.dart';

/// 홈과 카드 화면에서 같은 진행 상태와 선택을 보여준다.
class PhotoPreparationView extends ConsumerWidget {
  const PhotoPreparationView({required this.profileId, super.key});
  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(cardPhotoPreparationProvider(profileId));
    if (photos == null) return const SizedBox.shrink();
    final generation = ref.watch(cardGenerationProvider(profileId));
    final busy = generation.isLoading;
    final controller = ref.read(cardGenerationProvider(profileId).notifier);
    final message = !photos.needsChoice
        ? '사진을 분석하고 있어요. ${photos.completed}/${photos.total}장 완료\n'
              '분석이 끝나면 사진과 이야기를 함께 사용해 카드를 만들어요. 앱을 닫아도 계속 진행돼요.'
        : switch (photos.reason) {
            'analysisFailed' =>
              '사진 ${photos.failed}장을 분석하지 못했어요. '
                  '${photos.completed}/${photos.total}장 준비됐어요.',
            'consentRequired' =>
              'AI 사진 분석 동의가 꺼져 있어요. 설정에서 동의한 뒤 다시 시도하거나, 준비된 설명만 사용해 진행할 수 있어요.',
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
              onPressed: busy ? null : () => unawaited(controller.resume()),
              child: const Text('상태 다시 확인'),
            ),
        ],
        if (photos.needsChoice) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy
                ? null
                : () => unawaited(controller.resolvePhotos('retry')),
            child: const Text('사진 분석 다시 시도'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy
                ? null
                : () => unawaited(controller.resolvePhotos('continue')),
            child: Text(
              photos.completed == 0 ? '사진 없이 카드 만들기' : '완료된 사진으로 카드 만들기',
            ),
          ),
        ],
      ],
    );
  }
}
