import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../widgets/app_buttons.dart';
import '../profile_setup/photo_picker.dart';
import 'local_photos.dart';

/// 어르신 사진과 이야기 사진을 바꾸는 시트를 열고 고른 대로 한다.
///
/// 앨범에서 한 장을 고르거나, 이미 넣은 사진이 있으면 [resetLabel] 로 기본
/// 그림으로 되돌린다. 사진은 이 기기에만 두며 시트가 그렇게 알린다
/// ([LocalPhotos]).
Future<void> changeLocalPhoto(
  BuildContext context,
  WidgetRef ref, {
  required String profileId,
  required String slot,
  required String resetLabel,
}) async {
  final hasPhoto =
      ref.read(localPhotoPathProvider(localPhotoKey(profileId, slot))) != null;
  final action = await showModalBottomSheet<_Action>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    isScrollControlled: true,
    barrierLabel: '닫기',
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (context) =>
        _LocalPhotoSheet(hasPhoto: hasPhoto, resetLabel: resetLabel),
  );
  if (action == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final index = ref.read(localPhotoIndexProvider.notifier);
  void tell(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  switch (action) {
    case _Action.pick:
      final picked = await ref.read(photoPickerProvider).pick(limit: 1);
      if (picked.isEmpty) return;
      try {
        await index.keep(profileId, slot, picked.first.path);
      } on Exception {
        tell('사진을 넣지 못했어요. 다시 시도해주세요.');
        return;
      }
      tell('사진을 바꿨어요.');
    case _Action.reset:
      try {
        await index.remove(profileId, slot);
      } on Exception {
        tell('사진을 빼지 못했어요. 다시 시도해주세요.');
        return;
      }
      tell('기본 그림으로 되돌렸어요.');
  }
}

enum _Action { pick, reset }

class _LocalPhotoSheet extends StatelessWidget {
  const _LocalPhotoSheet({required this.hasPhoto, required this.resetLabel});

  final bool hasPhoto;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          0,
          AppSpacing.screen,
          AppSpacing.section,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text('사진 바꾸기', style: AppTypography.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.sm),
            // 서버 사진(갤러리)과 다르게 다루므로 고르기 전에 알린다.
            const Text(
              '사진은 이 휴대폰에만 저장돼요.\n서버에 올리거나 대화 카드에 쓰지 않아요.',
              style: AppTypography.sub,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              color: HomeColors.accent,
              loadingColor: HomeColors.accentLoading,
              label: '앨범에서 고르기',
              onPressed: () => Navigator.of(context).pop(_Action.pick),
            ),
            if (hasPhoto) ...[
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                borderColor: HomeColors.outline,
                label: resetLabel,
                onPressed: () => Navigator.of(context).pop(_Action.reset),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
