import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 아픈 경험을 다루는 카드(`sensitive`)라는 작은 표시.
///
/// AI 는 일대기나 세부 정보에 담긴 이야기에서 온 아픈 경험(사별, 전쟁, 사고,
/// 병 같은)으로 카드를 만들 수 있고, 그때 카드에 표시를 단다(2026-11-09 PM
/// 결정). 고를지는 보호자가 정한다. 카드 고르기와 면회 중 카드 추가 화면이 같이
/// 쓴다. 색만으로 알리지 않도록 아이콘과 글을 함께 둔다.
class SensitiveCardBadge extends StatelessWidget {
  const SensitiveCardBadge({super.key});

  static const label = '조심스러운 이야기';

  @override
  Widget build(BuildContext context) {
    // 높이를 못 박지 않는다. 글자를 키우면 함께 커진다(`app/DESIGN.md` 접근성).
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: HomeColors.bubble,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: HomeColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.ink),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
