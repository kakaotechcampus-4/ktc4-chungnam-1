"""변경 제안 생성. LLM 한 번으로 이야기 후보와 주제 조정을 받고 #106 규칙으로 거름."""

from __future__ import annotations

__all__ = ["generate_proposals", "PROMPT", "PROMPT_VERSION"]

from pathlib import Path
from typing import Callable

from pydantic import BaseModel, Field

from common.llm import ENDPOINTS, ChatConfig, chat_model, llm_down
from common.structured import invoke_structured
from common.visit_report import (
    Action,
    LifeFactProposalOut,
    ProposalResult,
    TopicProposalOut,
    VisitReportError,
    VisitReportRequest,
    card_refs,
    llm_payload,
)

PROMPT = Path(__file__).resolve().parent / "prompts/proposals.md"
PROMPT_VERSION = "proposals-1"   # 프롬프트나 거르는 규칙을 바꾸면 올림
_FACT_TITLE_MAX = 100            # #106 응답 검증과 같은 길이


def generate_proposals(request: VisitReportRequest, *, model: str, api_key: str, attempts: int = 1,
                       on_retry: Callable[[dict[str, str]], None] | None = None) -> ProposalResult:
    """model은 common/llm.py ENDPOINTS에 있는 이름. attempts·on_retry는 형식이 깨진 응답을 다시 받을 때 씀(시뮬레이션은 3).
    실패는 VisitReportError.
    """
    if model not in ENDPOINTS:
        raise VisitReportError("INVALID_REQUEST", f"모르는 model: {model}")
    refs = card_refs(request)
    try:
        out = invoke_structured(chat_model(ChatConfig(model=model, api_key=api_key)), _Proposals,
                                [("system", PROMPT.read_text()), ("user", llm_payload(request, refs, with_facts=True))],
                                "변경 제안", attempts, on_retry)
    except Exception as error:
        code = "LLM_UNAVAILABLE" if llm_down(error) else "GENERATION_FAILED"
        raise VisitReportError(code, f"{type(error).__name__}: {error}") from error
    return ProposalResult(model=model, prompt_version=PROMPT_VERSION, life_fact_proposals=_facts(out),
                          topic_proposals=_topics(out, request, refs))


# 변경 제안 LLM의 응답 형식. 모델이 읽는 스키마라 docstring을 두지 않음
class _LifeFact(BaseModel):
    title: str
    content: str
    reason: str


class _TopicProposal(BaseModel):
    card: str = Field(description="카드 번호표(c1 같은 값)")
    suggested_action: Action
    reason: str


class _Proposals(BaseModel):
    life_fact_proposals: list[_LifeFact]
    topic_proposals: list[_TopicProposal]


def _facts(out: _Proposals) -> list[LifeFactProposalOut]:
    """빈 칸이 있는 이야기 후보는 버리고, 제목은 #106 길이(100자)로 자름."""
    return [LifeFactProposalOut(title=f.title[:_FACT_TITLE_MAX], content=f.content, reason=f.reason)
            for f in out.life_fact_proposals if f.title.strip() and f.content.strip() and f.reason.strip()]


def _topics(out: _Proposals, request: VisitReportRequest, refs: dict[str, str]) -> list[TopicProposalOut]:
    """#106 규칙으로 거른 주제 조정. 없는 카드, 같은 카드의 두 번째 조정, 반응이 notUsed거나 없는 카드의 less·exclude는 버림."""
    by_ref = {refs[c.card_id]: c for c in request.cards}
    kept, seen = [], set()
    for t in out.topic_proposals:
        card = by_ref.get(t.card.strip())
        if card is None or card.card_id in seen:
            continue
        if t.suggested_action in ("less", "exclude") and card.reaction in ("notUsed", None):
            continue
        seen.add(card.card_id)
        kept.append(TopicProposalOut(card_id=card.card_id, suggested_action=t.suggested_action, reason=t.reason))
    return kept
