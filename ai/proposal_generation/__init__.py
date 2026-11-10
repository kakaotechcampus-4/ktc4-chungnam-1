"""변경 제안 생성. 면회가 끝난 뒤 녹음 전사, 소감, 고른 카드, 저장된 이야기로 두 가지를 제안함.

  이야기 후보(lifeFactProposals)  대화에 나온 경험, 생각, 계획 중 아직 저장되지 않은 것. 분류(storyCategory)와 아픈 기억 표시(sensitive)를 붙임
  주제 조정(topicProposals)       카드의 주제 하나에 more, less, exclude

입력은 #106 내부 API(8-3) 요청과 같음. DB를 읽거나 쓰지 않음. 보호자가 확인하기 전에는 반영되지 않음.
리포트와 합치는 법은 report_generation 설명 참고(common.visit_report.combine).

#106이 응답 전체를 거절하는 규칙은 코드로 미리 거름. 주제 조정은 카드당 하나, 반응이 notUsed거나 없는 카드에는 less·exclude 금지.
반응이 negative인 카드의 more는 #106이 거절하지 않지만 코드가 버림(proposals-9).
알려진 문제: 카드에 없는 이야기(예: 고인 이야기)를 싫어하신 경우 막을 단위가 없음.
proposals-5는 화자 정보에 따른 후보 일괄 제한을 제거하고, 불확실한 후보의 reason에 사용자 확인 필요를 적도록 지시함.
proposals-7은 title, content, reason에 '화자' 같은 처리 과정의 말을 쓰지 않게 함(11/8 운영 시험). proposals-6은 배포 전에 되돌렸고(#269) 쓰지 않음.
proposals-8은 이야기 후보와 주제 조정을 LLM 두 번으로 나눔(이야기 후보는 추론 강도 medium). 이야기 후보는 대화 전체에서 빠짐없이,
아픈 경험(sensitive)과 주인이 불확실한 경험도 내게 하고, 코드 상한은 30개. 주제 조정의 개수 제한을 없앰(PM 결정, 2026-11-09).
두 호출은 동시에 보내고 before_call을 넘기면 두 호출을 보내기 직전마다 부름(backend 마감 확인용).
proposals-9는 보호자가 아쉬웠다고 평가한(negative) 카드에 more를 내지 않게 하고, 코드도 그 more를 버림(11/10 E2E 문제 12).
proposals-10은 앞뒤 질문, 답과 정정을 함께 읽고 행동 주체, 친족 관계, 사건 순서를 나눠 확인하도록 지시함.
불확실한 내용은 reason에만 적지 않고 title과 content에서도 단정하지 않도록 함. 기본 추론 medium과 출력 상한 16000은 유지함.
이 변경은 프롬프트 지시이며 인물 관계의 정확성을 코드로 보장하지 않음.
버전 기록: proposals-2는 아픈 기억 제외 범위 수정(#201), proposals-3은 화자 미확인 지시(#199), proposals-4는 둘을 합친 것.
proposals-2와 proposals-4는 가장 가까운 카드의 주제를 막지 않고 아무것도 남기지 않음. 같은 시기나 장소의 다른 경험이 추천에서 빠지지 않게 하려는 것(#116).
이 범위는 프롬프트로만 지시함. reason은 자유 문장이라 코드가 어떤 경험을 가리키는지 판정하지 않음.
topic_proposals는 card_id가 필수(#84 스키마)라 카드 밖 제안을 저장할 자리도 없음.
"""

__all__ = ["generate_proposals", "PROMPT", "PROMPT_VERSION"]

from proposal_generation.generate import PROMPT, PROMPT_VERSION, generate_proposals
