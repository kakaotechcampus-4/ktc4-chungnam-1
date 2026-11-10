import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 대화 카드 아래의 펼침 단서.
///
/// 접힌 카드는 `질문 보기` 와 아래 화살표, 펼친 카드는 맨 아래에 `질문 접기` 와
/// 위 화살표를 둔다. 누르는 일은 카드 본문(`SelectableCard.onTap`)이 받는다.
/// 예전의 13 회색 `눌러서 질문 보기` 는 눈에 잘 띄지 않아(2026-11-10 UX 점검
/// 19) 글자를 키우고 초록 화살표를 붙였다. 카드 고르기와 면회 중 카드 추가
/// 화면이 같이 쓴다.
///
/// 화면 낭독기는 카드의 펼침 여부와 두 번 탭 안내(`질문 펼치기`, `질문 접기`)로
/// 알므로 이 글자는 읽지 않는다.
class CardExpandCue extends StatelessWidget {
  const CardExpandCue({required this.expanded, super.key});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              expanded ? '질문 접기' : '질문 보기',
              style: AppTypography.sub.copyWith(
                color: HomeColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 24,
            color: HomeColors.accent,
          ),
        ],
      ),
    );
  }
}
