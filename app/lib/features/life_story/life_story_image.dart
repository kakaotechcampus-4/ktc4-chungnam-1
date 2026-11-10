import 'dart:io';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'life_story.dart';

/// 이야기 위에 놓는 그림이다. 4:3 이다.
///
/// [photoPath] 가 있으면 보호자가 이 기기에 넣은 사진을 그린다(`LocalPhotos`).
/// 없거나 읽지 못하면 기본 이미지다. 기본 이미지 파일은 `app/assets/images/` 에
/// 하나씩 채워 넣는다. 아직 없는 번호는 회색 면에 분류 아이콘과 `가족 3` 같은
/// 이름을 그려 자리를 잡는다.
class LifeStoryImage extends StatelessWidget {
  const LifeStoryImage({
    required this.category,
    required this.number,
    this.photoPath,
    super.key,
  });

  final LifeStoryCategory category;
  final int number;
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      lifeStoryImageAsset(category, number),
      fit: BoxFit.cover,
      // 이야기 제목이 바로 위에 있어 그림을 따로 읽어 주지 않는다.
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) =>
          _Placeholder(category: category, number: number),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.image),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: switch (photoPath) {
          null => fallback,
          final path => LayoutBuilder(
            builder: (context, box) => Image.file(
              File(path),
              fit: BoxFit.cover,
              // 앨범 사진은 크다. 칸 폭에 맞춰 줄여 풀어 기억을 아낀다. 가로로
              // 긴 사진도 높이가 모자라 흐려지지 않게 폭을 넉넉히 둔다.
              cacheWidth: box.maxWidth.isFinite
                  ? (box.maxWidth *
                            1.5 *
                            MediaQuery.devicePixelRatioOf(context))
                        .round()
                  : null,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          ),
        },
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
    // 연초록 면이다. 그 위 비활성 회색은 3.9:1 이라 글자는 초록(5.7:1)으로 쓴다.
    return ColoredBox(
      color: HomeColors.bubble,
      // 입력 화면의 작은 그림 고르기 칸에서도 넘치지 않게 줄인다.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 40, color: HomeColors.accentLoading),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${category.label} $number',
              style: AppTypography.caption.copyWith(color: HomeColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
