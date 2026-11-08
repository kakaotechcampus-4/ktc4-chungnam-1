"""변경 제안 생성. 면회가 끝난 뒤 녹음 전사, 소감, 고른 카드, 저장된 이야기로 두 가지를 제안함.

  이야기 후보(lifeFactProposals)  어르신이 직접 말한 지난날 중 아직 저장되지 않은 것
  주제 조정(topicProposals)       카드의 주제 하나에 more·less·exclude

입력은 #106 내부 API(8-3) 요청과 같음. DB를 읽거나 쓰지 않음. 보호자가 확인하기 전에는 반영되지 않음.
리포트와 합치는 법은 report_generation 설명 참고(common.visit_report.combine).

#106이 응답 전체를 거절하는 규칙은 코드로 미리 거름. 주제 조정은 카드당 하나, 반응이 notUsed거나 없는 카드에는 less·exclude 금지.
알려진 문제: 카드에 없는 이야기(예: 고인 이야기)를 싫어하신 경우 막을 단위가 없음.
proposals-5는 화자 정보에 따른 후보 일괄 제한을 제거하고, 불확실한 후보의 reason에 사용자 확인 필요를 적도록 지시함.
proposals-6은 보호자를 기본적으로 어르신의 자녀로 보고, 이야기 후보의 가족 호칭을 어르신 입장에서 쓰게 함(11/8 운영 시험에서 보호자가 '아버지'라 부른 어르신의 남편이 '아버지 정수 씨'로 적힘). reason에도 '화자' 같은 처리 과정의 말을 쓰지 않게 함.
버전 기록: proposals-2는 아픈 기억 제외 범위 수정(#201), proposals-3은 화자 미확인 지시(#199), proposals-4는 둘을 합친 것.
proposals-2와 proposals-4는 가장 가까운 카드의 주제를 막지 않고 아무것도 남기지 않음. 같은 시기나 장소의 다른 경험이 추천에서 빠지지 않게 하려는 것(#116).
이 범위는 프롬프트로만 지시함. reason은 자유 문장이라 코드가 어떤 경험을 가리키는지 판정하지 않음.
topic_proposals는 card_id가 필수(#84 스키마)라 카드 밖 제안을 저장할 자리도 없음.
"""

__all__ = ["generate_proposals", "PROMPT", "PROMPT_VERSION"]

from proposal_generation.generate import PROMPT, PROMPT_VERSION, generate_proposals
