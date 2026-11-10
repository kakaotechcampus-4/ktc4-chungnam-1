"""동기 LLM 호출의 일시 오류만 최대 한 번 재시도한다. SDK 재시도와 중첩하지 않는다."""
from __future__ import annotations

import random
import math
import logging
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import TypeVar

import openai

T = TypeVar("T")


@dataclass(frozen=True)
class RetryPolicy:
    enabled: bool = False
    delay_seconds: float = 1.0
    before_retry: Callable[[float], None] | None = None
    remaining: Callable[[], float] | None = None


_policy: ContextVar[RetryPolicy] = ContextVar("llm_retry_policy", default=RetryPolicy())


class RetryBlocked(RuntimeError):
    """업무 검사 실패를 모델 오류로 바꾸지 않고 호출자에게 돌려주기 위한 표시."""

    def __init__(self, original: Exception):
        self.original = original
        super().__init__("LLM retry blocked by job check")


@contextmanager
def retry_scope(**changes) -> Iterator[None]:
    """스레드별 정책. 안쪽 마감 설정이 바깥쪽 worker의 재시도 허용 설정을 보존한다."""
    token = _policy.set(replace(_policy.get(), **changes))
    try:
        yield
    finally:
        _policy.reset(token)


def retryable(error: BaseException) -> bool:
    # 래핑된 업무·권한 검사 예외는 재시도하지 않는다. 실제 SDK 오류만 분류한다.
    if isinstance(error, openai.APIConnectionError):
        return True
    if not isinstance(error, openai.APIStatusError):
        return False
    if error.status_code == 429:
        body = error.body if isinstance(error.body, dict) else {}
        detail = body.get("error", body)
        detail = detail if isinstance(detail, dict) else {}
        if detail.get("code") in {"insufficient_quota", "billing_hard_limit_reached",
                                  "organization_usage_limit_exceeded"}:
            return False
        if detail.get("type") == "insufficient_quota":
            return False
    return error.status_code in {408, 429} or 500 <= error.status_code < 600


def _retry_after(error: BaseException) -> float:
    if not isinstance(error, openai.APIStatusError):
        return 0.0
    headers = error.response.headers
    try:
        if "retry-after-ms" in headers:
            delay = float(headers["retry-after-ms"]) / 1000
            return max(0.0, delay) if math.isfinite(delay) else 0.0
        value = headers.get("retry-after", "0")
        try:
            delay = float(value)
            return max(0.0, delay) if math.isfinite(delay) else 0.0
        except ValueError:
            return max(0.0, (parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds())
    except (ValueError, TypeError, OverflowError):
        return 0.0


def invoke_with_retry(call: Callable[[float], T], *, timeout: float) -> T:
    """최초 호출과 재시도가 timeout 하나를 공유한다. 재시도 전 업무 검사를 다시 한다."""
    policy = _policy.get()
    end = time.monotonic() + timeout

    def left() -> float:
        remaining = end - time.monotonic()
        return min(remaining, policy.remaining()) if policy.remaining else remaining

    for attempt in range(2 if policy.enabled else 1):
        remaining = left()
        if remaining <= 0:
            raise TimeoutError("LLM call deadline exceeded")
        try:
            return call(remaining)
        except Exception as error:
            if attempt or not policy.enabled or not retryable(error):
                raise
            delay = max(_retry_after(error), random.uniform(0.5, 1.0) * policy.delay_seconds)
            if delay >= left():
                raise
            time.sleep(delay)
            if policy.before_retry is not None:
                try:
                    policy.before_retry(left())
                except Exception as blocked:
                    raise RetryBlocked(blocked) from None
            if left() <= 0:
                raise
            logging.getLogger("saerok.llm").info(
                "llm_retry attempt=1 error_type=%s", type(error).__name__,
            )
    raise AssertionError("unreachable")
