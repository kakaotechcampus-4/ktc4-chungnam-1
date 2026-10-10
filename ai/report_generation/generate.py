"""리포트 생성. LLM 한 번으로 제목, 본문, 카드별 요약을 받고 #106 규칙으로 거름."""

from __future__ import annotations

__all__ = ["generate_report", "PROMPT", "PROMPT_VERSION"]

from pathlib import Path
from typing import Callable

from pydantic import BaseModel, Field

from common.llm import ENDPOINTS, ChatConfig, chat_model, llm_down
from common.structured import invoke_structured
from common.visit_report import (
    CardSummaryOut,
    ReportResult,
    VisitReportError,
    VisitReportRequest,
    card_refs,
    llm_payload,
)

PROMPT = Path(__file__).resolve().parent / "prompts/report.md"
PROMPT_VERSION = "report-1"   # 프롬프트나 거르는 규칙을 바꾸면 올림
_TITLE_MAX = 200              # #106 응답 검증과 같은 길이


def generate_report(request: VisitReportRequest, *, model: str, api_key: str, attempts: int = 1,
                    on_retry: Callable[[dict[str, str]], None] | None = None) -> ReportResult:
    """model은 common/llm.py ENDPOINTS에 있는 이름. attempts·on_retry는 형식이 깨진 응답을 다시 받을 때 씀(시뮬레이션은 3).
    실패는 VisitReportError.
    """
    if model not in ENDPOINTS:
        raise VisitReportError("INVALID_REQUEST", f"모르는 model: {model}")
    refs = card_refs(request)
    try:
        out = invoke_structured(chat_model(ChatConfig(model=model, api_key=api_key)), _Report,
                                [("system", PROMPT.read_text()), ("user", llm_payload(request, refs, with_facts=False))],
                                "면회 리포트", attempts, on_retry)
    except Exception as error:
        code = "LLM_UNAVAILABLE" if llm_down(error) else "GENERATION_FAILED"
        raise VisitReportError(code, f"{type(error).__name__}: {error}") from error
    if not out.title.strip() or not out.body.strip():
        raise VisitReportError("GENERATION_FAILED", "제목이나 본문이 비어 있음")
    return ReportResult(model=model, prompt_version=PROMPT_VERSION, title=out.title[:_TITLE_MAX], body=out.body,
                        card_summaries=_summaries(out, request, refs))


# 리포트 LLM의 응답 형식. 모델이 읽는 스키마라 docstring을 두지 않음
class _Summary(BaseModel):
    card: str = Field(description="카드 번호표(c1 같은 값)")
    summary: str


class _Report(BaseModel):
    title: str
    body: str
    card_summaries: list[_Summary]


def _summaries(out: _Report, request: VisitReportRequest, refs: dict[str, str]) -> list[CardSummaryOut]:
    """#106 규칙으로 거른 카드 요약. 없는 카드, 반응이 notUsed거나 없는 카드, 같은 카드의 두 번째 요약, 빈 요약은 버림."""
    by_ref = {refs[c.card_id]: c for c in request.cards}
    kept, seen = [], set()
    for s in out.card_summaries:
        card = by_ref.get(s.card.strip())
        if card is None or card.card_id in seen or card.reaction not in ("positive", "neutral", "negative") or not s.summary.strip():
            continue
        seen.add(card.card_id)
        kept.append(CardSummaryOut(card_id=card.card_id, summary=s.summary))
    return kept
