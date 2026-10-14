import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'life_story.dart';

/// 이야기 위에 놓는 기본 이미지다. 4:3 이다.
///
/// 이미지 파일은 `app/assets/images/` 에 하나씩 채워 넣는다. 아직 없는 번호는
/// 회색 면에 분류 아이콘과 `가족 3` 같은 이름을 그려 자리를 잡는다.
class LifeStoryImage extends StatelessWidget {
  const LifeStoryImage({
    required this.category,
    required this.number,
    super.key,
  });

  final LifeStoryCategory category;
  final int number;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.image),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.asset(
          lifeStoryImageAsset(category, number),
          fit: BoxFit.cover,
          // 이야기 제목이 바로 위에 있어 그림을 따로 읽어 주지 않는다.
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) =>
              _Placeholder(category: category, number: number),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.category, required this.number});

  final LifeStoryCategory category;
  final int number;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 40, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${category.label} $number',
              style: AppTypography.caption.copyWith(
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
