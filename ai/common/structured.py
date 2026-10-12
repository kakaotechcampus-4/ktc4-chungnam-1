"""정해진 형식(Pydantic 모델)으로 답을 받는 LLM 호출.

모델 출력이 가끔 중간에 망가져 형식을 못 읽음. attempts만큼 다시 시도.
"""

from __future__ import annotations

from typing import Callable, TypeVar

from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


def invoke_structured(model: BaseChatModel, schema: type[T], messages: list[tuple[str, str]], label: str,
                      attempts: int = 1, on_retry: Callable[[dict[str, str]], None] | None = None) -> T:
    runnable = model.with_structured_output(schema, method="json_schema", strict=True)
    for attempt in range(1, attempts + 1):
        try:
            return runnable.invoke(messages)
        except Exception as error:  # 파싱 실패, 출력 잘림 등
            if on_retry:
                on_retry({"role": label, "attempt": str(attempt), "error": f"{type(error).__name__}: {str(error)[:200]}"})
            if attempt == attempts:
                raise
    raise AssertionError("attempts는 1 이상이어야 한다")
