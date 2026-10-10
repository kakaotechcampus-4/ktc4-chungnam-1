"""모델 호출 설정. 엘리스 ML API(OpenAI 호환)를 LangChain ChatOpenAI로 부름.

모델 이름과 키는 부르는 쪽이 넘김. backend는 자기 설정에서, 시뮬레이션·평가는 환경 변수에서 읽음(simulation/llm_env.py).
주소는 모델 이름으로 ENDPOINTS에서 찾음.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import openai
from langchain_core.language_models import BaseChatModel
from langchain_openai import ChatOpenAI

# 엘리스 ML API는 모델마다 주소가 다름. 쓸 수 있는 모델과 주소를 여기 적어 둠
# 새 모델은 엘리스 콘솔에서 주소를 확인해 추가
ENDPOINTS = {
    "gpt-5.6-luna": "https://mlapi.run/286e9158-d32e-436d-a23d-36b43fc8e68a/v1",
}


@dataclass(frozen=True)
class ChatConfig:
    model: str             # ENDPOINTS에 있는 이름
    api_key: str = field(repr=False)  # repr에서 빼서 로그에 안 찍힘
    effort: str | None = "low"  # 추론 강도. None이면 넘기지 않음
    timeout: int = 300
    # 엘리스 프록시가 스트리밍이 아닌 응답의 출력을 2,000토큰으로 막음(시뮬레이션에서 400 응답으로 확인, 2026-10-05).
    # 후보 제출이 잘려서 스트리밍으로 받고 상한을 늘림
    max_tokens: int = 8000

    @property
    def name(self) -> str:
        return f"{self.model}:{self.effort}" if self.effort else self.model


def chat_model(config: ChatConfig) -> BaseChatModel:
    if config.model not in ENDPOINTS:
        raise ValueError(f"모르는 모델: {config.model}. common/llm.py의 ENDPOINTS에 주소를 추가해야 함")
    if not config.api_key:
        raise RuntimeError("ML API 키가 필요합니다")
    return ChatOpenAI(
        model=config.model, base_url=ENDPOINTS[config.model], api_key=config.api_key, timeout=config.timeout,
        # SDK 자동 재시도(기본 2회) 끔. PM이 "재시도 횟수는 검증 결과 없이 선택하거나 고정하지 않는다"고 정해 둠(local_ai/CLAUDE.md)
        # 일시 오류만 1회 자동 재시도하는 안은 PM 검토안(#108). 정해지면 backend에서 다시 시도함
        max_retries=0,
        max_tokens=config.max_tokens, streaming=True, stream_usage=True,
        # store=false라 대화가 업체 쪽에 남지 않음. 대신 추론 내용을 암호화해 받아 다음 요청에 돌려줌
        use_responses_api=True, store=False, include=["reasoning.encrypted_content"], output_version="responses/v1",
        reasoning={"effort": config.effort} if config.effort else None,
    )


def llm_down(error: BaseException) -> bool:
    """예외가 엘리스 API 쪽 문제(연결 실패, 시간 초과, 호출 한도, 서버 오류)인지.
    LangChain이 원래 예외를 감싸서 던지므로 __cause__·__context__를 거슬러 올라가며 봄.
    """
    seen = error
    while seen is not None:
        if isinstance(seen, _LLM_DOWN):
            return True
        seen = seen.__cause__ or seen.__context__
    return False


_LLM_DOWN = (openai.APIConnectionError, openai.APITimeoutError, openai.RateLimitError, openai.InternalServerError)
