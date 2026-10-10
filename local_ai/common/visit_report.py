"""면회 리포트와 변경 제안이 같이 쓰는 형식. #106 내부 API(8-3)의 요청·응답과 같은 camelCase.

#106은 VisitReportRequest를 보내고 리포트와 변경 제안을 VisitReportResult 하나로 받음.
여기서는 리포트(report_generation)와 변경 제안(proposal_generation)을 따로 만들고, combine()으로 #106 응답 하나로 합침.
화자 라벨은 SPEAKER_00 같은 군집 이름이고 1~8명, 정하지 못한 구간은 null(data-contracts.md).
"""

from __future__ import annotations

__all__ = [
    "VisitReportRequest",
    "ReportEvaluation",
    "ReportCard",
    "ReportCardTopic",
    "ReportProfileFacts",
    "ReportLifeFact",
    "Transcript",
    "TranscriptSegment",
    "ReportResult",
    "ProposalResult",
    "VisitReportResult",
    "CardSummaryOut",
    "LifeFactProposalOut",
    "TopicProposalOut",
    "VisitReportError",
    "Reaction",
    "Action",
    "combine",
    "card_refs",
    "llm_payload",
]

import json
from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

Reaction = Literal["positive", "neutral", "negative", "notUsed"]
Action = Literal["more", "less", "exclude"]
ErrorCode = Literal["INVALID_REQUEST", "LLM_UNAVAILABLE", "GENERATION_FAILED"]


class _Camel(BaseModel):
    """파이썬 이름은 snake_case, JSON 이름은 camelCase로 맞추는 공통 부모. 정의에 없는 키는 받지 않음."""
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


# ── #106 요청 ──────────────────────────────────────────
class ReportEvaluation(_Camel):
    """보호자 소감. 만족도, 어르신 반응, 자유 메모."""
    conversation_satisfaction: int
    care_recipient_reaction: Literal["pleased", "calm", "angry", "lowEnergy", "unknown"]
    free_note: str | None


class ReportCardTopic(_Camel):
    """카드가 붙은 주제."""
    topic_id: str
    title: str


class ReportCard(_Camel):
    """회차에서 고른 카드 하나. 답하지 않은 카드는 reaction이 null."""
    card_id: str
    card_title: str
    topic: ReportCardTopic
    reaction: Reaction | None


class ReportProfileFacts(_Camel):
    """초기 정보 네 칸."""
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None


class ReportLifeFact(_Camel):
    """이미 저장된 이야기 하나."""
    fact_id: str
    title: str
    content: str


class TranscriptSegment(_Camel):
    """전사 구간 하나. speaker_label이 null이면 화자를 정하지 못한 구간."""
    start_ms: int
    end_ms: int
    speaker_label: str | None
    text: str


class Transcript(_Camel):
    """면회 녹음의 전사."""
    duration_ms: int
    segments: list[TranscriptSegment]


class VisitReportRequest(_Camel):
    """#106 8-3 요청. 리포트와 변경 제안이 같은 요청을 받음."""
    schema_version: Literal[1] = 1
    analysis_id: str
    visit_date: date
    evaluation: ReportEvaluation
    cards: list[ReportCard]        # 회차에서 고른 카드, position 순
    profile_facts: ReportProfileFacts
    life_facts: list[ReportLifeFact]
    transcript: Transcript


# ── 결과 ───────────────────────────────────────────────
class CardSummaryOut(_Camel):
    """카드 하나의 한 문장 요약."""
    card_id: str
    summary: str


class LifeFactProposalOut(_Camel):
    """새 이야기 후보 하나."""
    title: str
    content: str
    reason: str


class TopicProposalOut(_Camel):
    """카드의 주제 하나에 붙는 조정 제안."""
    card_id: str
    suggested_action: Action
    reason: str


class ReportResult(_Camel):
    """report_generation.generate_report의 결과."""
    model: str
    prompt_version: str
    title: str
    body: str
    card_summaries: list[CardSummaryOut]


class ProposalResult(_Camel):
    """proposal_generation.generate_proposals의 결과."""
    model: str
    prompt_version: str
    life_fact_proposals: list[LifeFactProposalOut]
    topic_proposals: list[TopicProposalOut]


class VisitReportResult(_Camel):
    """#106 8-3 응답. combine()이 만듦."""
    schema_version: Literal[1] = 1
    analysis_id: str
    model: str
    prompt_version: str
    title: str
    body: str
    card_summaries: list[CardSummaryOut]
    life_fact_proposals: list[LifeFactProposalOut]
    topic_proposals: list[TopicProposalOut]


class VisitReportError(RuntimeError):
    """리포트·변경 제안 생성의 실패.

      INVALID_REQUEST    모르는 모델
      LLM_UNAVAILABLE    엘리스 API 연결 실패, 시간 초과, 호출 한도
      GENERATION_FAILED  그 밖의 실패(형식이 깨진 응답, 빈 제목·본문 등)
    """

    def __init__(self, code: ErrorCode, message: str) -> None:
        """code는 ErrorCode 중 하나, message는 사람이 읽을 이유."""
        super().__init__(f"{code}: {message}")
        self.code, self.message = code, message


def combine(analysis_id: str, report: ReportResult, proposals: ProposalResult) -> VisitReportResult:
    """리포트와 변경 제안을 #106 응답 하나로 합침. promptVersion은 두 판을 +로 이음(#106 상한 50자)."""
    return VisitReportResult(analysis_id=analysis_id, model=report.model,
                             prompt_version=f"{report.prompt_version}+{proposals.prompt_version}"[:50],
                             title=report.title, body=report.body, card_summaries=report.card_summaries,
                             life_fact_proposals=proposals.life_fact_proposals, topic_proposals=proposals.topic_proposals)


def card_refs(request: VisitReportRequest) -> dict[str, str]:
    """cardId → 번호표(c1, c2). 모델에게는 cardId 대신 번호표를 보여 주고 돌려받은 뒤 되돌림."""
    return {c.card_id: f"c{i}" for i, c in enumerate(request.cards, 1)}


def llm_payload(request: VisitReportRequest, refs: dict[str, str], with_facts: bool) -> str:
    """모델에게 보낼 입력 JSON. 카드는 번호표로, 전사는 화자 라벨과 글만. with_facts면 초기 정보와 저장된 이야기도 넣음."""
    data = {
        "evaluation": request.evaluation.model_dump(by_alias=True),
        "cards": [{"card": refs[c.card_id], "card_title": c.card_title, "topic": c.topic.title, "reaction": c.reaction}
                  for c in request.cards],
        "transcript": [{"speaker": s.speaker_label, "text": s.text} for s in request.transcript.segments],
    }
    if with_facts:
        data["profile_facts"] = request.profile_facts.model_dump(by_alias=True)
        data["life_facts"] = [{"title": f.title, "content": f.content} for f in request.life_facts]
    return json.dumps(data, ensure_ascii=False)
