"""리포트 생성 내부 API(8-3, 백엔드 → AI 서버) 형식.

피보호자의 이름, 성별과 생년월일은 요청에 넣지 않는다. 응답의 길이와 빈 값 제한은
저장할 컬럼의 제약(`visit_sessions.report_*`, 제안 테이블)과 같게 둬, 저장 단계에서
DB 오류로 실패하지 않고 형식 오류(`INVALID_AI_RESPONSE`)로 걸러지게 한다.
"""

from dataclasses import dataclass, field
from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, Field, PrivateAttr

from app.schemas.common import ApiModel
from app.schemas.evaluation import CareRecipientReaction
from app.schemas.profiles import StoryCategory

CardReaction = Literal["positive", "neutral", "negative", "notUsed"]
# 한 리포트의 이야기 후보 상한(PM 결정, 2026-11-09). AI 쪽이 넘는 후보를 잘라 이만큼만 보내고
# (`ai/proposal_generation/generate.py`의 `_FACT_MAX`), 넘게 오면 형식 오류로 본다.
LIFE_FACT_PROPOSAL_LIMIT = 30


def _not_blank(value: str) -> str:
    if not value.strip():
        raise ValueError("빈 값은 받지 않습니다.")
    return value


NonBlank = Annotated[str, AfterValidator(_not_blank)]


class ReportEvaluation(ApiModel):
    conversation_satisfaction: int = Field(alias="conversationSatisfaction")
    care_recipient_reaction: CareRecipientReaction = Field(
        alias="careRecipientReaction"
    )
    free_note: str | None = Field(alias="freeNote")


class ReportCardTopic(ApiModel):
    topic_id: UUID = Field(alias="topicId")
    title: str


class ReportCard(ApiModel):
    card_id: UUID = Field(alias="cardId")
    card_title: str = Field(alias="cardTitle")
    topic: ReportCardTopic
    # 답하지 않은 카드는 null이다.
    reaction: CardReaction | None


class ReportProfileFacts(ApiModel):
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None


class ReportLifeFact(ApiModel):
    fact_id: UUID = Field(alias="factId")
    title: str
    content: str


class ReportTranscriptSegment(ApiModel):
    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    speaker_label: str | None = Field(alias="speakerLabel")
    text: str


class ReportTranscript(ApiModel):
    duration_ms: int = Field(alias="durationMs")
    segments: list[ReportTranscriptSegment]


class VisitReportRequest(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    visit_date: date = Field(alias="visitDate")
    evaluation: ReportEvaluation
    cards: list[ReportCard]
    profile_facts: ReportProfileFacts = Field(alias="profileFacts")
    life_facts: list[ReportLifeFact] = Field(alias="lifeFacts")
    transcript: ReportTranscript
    # 녹음 제출 당시 예상 인원. 라벨 개수와 비교하되 사람의 역할을 뜻하지 않는다.
    # 이전 호출자는 생략할 수 있다. 생략을 2명으로 추측하지 않는다.
    participant_count: int | None = Field(default=None, alias="participantCount", ge=1, le=8)


class GeneratedCardSummary(ApiModel):
    card_id: UUID = Field(alias="cardId")
    summary: NonBlank


class GeneratedLifeFactProposal(ApiModel):
    title: Annotated[NonBlank, Field(max_length=100)]
    content: NonBlank
    reason: NonBlank
    # AI가 고른 일대기 분류. 7-4 승인 때 보호자가 바꾸지 않으면 이 분류로 이야기를 만든다.
    story_category: StoryCategory = Field(alias="storyCategory")
    # 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 후보.
    sensitive: bool


class GeneratedTopicProposal(ApiModel):
    card_id: UUID = Field(alias="cardId")
    suggested_action: Literal["more", "less", "exclude"] = Field(
        alias="suggestedAction"
    )
    reason: NonBlank


@dataclass(frozen=True)
class GenerationCounts:
    """생성 함수가 처리 기록(로그)에 쓰라고 따로 알려 주는 숫자. 8-3 응답 JSON에는 없다.

    `*_returned`는 모델이 낸 개수(AI 쪽에서 거르고 자르기 전), `token_usage`는 모델 호출의 토큰 수다.
    글은 담지 않는다.
    """

    life_fact_proposals_returned: int | None = None
    topic_proposals_returned: int | None = None
    token_usage: dict[str, int] = field(default_factory=dict)


class VisitReportResult(ApiModel):
    """AI 서버에서 받은 리포트. 카드와 제안의 규칙은 생성기가 따로 검증한다."""

    # 처리 기록용 숫자. JSON으로 읽고 쓰지 않으며 ai 패키지를 감싼 생성 함수만 채운다.
    _counts: GenerationCounts = PrivateAttr(default_factory=GenerationCounts)

    schema_version: Literal[1] = Field(alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    model: Annotated[NonBlank, Field(max_length=100)]
    prompt_version: Annotated[NonBlank, Field(max_length=50)] = Field(
        alias="promptVersion"
    )
    title: Annotated[NonBlank, Field(max_length=200)]
    body: NonBlank
    card_summaries: list[GeneratedCardSummary] = Field(alias="cardSummaries")
    life_fact_proposals: list[GeneratedLifeFactProposal] = Field(
        alias="lifeFactProposals", max_length=LIFE_FACT_PROPOSAL_LIMIT
    )
    topic_proposals: list[GeneratedTopicProposal] = Field(alias="topicProposals")

    @property
    def counts(self) -> GenerationCounts:
        return self._counts

    def with_counts(self, counts: GenerationCounts) -> "VisitReportResult":
        """처리 기록용 숫자를 붙여 자신을 돌려준다."""
        self._counts = counts
        return self
