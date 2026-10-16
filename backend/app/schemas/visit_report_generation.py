"""리포트 생성 내부 API(8-3, 백엔드 → AI 서버) 형식.

피보호자의 이름, 성별과 생년월일은 요청에 넣지 않는다. 응답의 길이와 빈 값 제한은
저장할 컬럼의 제약(`visit_sessions.report_*`, 제안 테이블)과 같게 둬, 저장 단계에서
DB 오류로 실패하지 않고 형식 오류(`INVALID_AI_RESPONSE`)로 걸러지게 한다.
"""

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, Field

from app.schemas.common import ApiModel
from app.schemas.evaluation import CareRecipientReaction

CardReaction = Literal["positive", "neutral", "negative", "notUsed"]


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


class GeneratedCardSummary(ApiModel):
    card_id: UUID = Field(alias="cardId")
    summary: NonBlank


class GeneratedLifeFactProposal(ApiModel):
    title: Annotated[NonBlank, Field(max_length=100)]
    content: NonBlank
    reason: NonBlank


class GeneratedTopicProposal(ApiModel):
    card_id: UUID = Field(alias="cardId")
    suggested_action: Literal["more", "less", "exclude"] = Field(
        alias="suggestedAction"
    )
    reason: NonBlank


class VisitReportResult(ApiModel):
    """AI 서버에서 받은 리포트. 카드와 제안의 규칙은 생성기가 따로 검증한다."""

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
        alias="lifeFactProposals"
    )
    topic_proposals: list[GeneratedTopicProposal] = Field(alias="topicProposals")
