"""카드 생성(API 4절) 형식. JSON 이름은 필드 이름에서 camelCase로 만듦.

- 앱과 주고받음: 4-1·4-2 응답 `CardGenerationStatus`
- 생성 함수와 주고받음(4-1 처리): 요청 `CardGenerationRequest`, 결과 `CardGenerationResult`
"""

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import ConfigDict, Field
from pydantic.alias_generators import to_camel

from app.schemas.common import ApiModel


class CamelModel(ApiModel):
    model_config = ConfigDict(alias_generator=to_camel)


class CardGenerationStatus(CamelModel):
    """4-1, 4-2 응답. 상태별 홈 버튼은 API 명세 4절 표 참고."""

    schema_version: Literal[1] = 1
    status: Literal["none", "running", "ready", "inVisit", "failed"]


# ── 4-1 처리: 요청 ────────────────────────────────────
# 근거 항목: {"factId"}, {"photoId"}, {"profileField"} 중 하나
Evidence = list[dict[str, str]]


class ProfileFacts(CamelModel):
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None


class LifeFact(CamelModel):
    fact_id: UUID
    title: str
    content: str
    created_at: datetime
    # visit: 면회 뒤 제안을 승인해 생긴 이야기, caregiver: 보호자가 직접 넣은 이야기
    source: Literal["visit", "caregiver"]


class Photo(CamelModel):
    photo_id: UUID
    description: str


class TopicFeedback(CamelModel):
    action: Literal["more", "less", "exclude"]
    decided_at: datetime


class Topic(CamelModel):
    topic_id: UUID
    title: str
    description: str
    evidence: Evidence
    created_at: datetime
    feedback: list[TopicFeedback]  # 승인된 결정만


class Visit(CamelModel):
    session_id: UUID
    started_at: datetime
    set_id: UUID | None  # 이 회차에 쓴 카드 묶음


class PastCard(CamelModel):
    card_id: UUID
    set_id: UUID
    topic_id: UUID
    position: int
    card_title: str
    primary_question: str
    evidence: Evidence
    selected: bool
    review_reaction: Literal["positive", "neutral", "negative", "notUsed"] | None


class CardContext(CamelModel):
    age_range: str  # 예: "80s"
    profile_facts: ProfileFacts
    life_facts: list[LifeFact]
    photos: list[Photo]
    topics: list[Topic]
    visits: list[Visit]  # 평가까지 끝난 회차만
    past_cards: list[PastCard]  # 그 회차에 쓰인 카드 묶음의 카드


class CardGenerationRequest(CamelModel):
    schema_version: Literal[1] = 1
    model: str
    prompt_version: int
    context: CardContext


# ── 4-1 처리: 결과 ────────────────────────────────────
class GeneratedTopic(CamelModel):
    """기존 주제면 `topic_id`만, 새 주제면 `title`, `description`, `evidence`."""

    topic_id: UUID | None = None
    title: str | None = None
    description: str | None = None
    evidence: Evidence | None = None


class GeneratedCard(CamelModel):
    position: int
    topic: GeneratedTopic
    card_title: str
    description: str
    primary_question: str
    follow_up_questions: list[str]
    evidence_source: Literal["lifeFact", "photo", "profile", "none"]
    evidence: Evidence
    # 생성 쪽이 채움. BE는 generation_log에만 남김
    extra: dict[str, Any] = Field(default_factory=dict)


class CardGenerationResult(CamelModel):
    schema_version: Literal[1] = 1
    model: str
    prompt_version: int
    cards: list[GeneratedCard]
    log: dict[str, Any] = Field(default_factory=dict)
