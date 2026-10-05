import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// B-7 사진 올리기. 선택 항목이며 한 장만 받는다.
///
/// 실제 갤러리 연결은 아직 붙이지 않았다. 목 데이터의 사진으로 자리를 채운다.
class PhotoUploadStep extends StatelessWidget {
  const PhotoUploadStep({
    required this.hasPhoto,
    required this.onPicked,
    required this.onRemoved,
    super.key,
  });

  final bool hasPhoto;
  final VoidCallback onPicked;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Text(
          '어르신과 관련된 사진을\n올려주세요',
          style: AppTypography.screenTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          '사진에서 대화 주제를 추천해드려요. 넣지 않으셔도 괜찮아요.',
          style: AppTypography.sub,
          textAlign: TextAlign.center,
        ),
        const Spacer(flex: 2),

        if (hasPhoto)
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.image),
                child: Image.asset('assets/images/family.webp'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onRemoved,
                style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
                child: const Text('다른 사진 고르기', style: AppTypography.sub),
              ),
            ],
          )
        else
          InkWell(
            onTap: onPicked,
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.image),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 44,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text('사진 추가하기', style: AppTypography.sub),
                ],
              ),
            ),
          ),

        const Spacer(flex: 3),
      ],
    );
  }
}
