"""카드 생성 전체 제한 시간(time_limit).

모델을 부르기 직전마다 남은 시간을 확인하고, 남은 시간을 그 호출의 timeout으로 줌. 스트리밍으로 받는 중에도 토큰마다 확인해서
넘으면 끊음. 제한 시간이 지나면 진행 중인 호출을 끊고 다음 호출도 시작하지 않음(PM 리뷰, #110 2026-10-12).
"""

from __future__ import annotations

import dataclasses
import math
import time
from typing import Any

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.language_models import BaseChatModel

from common.llm import ChatConfig, chat_model


class TimeLimitExceeded(RuntimeError):
    """제한 시간을 넘긴 실패. generate_cards가 LLM_UNAVAILABLE로 바꿈."""
    pass


class Deadline:
    """카드 생성 한 번의 마감 시각. 단계마다 남은 시간을 timeout으로 준 모델을 만들어 줌."""

    def __init__(self, config: ChatConfig, seconds: float) -> None:
        self.config = config
        self.seconds = seconds
        self.end = time.monotonic() + seconds

    def model(self, stage: str) -> BaseChatModel:
        """남은 시간을 timeout으로 준 모델. 남은 시간이 없으면 TimeLimitExceeded. stage는 실패 문장에 남길 단계 이름."""
        left = self.check(stage)
        model = chat_model(dataclasses.replace(self.config, timeout=min(self.config.timeout, math.ceil(left))))
        model.callbacks = [_StopStreaming(self, stage)]
        return model

    def check(self, stage: str) -> float:
        """남은 시간(초). 남은 시간이 없으면 TimeLimitExceeded."""
        left = self.end - time.monotonic()
        if left <= 0:
            raise TimeLimitExceeded(f"{stage} 중 {self.seconds:.0f}초를 넘김")
        return left


def timed_out(error: BaseException) -> bool:
    """예외가 제한 시간 초과에서 나왔는지. LangChain이 콜백 예외를 감싸서 던질 수 있어 __cause__·__context__를 거슬러 올라감."""
    seen: BaseException | None = error
    while seen is not None:
        if isinstance(seen, TimeLimitExceeded):
            return True
        seen = seen.__cause__ or seen.__context__
    return False


class _StopStreaming(BaseCallbackHandler):
    """스트리밍 토큰이 올 때마다 남은 시간을 확인함."""

    raise_error = True  # 콜백 예외를 삼키지 않고 호출을 끊음

    def __init__(self, deadline: Deadline, stage: str) -> None:
        self.deadline = deadline
        self.stage = stage

    def on_llm_new_token(self, token: str, **kwargs: Any) -> None:
        """토큰이 올 때마다 불림. 시간을 넘겼으면 TimeLimitExceeded."""
        self.deadline.check(self.stage)
