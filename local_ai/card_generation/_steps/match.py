"""연결 판정(②). 후보마다 속할 주제를 LLM 한 번으로 정함.

에이전트가 적은 연결은 넣지 않고 다시 판정함. 기존 주제가 없는 후보끼리도 같은 이야기면 new_key 하나로 묶음.
excluded 주제에 속한 후보, 판정이 빠졌거나 없는 주제를 가리킨 후보는 뺌.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel, Field

from card_generation._steps.research.candidates import CardCandidate, evidence_refs
from card_generation._steps.research.store import ProfileStore
from card_generation._steps.research.tools import TopicView
from card_generation._versions.base import Version
from common.structured import invoke_structured


@dataclass
class Matched:
    """판정을 거친 후보. topic_id와 new_key 중 하나만 있음."""
    no: int                      # 에이전트가 낸 순서(1부터)
    candidate: CardCandidate
    topic_id: str | None
    new_key: str | None
    reason: str
    agent_topic_id: str | None   # 에이전트가 적었던 연결(비교용)


@dataclass
class MatchOutcome:
    """판정 결과. kept는 남은 후보, dropped는 빠진 후보와 이유, new_topics는 새 주제의 제목과 설명."""
    kept: list[Matched] = field(default_factory=list)
    dropped: list[dict[str, Any]] = field(default_factory=list)
    new_topics: dict[str, _NewTopic] = field(default_factory=dict)


# 판정 LLM이 후보 하나마다 내는 답. 모델이 읽는 스키마라 docstring을 두지 않음
class _Assignment(BaseModel):
    candidate_id: str
    topic_id: str | None = Field(description="같은 이야기인 기존 주제의 topic_id. 없으면 null")
    new_key: str | None = Field(description="기존 주제가 없을 때 같은 이야기 후보끼리 공유하는 키(n1, n2, ...)")
    reason: str


# 판정 LLM이 새 주제마다 짓는 제목과 설명
class _NewTopic(BaseModel):
    new_key: str
    title: str
    description: str


class _MatchResult(BaseModel):
    """후보마다 속하는 이야기를 정한 결과."""
    assignments: list[_Assignment]
    new_topics: list[_NewTopic]


def run_match(model: BaseChatModel, store: ProfileStore, candidates: list[CardCandidate], prompt: str) -> MatchOutcome:
    """판정 입력을 만들어 판정하고 거름."""
    topics = store.all_topics()
    payload = _match_input(store, topics, candidates)
    result = judge(model, payload, prompt)
    aliases = store.aliases()  # 판정도 번호표로 답함. UUID로 되돌린 뒤 거름
    result = result.model_copy(update={"assignments": [
        a.model_copy(update={"topic_id": aliases.uuid(a.topic_id)}) for a in result.assignments]})
    outcome = _apply_match(candidates, topics, result)
    return outcome


def judge(model: BaseChatModel, payload: dict[str, Any], prompt: str) -> _MatchResult:
    """판정 LLM 호출 한 번."""
    return invoke_structured(model, _MatchResult, [("system", prompt),
                                                  ("user", json.dumps(payload, ensure_ascii=False))], "연결 판정")


def match_prompt(v: Version, match_path: Path | None = None, same_story_path: Path | None = None) -> str:
    """판의 판정 프롬프트. 평가에서는 다른 판의 경로를 넣어 비교함."""
    if not match_path and not same_story_path:
        return v.match_prompt()
    match_text = (match_path or v.prompts / "match.md").read_text()
    return match_text.replace("{same_story}", (same_story_path or v.prompts / "same_story.md").read_text().strip())


def _match_input(store: ProfileStore, topics: list[TopicView], candidates: list[CardCandidate]) -> dict[str, Any]:
    """판정 LLM에 보낼 입력. 기존 주제(번호표, 제목, 설명, 제외 여부, 근거 글)와 후보(카드 제목, 장면, 종류, 근거 글).
    판정이 에이전트 의견을 따라가지 않게 에이전트가 적은 연결과 새 주제 이름은 넣지 않음.
    """
    existing = []
    for t in topics:
        detail = store.get_topic(t.topic_id)
        existing.append({"topic_id": store.aliases().alias(t.topic_id), "title": t.title, "description": t.description,
                         "excluded": t.excluded,
                         "evidence_texts": [e.text for e in detail.evidence if e.text]})
    cands = []
    for no, c in enumerate(candidates, 1):
        refs = evidence_refs(c)
        # 판정이 에이전트 의견을 따라가지 않게 연결과 새 주제 이름은 넣지 않음
        cands.append({"candidate_id": _candidate_id(no), "card_title": c.card_title, "angle": c.angle, "kind": c.kind,
                      "evidence_texts": [t for t in store.evidence_texts(refs) if t]})
    return {"existing_topics": existing, "candidates": cands}


def _apply_match(candidates: list[CardCandidate], topics: list[TopicView], result: _MatchResult) -> MatchOutcome:
    """판정 결과를 후보에 붙이고 코드로 거름."""
    by_id = {t.topic_id: t for t in topics}
    new_topics = {n.new_key: n for n in result.new_topics}
    answers: dict[str, _Assignment] = {}
    for a in result.assignments:
        answers.setdefault(a.candidate_id, a)
    out = MatchOutcome(new_topics={})
    for no, c in enumerate(candidates, 1):
        a = answers.get(_candidate_id(no))

        def drop(reason: str) -> None:
            out.dropped.append({"no": no, "card_title": c.card_title, "reason": reason})

        if a is None:
            drop("판정 결과가 없음")
            continue
        if (a.topic_id is None) == (a.new_key is None):
            drop("판정이 기존 주제와 새 주제 중 하나를 고르지 않음")
            continue
        if a.topic_id is not None:
            topic = by_id.get(a.topic_id)
            if topic is None:
                drop("판정이 없는 주제를 가리킴")
                continue
            if topic.excluded:
                drop(f"excluded 주제 '{topic.title}'와 같은 이야기: {a.reason}")
                continue
        elif a.new_key not in new_topics:
            drop(f"판정의 새 주제 {a.new_key}에 제목과 설명이 없음")
            continue
        else:
            out.new_topics[a.new_key] = new_topics[a.new_key]
        out.kept.append(Matched(no=no, candidate=c, topic_id=a.topic_id, new_key=a.new_key, reason=a.reason,
                                agent_topic_id=c.linked_topic_id))
    return out


def _candidate_id(no: int) -> str:
    """후보 번호표(c1, c2). 판정 입력과 판정 결과를 같은 형식으로 맞춤."""
    return f"c{no}"
