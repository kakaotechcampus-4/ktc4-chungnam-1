"""변경 제안 생성. 면회가 끝난 뒤 녹음 전사, 소감, 고른 카드, 저장된 이야기로 두 가지를 제안함.

  이야기 후보(lifeFactProposals)  어르신이 직접 말한 지난날 중 아직 저장되지 않은 것
  주제 조정(topicProposals)       카드의 주제 하나에 more·less·exclude

입력은 #106 내부 API(8-3) 요청과 같음. DB를 읽거나 쓰지 않음. 보호자가 확인하기 전에는 반영되지 않음.
리포트와 합치는 법은 report_generation 설명 참고(common.visit_report.combine).

#106이 응답 전체를 거절하는 규칙은 코드로 미리 거름. 주제 조정은 카드당 하나, 반응이 notUsed거나 없는 카드에는 less·exclude 금지.
알려진 문제: 카드에 없는 이야기(예: 고인 이야기)를 싫어하신 경우 막을 단위가 없음. 가장 가까운 카드의 주제를 막거나 아무것도 못 남김.
topic_proposals는 card_id가 필수(#84 스키마)라 카드 밖 제안을 저장할 자리도 없음.
"""

__all__ = ["generate_proposals", "PROMPT", "PROMPT_VERSION"]

from proposal_generation.generate import PROMPT, PROMPT_VERSION, generate_proposals
