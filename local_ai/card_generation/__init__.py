"""카드 생성. 다음 면회에 쓸 대화 카드 12장(1~9번 고르는 카드, 10~12번 보충용)을 만듦.

backend 카드 생성 worker가 DB에서 모은 context를 넘기면 카드 12장과 새로 만들 주제를 돌려줌.
DB를 읽거나 쓰지 않음. 카드·주제 저장과 UUID 발급은 backend가 함.

    from card_generation import CardGenerationError, GenerationRequest, generate_cards

    result = generate_cards(GenerationRequest.model_validate(payload), api_key=settings.ml_api_key)

backend는 이 패키지에서 위 이름만 씀. 밑줄로 시작하는 폴더와 이름은 패키지 안에서만 씀(PEP 8).

흐름(generate.py)
  ① 조사      _steps/research   에이전트가 읽기 도구로 프로필, 이야기, 사진, 지난 주제를 보고 후보 16~24개를 냄
  ② 연결 판정  _steps/match.py   후보마다 속할 주제를 LLM 한 번으로 다시 정함. 추천하지 않기 주제에 걸린 후보는 뺌
              주제가 12개보다 적으면 무엇이 묶이고 빠졌는지 알려 주고 ①로 다시(최대 2번)
  ③ 선정      _steps/select.py  새 이야기 5장을 먼저 잡고, 남은 자리는 기존 주제를 점수 softmax 확률로 추첨
  ④ 문안      _steps/write.py   고른 12장에 설명, 첫 질문, 꼬리 질문 3개를 쓰고 금지 표현을 검사
LLM은 ①에서 여러 번, ②·④에서 한 번씩 부름. 한 번에 1~2분 걸리고 240초를 넘기면 실패.

폴더
  contract.py         backend와 주고받는 요청·결과·실패 형식(#99와 같은 camelCase)
  generate.py         진입점 generate_cards와 ①~④ 잇기
  _steps/research/    agent(조사 에이전트), candidates(후보 형식과 제출 검증), tools(도구 6개와 결과 형식),
                      store(context 조회, 번호표, 선호 점수)
  _steps/match.py, select.py, write.py
  _versions/          판(promptVersion)마다 프롬프트와 정해 둔 값. backend가 요청의 promptVersion으로 판을 고름

주요 결정
  - 모델 주소는 common/llm.py의 ENDPOINTS에서 모델 이름으로 찾음. 목록에 없는 모델이나 판은 INVALID_CONTEXT
  - 모델에게는 UUID 대신 번호표(t1, f3, p2)를 보여 주고, 결과를 돌려주기 전에 UUID로 되돌림
  - 선호 점수는 보호자가 승인한 결정(more·less·exclude)만 감쇠해 더함. 카드 반응과 미사용은 넣지 않음(PM 결정, #44)
  - 추천하지 않기를 고른 주제만 확실히 뺌. 나머지는 점수가 낮아도 추첨에 들어감
  - 실패는 CardGenerationError. code를 backend가 card_sets.error_code에 그대로 남김(contract.py)
"""

__all__ = ["generate_cards", "GenerationRequest", "GenerationResult", "CardGenerationError"]

from card_generation.contract import CardGenerationError, GenerationRequest, GenerationResult
from card_generation.generate import generate_cards
