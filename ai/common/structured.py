"""정해진 형식(Pydantic 모델)으로 답을 받는 LLM 호출.

모델 출력이 가끔 중간에 망가져 형식을 못 읽음. attempts만큼 다시 시도.
"""

from __future__ import annotations

from typing import Any, Callable, TypeVar

from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


def invoke_structured(model: BaseChatModel, schema: type[T], messages: list[tuple[str, str]], label: str,
                      attempts: int = 1, on_retry: Callable[[dict[str, str]], None] | None = None, *,
                      usage: dict[str, int] | None = None) -> T:
    """usage를 넘기면 응답마다 토큰 수(usage_metadata)를 더해 넣음. 형식이 깨져 다시 받은 응답의 토큰도 셈.
    모델이 토큰 수를 주지 않으면 usage를 그대로 둠. 대화 내용은 넣지 않음.
    """
    runnable = model.with_structured_output(schema, method="json_schema", strict=True, include_raw=usage is not None)
    for attempt in range(1, attempts + 1):
        try:
            out = runnable.invoke(messages)
            if usage is None:
                return out
            add_usage(usage, out.get("raw"))
            # include_raw면 형식 오류를 던지지 않고 담아 줌. 다시 던져서 include_raw가 없을 때와 같게 다시 시도함
            if out.get("parsing_error") is not None:
                raise out["parsing_error"]
            if out.get("parsed") is None:
                raise ValueError("정해진 형식의 답이 없음")
            return out["parsed"]
        except Exception as error:  # 파싱 실패, 출력 잘림 등
            if on_retry:
                on_retry({"role": label, "attempt": str(attempt), "error": f"{type(error).__name__}: {str(error)[:200]}"})
            if attempt == attempts:
                raise
    raise AssertionError("attempts는 1 이상이어야 한다")


def add_usage(usage: dict[str, int], message: Any) -> None:
    """LangChain 응답 메시지의 usage_metadata를 usage에 더함. 키는 calls, input_tokens, output_tokens,
    total_tokens, reasoning_tokens(모델이 줄 때만). 토큰 수가 없는 응답은 calls만 셈.
    """
    usage["calls"] = usage.get("calls", 0) + 1
    meta = getattr(message, "usage_metadata", None) or {}
    for key in ("input_tokens", "output_tokens", "total_tokens"):
        if isinstance(meta.get(key), int):
            usage[key] = usage.get(key, 0) + meta[key]
    reasoning = (meta.get("output_token_details") or {}).get("reasoning")
    if isinstance(reasoning, int):
        usage["reasoning_tokens"] = usage.get("reasoning_tokens", 0) + reasoning
    if _cut_off(message):
        usage["incomplete_responses"] = usage.get("incomplete_responses", 0) + 1


def _cut_off(message: Any) -> bool:
    """출력 한도에 걸려 답이 끊겼는지. Responses API의 status와 incomplete_details만 봄(내용은 보지 않음)."""
    meta = getattr(message, "response_metadata", None) or {}
    details = meta.get("incomplete_details") or {}
    reason = details.get("reason") if isinstance(details, dict) else None
    return meta.get("status") == "incomplete" or reason == "max_output_tokens"         or meta.get("finish_reason") == "length"
