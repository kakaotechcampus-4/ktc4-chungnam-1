"""시뮬레이션 작업대에 LLM 요청과 도구 호출을 실시간 이벤트로 넘기는 훅.

set_sink()로 받을 함수를 넣으면 LangChain 전역 콜백이 켜져 단계 이름, 걸린 시간, 토큰, 입력과 출력 일부가 넘어감.
생성 기능 코드는 이 모듈을 모름. 지금 단계는 stage()로 정함.
"""

from __future__ import annotations

import contextvars
import json
import time
from contextlib import contextmanager
from typing import Any, Callable
from uuid import UUID

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.tracers.context import register_configure_hook

_sink: Callable[[dict[str, Any]], None] | None = None
_stage: contextvars.ContextVar[str] = contextvars.ContextVar("stage", default="")
PREVIEW = 4000


def set_sink(sink: Callable[[dict[str, Any]], None] | None) -> None:
    global _sink
    _sink = sink
    _handler.set(HANDLER if sink else None)


def emit(kind: str, **data: Any) -> None:
    if _sink is not None:
        _sink({"kind": kind, "stage": _stage.get(), "ts": time.time(), **data})


@contextmanager
def stage(name: str):
    token = _stage.set(name)
    emit("stage_start", name=name)
    started = time.monotonic()
    try:
        yield
    finally:
        emit("stage_end", name=name, seconds=round(time.monotonic() - started, 1))
        _stage.reset(token)


def _cut(value: Any) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, default=str)
    return text if len(text) <= PREVIEW else text[:PREVIEW] + f" …(+{len(text) - PREVIEW}자)"


def _message_text(m: Any) -> str:
    content = getattr(m, "content", m)
    if isinstance(content, list):
        content = " ".join(c.get("text", "") if isinstance(c, dict) else str(c) for c in content)
    return f"[{getattr(m, 'type', '?')}] {content}"


class _Handler(BaseCallbackHandler):
    def __init__(self) -> None:
        self.started: dict[UUID, float] = {}

    def on_chat_model_start(self, serialized, messages, *, run_id, **kwargs):
        if _sink is None:
            return
        self.started[run_id] = time.monotonic()
        flat = [m for batch in messages for m in batch]
        emit("llm_start", id=str(run_id), messages=len(flat),
             system=_cut(_message_text(flat[0])) if flat else "",
             last=_cut(_message_text(flat[-1])) if flat else "")

    def on_llm_end(self, response, *, run_id, **kwargs):
        if _sink is None:
            return
        seconds = round(time.monotonic() - self.started.pop(run_id, time.monotonic()), 1)
        gen = response.generations[0][0] if response.generations and response.generations[0] else None
        msg = getattr(gen, "message", None)
        usage = getattr(msg, "usage_metadata", None) or {}
        tool_calls = [{"name": t["name"], "args": t["args"]} for t in getattr(msg, "tool_calls", []) or []]
        text = _message_text(msg) if msg is not None else (gen.text if gen else "")
        emit("llm_end", id=str(run_id), seconds=seconds, input_tokens=usage.get("input_tokens", 0),
             output_tokens=usage.get("output_tokens", 0), output=_cut(text), tool_calls=_cut(tool_calls) if tool_calls else "")

    def on_llm_error(self, error, *, run_id, **kwargs):
        if _sink is None:
            return
        self.started.pop(run_id, None)
        emit("llm_error", id=str(run_id), error=_cut(f"{type(error).__name__}: {error}"))

    def on_tool_start(self, serialized, input_str, *, run_id, **kwargs):
        if _sink is not None:
            self.started[run_id] = time.monotonic()
            emit("tool_start", id=str(run_id), name=(serialized or {}).get("name", ""), input=_cut(input_str))

    def on_tool_end(self, output, *, run_id, **kwargs):
        if _sink is not None:
            seconds = round(time.monotonic() - self.started.pop(run_id, time.monotonic()), 2)
            emit("tool_end", id=str(run_id), seconds=seconds, output=_cut(getattr(output, "content", output)))


HANDLER = _Handler()
_handler: contextvars.ContextVar[_Handler | None] = contextvars.ContextVar("simulation_trace", default=None)
register_configure_hook(_handler, inheritable=True)
