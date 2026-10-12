"""backend 카드 생성 worker와 주고받는 요청·결과·실패 형식. JSON 이름은 API 명세와 같은 camelCase.

backend가 DB에서 context를 조립해 generate_cards(GenerationRequest)를 부르고 결과를 저장함. 카드 생성은 DB를 읽거나 쓰지 않음.
넘기는 정보는 API 명세 2절(민혁님, #87: 이름·성별·생년월일은 내부 API에 넣지 않음)과 #99의 4-1 처리 기준.
사진 설명은 보호자 확인 전 것도 넣음. 민혁님 의견(회의, #99 본문에 기록).
  넘김    연령대, 세부 정보 네 항목, 이야기(출처·등록 시각 포함), 분석이 끝난 프로필 사진의 설명, 주제와 승인된 결정,
          평가까지 끝난 면회 목록, 그 면회에 쓰인 카드
  안 넘김 이름, 성별, 생년월일, 인지 상태, 증상 메모, 면회 평가 메모, 리포트 본문, 승인 전 제안, 회차에 안 쓰인 카드 묶음
"""

from __future__ import annotations

__all__ = [
    "GenerationRequest",
    "CardContext",
    "ProfileFacts",
    "LifeFactIn",
    "PhotoIn",
    "FeedbackIn",
    "TopicIn",
    "VisitIn",
    "PastCardIn",
    "GenerationResult",
    "CardOut",
    "TopicOut",
    "CardExtra",
    "CardGenerationError",
    "ErrorCode",
    "Action",
    "Reaction",
]

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

Action = Literal["more", "less", "exclude"]
ErrorCode = Literal["INVALID_CONTEXT", "NOT_ENOUGH_TOPICS", "TEXT_CHECK_FAILED", "LLM_UNAVAILABLE", "CARD_GENERATION_FAILED"]
Reaction = Literal["positive", "neutral", "negative", "notUsed"]


class _Camel(BaseModel):
    """파이썬 이름은 snake_case, JSON 이름은 camelCase로 맞추는 공통 부모. 정의에 없는 키는 받지 않음."""
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


# ── 입력 ─────────────────────────────────────────────
class ProfileFacts(_Camel):
    """초기 정보 네 칸(하시던 일, 고향, 취미, 가족). 비어 있으면 None."""
    occupation: str | None = None
    hometown: str | None = None
    hobby: str | None = None
    family: str | None = None


class LifeFactIn(_Camel):
    """보호자가 확인한 생애 이야기 하나. source가 visit이면 면회 뒤 제안을 승인해 생긴 이야기."""
    fact_id: str
    title: str
    content: str
    created_at: datetime | None = None
    source: Literal["visit", "caregiver"] = "caregiver"   # visit: 면회 뒤 제안을 승인해 생긴 이야기


class PhotoIn(_Camel):
    """분석이 끝난 프로필 사진 하나의 설명."""
    photo_id: str
    description: str


class FeedbackIn(_Camel):
    """보호자가 승인한 주제 결정 하나(more·less·exclude)와 결정 시각."""
    action: Action
    decided_at: datetime


class TopicIn(_Camel):
    """이 프로필의 기존 주제 하나. 근거와 승인된 결정 이력을 함께 받음."""
    topic_id: str
    title: str
    description: str
    evidence: list[dict[str, str]] = Field(default_factory=list)
    created_at: datetime | None = None
    feedback: list[FeedbackIn] = Field(default_factory=list)   # 승인된 결정만


class VisitIn(_Camel):
    """평가까지 끝난 면회 하나. set_id는 그 면회에 쓴 카드 묶음."""
    session_id: str
    started_at: datetime
    set_id: str | None = None   # 이 면회에 쓴 카드 묶음


class PastCardIn(_Camel):
    """평가까지 끝난 면회에 쓰인 카드 하나. 지난 질문을 되풀이하지 않고 사용 이력을 세는 데 씀."""
    card_id: str
    set_id: str
    topic_id: str
    position: int = Field(ge=1, le=12)
    card_title: str
    primary_question: str
    evidence: list[dict[str, str]] = Field(default_factory=list)
    selected: bool
    review_reaction: Reaction | None = None


class CardContext(_Camel):
    """backend가 DB에서 모아 넘기는 프로필 하나의 정보 전부. 카드 생성은 이것만 봄."""
    age_range: str = Field(pattern=r"^\d0s$")   # 예: "80s"
    profile_facts: ProfileFacts
    life_facts: list[LifeFactIn] = Field(default_factory=list)
    photos: list[PhotoIn] = Field(default_factory=list)
    topics: list[TopicIn] = Field(default_factory=list)
    visits: list[VisitIn] = Field(default_factory=list)     # 평가까지 끝난 회차만
    past_cards: list[PastCardIn] = Field(default_factory=list)


class GenerationRequest(_Camel):
    """generate_cards의 입력. model과 prompt_version은 backend 설정값."""
    schema_version: Literal[1] = 1
    model: str            # backend 설정. card_sets.model과 같은 값. common/llm.py의 ENDPOINTS에 있는 이름만 받음
    prompt_version: int   # backend 설정. _versions.VERSIONS에 있는 판만 받음
    context: CardContext


# ── 결과 ─────────────────────────────────────────────
class TopicOut(_Camel):
    """기존 주제면 topic_id만, 새 주제면 title·description·evidence. 새 주제의 topicId는 backend가 정함."""
    topic_id: str | None = None
    title: str | None = None
    description: str | None = None
    evidence: list[dict[str, str]] | None = None


class CardExtra(_Camel):
    """화면에 안 쓰는 부가 정보. backend는 generation_log에만 남김."""
    kind: Literal["personal", "photo", "discover", "general"]
    bucket: Literal["new", "existing"]
    angle: str
    pick_reason: str
    agent_reason: str
    match_reason: str


class CardOut(_Camel):
    """카드 한 장. evidence_source는 근거 종류, evidence는 근거 항목 목록(none이면 빈 목록)."""
    position: int
    topic: TopicOut
    card_title: str
    description: str
    primary_question: str
    follow_up_questions: list[str]
    evidence_source: Literal["lifeFact", "photo", "profile", "none"]
    evidence: list[dict[str, str]]
    extra: CardExtra


class GenerationResult(_Camel):
    """generate_cards의 결과. 카드 12장과 generation_log에 남길 실행 기록."""
    schema_version: Literal[1] = 1
    model: str
    prompt_version: int
    cards: list[CardOut]                       # 12장. 1~9는 고르는 카드, 10~12는 면회 중 보충용(API 명세 4절, #87)
    log: dict[str, Any] = Field(default_factory=dict)   # 후보 수, 도구 호출, 다시 찾기, 빠진 후보 등. generation_log용


# ── 실패 ─────────────────────────────────────────────


class CardGenerationError(RuntimeError):
    """worker가 code를 card_sets.error_code에 그대로 남김.

      INVALID_CONTEXT         입력 형식이 맞지 않거나 모르는 promptVersion·model
      NOT_ENOUGH_TOPICS       다시 찾아도 서로 다른 주제로 12장을 채우지 못함
      TEXT_CHECK_FAILED       문안이 금지 표현 검사에 두 번 걸림
      LLM_UNAVAILABLE         엘리스 API 연결 실패, 시간 초과, 호출 한도
      CARD_GENERATION_FAILED  그 밖의 실패(에이전트가 제출하지 않음 등)
    """

    def __init__(self, code: ErrorCode, message: str) -> None:
        """code는 ErrorCode 중 하나, message는 사람이 읽을 이유."""
        super().__init__(f"{code}: {message}")
        self.code, self.message = code, message
