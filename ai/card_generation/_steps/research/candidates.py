"""조사 에이전트가 내는 카드 후보 형식과 제출 검증. 개수 기준은 판(versions)마다 있음."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

from card_generation._steps.research.tools import InitialField
from card_generation._versions.base import Version

_TITLE_MAX = 100   # 카드 제목과 새 주제 제목. backend DB가 VARCHAR(100)


# ── 에이전트 제출(response_format) ─────────────────────
class Evidence(BaseModel):
    """셋 중 하나만 값을 넣는다."""
    fact_id: str | None
    photo_id: str | None
    field: InitialField | None


# 조사 에이전트가 내는 카드 후보 하나. 질문 문장은 아직 없고 어떤 이야기의 어느 장면을 무엇을 근거로 다룰지만 담음.
# 모델이 읽는 스키마라 docstring 대신 필드 description으로 설명함
class CardCandidate(BaseModel):
    linked_topic_id: str | None = Field(description="기존 주제와 같은 이야기면 그 topicId, 아니면 null")
    new_topic_title: str | None = Field(description="연결할 주제가 없을 때만 쓰는 새 주제 제목")
    new_topic_description: str | None = Field(description="연결할 주제가 없을 때만 쓰는 새 주제 설명")
    card_title: str = Field(description="카드 제목. 짧은 명사구")
    angle: str = Field(description="이번에 다룰 장면·사람·물건·시기")
    kind: Literal["personal", "photo", "discover", "general"]
    evidence: list[Evidence] = Field(description="personal·photo는 1개 이상, 나머지는 빈 목록")
    discover_field: InitialField | None = Field(description="kind가 discover일 때 여쭤 알아갈 빈 칸")
    reason: str = Field(description="이 카드를 고른 이유")


class CardCandidateSubmission(BaseModel):
    """대화 카드 후보 16~24개를 제출하고 조사를 끝낸다."""
    candidates: list[CardCandidate]


def submission_problems(sub: CardCandidateSubmission, version: Version) -> list[str]:
    """제출 검사. 후보 수, 주제 수, 한 주제의 후보 수, 새 주제 수, 근거 형식과 종류, 제목 길이를 판(version) 값으로 봄.
    걸린 것을 문장 목록으로 돌려주고, 이 문장을 그대로 모델에게 보내 다시 내게 함.
    """
    problems: list[str] = []
    n = len(sub.candidates)
    if not version.min_candidates <= n <= version.max_candidates:
        problems.append(f"후보가 {n}개다. {version.min_candidates}~{version.max_candidates}개여야 한다.")
    counts: dict[str, int] = {}
    for i, c in enumerate(sub.candidates, 1):
        if not c.linked_topic_id and not (c.new_topic_title and c.new_topic_description):
            problems.append(f"{i}번: 기존 주제에 연결하거나 새 주제 제목과 설명을 써야 한다.")
        if c.linked_topic_id and (c.new_topic_title or c.new_topic_description):
            problems.append(f"{i}번: 기존 주제에 연결했으면 새 주제 제목과 설명은 null이어야 한다.")
        if any(sum(x is not None for x in (e.fact_id, e.photo_id, e.field)) != 1 for e in c.evidence):
            problems.append(f"{i}번: evidence 원소마다 fact_id, photo_id, field 중 하나만 값을 넣어야 한다.")
        if len({"fact" if e.fact_id else "photo" if e.photo_id else "field" for e in c.evidence}) > 1:
            # backend(#99 4-1 검증)는 한 카드의 근거를 한 종류만 받음
            problems.append(f"{i}번: evidence는 한 종류로만 적는다(이야기끼리, 사진끼리, 초기 정보 칸끼리).")
        if len(c.card_title) > _TITLE_MAX or len(c.new_topic_title or "") > _TITLE_MAX:
            problems.append(f"{i}번: 카드 제목과 새 주제 제목은 {_TITLE_MAX}자 이하여야 한다.")
        if c.kind in ("personal", "photo") and not c.evidence:
            problems.append(f"{i}번: {c.kind}는 근거가 하나 이상 있어야 한다.")
        if c.kind == "photo" and not any(e.photo_id for e in c.evidence):
            problems.append(f"{i}번: photo는 photo_id 근거가 있어야 한다.")
        if c.kind in ("discover", "general") and c.evidence:
            problems.append(f"{i}번: {c.kind}는 evidence를 비워야 한다.")
        if (c.kind == "discover") != (c.discover_field is not None):
            problems.append(f"{i}번: discover_field는 kind가 discover일 때만, 그리고 그때는 꼭 쓴다.")
        counts[_topic_key(c)] = counts.get(_topic_key(c), 0) + 1
    crowded = [k.split(":", 1)[1] for k, v in counts.items() if v > version.max_per_topic]
    if crowded:
        problems.append(f"한 주제에 후보가 {version.max_per_topic}개를 넘는다: {', '.join(crowded)}")
    new_topics = [k for k in counts if k.startswith("new:")]
    if len(new_topics) < version.min_new_topics:
        problems.append(f"새 주제(기존 주제에 연결하지 않은 이야기)가 {len(new_topics)}개다. {version.min_new_topics}개 이상이어야 한다. "
                        "아직 다루지 않은 이야기나 연령대에 맞는 옛 추억에서 새 이야기를 더 찾아라.")
    if len(counts) < version.min_topics:
        problems.append(f"서로 다른 주제가 {len(counts)}개다. 최종 카드는 주제마다 한 장이라 {version.min_topics}개 이상이어야 한다. "
                        "다른 이야기에서 후보를 더 찾아라.")
    return problems


def evidence_refs(c: CardCandidate) -> list[dict[str, str]]:
    """후보 근거를 backend 형식({"factId"}, {"photoId"}, {"profileField"})으로 바꿈."""
    return [{"factId": e.fact_id} if e.fact_id else {"photoId": e.photo_id} if e.photo_id else {"profileField": e.field}
            for e in c.evidence if e.fact_id or e.photo_id or e.field]


def _topic_key(c: CardCandidate) -> str:
    """에이전트 기준 주제 구분. 기존 주제는 ID, 새 주제는 제목으로 셈."""
    return f"id:{c.linked_topic_id}" if c.linked_topic_id else f"new:{(c.new_topic_title or '').strip()}"
