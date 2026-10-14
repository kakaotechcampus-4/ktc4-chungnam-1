"""회차 목록, 리포트와 변경 제안 (API 5-4, 7-1 ~ 7-4) 형식."""

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, Field, model_validator

from app.schemas.common import ApiModel

SessionStatus = Literal[
    "evaluationPending", "audioPending", "processing", "completed", "failed"
]
Mood = Literal["hard", "normal", "good"]
TopicAction = Literal["more", "less", "exclude"]
ReviewStatus = Literal["pending", "accepted", "rejected"]


class VisitSession(ApiModel):
    """회차 응답(5절 VisitSession).

    임시 중복: 작업 B의 PR #99가 `app/schemas/visit_session.py`에 같은 모델을 둔다.
    그 파일이 develop에 없어 여기 따로 정의하며, 필드 이름, 순서, 타입과 JSON 이름을
    그 모델과 같게 맞췄다. #99가 병합되면 B의 모델 하나로 합치고 이 클래스는 지운다.
    """

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    session_id: UUID = Field(alias="sessionId")
    profile_id: UUID = Field(alias="profileId")
    set_id: UUID = Field(alias="setId")
    selected_card_ids: list[UUID] = Field(alias="selectedCardIds")
    session_status: SessionStatus = Field(alias="sessionStatus")
    photo_id: UUID | None = Field(alias="photoId")
    participant_count: int | None = Field(alias="participantCount")
    started_at: datetime = Field(alias="startedAt")
    analysis_id: UUID | None = Field(alias="analysisId")


class VisitSessionListResponse(ApiModel):
    """5-4 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    sessions: list[VisitSession]


class ReportSummary(ApiModel):
    session_id: UUID = Field(alias="sessionId")
    title: str
    visit_date: date = Field(alias="visitDate")
    mood: Mood


class ReportListResponse(ApiModel):
    """7-1 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    reports: list[ReportSummary]


class ReportPhoto(ApiModel):
    photo_id: UUID = Field(alias="photoId")
    image_url: str = Field(alias="imageUrl")
    image_url_expires_at: datetime = Field(alias="imageUrlExpiresAt")


class CardSummary(ApiModel):
    card_id: UUID = Field(alias="cardId")
    card_title: str = Field(alias="cardTitle")
    summary: str


class VisitReport(ApiModel):
    """7-2 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    session_id: UUID = Field(alias="sessionId")
    title: str
    body: str
    visit_date: date = Field(alias="visitDate")
    mood: Mood
    photo: ReportPhoto | None
    card_summaries: list[CardSummary] = Field(alias="cardSummaries")
    generated_at: datetime = Field(alias="generatedAt")


class LifeFactProposal(ApiModel):
    proposal_id: UUID = Field(alias="proposalId")
    title: str
    content: str
    reason: str
    review_status: ReviewStatus = Field(alias="reviewStatus")


class ProposalTopic(ApiModel):
    topic_id: UUID = Field(alias="topicId")
    title: str
    description: str


class TopicProposal(ApiModel):
    proposal_id: UUID = Field(alias="proposalId")
    card_id: UUID = Field(alias="cardId")
    topic: ProposalTopic
    suggested_action: TopicAction = Field(alias="suggestedAction")
    reason: str
    review_status: ReviewStatus = Field(alias="reviewStatus")


class ChangeProposal(ApiModel):
    """7-3, 7-4 응답. 제안 값은 AI가 만든 원래 값이며 확인 뒤에도 바뀌지 않는다."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    session_id: UUID = Field(alias="sessionId")
    life_fact_proposals: list[LifeFactProposal] = Field(alias="lifeFactProposals")
    topic_proposals: list[TopicProposal] = Field(alias="topicProposals")


def _not_blank(value: str) -> str:
    if not value.strip():
        raise ValueError("빈 값은 받지 않습니다.")
    return value


# 2-6 생애 정보 추가와 같은 규칙이다(제목 100자 이하, 둘 다 비울 수 없음).
LifeFactTitle = Annotated[str, AfterValidator(_not_blank), Field(max_length=100)]
LifeFactContent = Annotated[str, AfterValidator(_not_blank)]


class LifeFactReview(ApiModel):
    proposal_id: UUID = Field(alias="proposalId")
    review_status: Literal["accepted", "rejected"] = Field(alias="reviewStatus")
    title: LifeFactTitle | None = None
    content: LifeFactContent | None = None

    @model_validator(mode="after")
    def _final_values_match_status(self) -> "LifeFactReview":
        # 승인 항목에만 보호자가 확인한 최종 값을 담는다(422 INVALID_REQUEST).
        sent = {"title", "content"} & self.model_fields_set
        if self.review_status == "accepted":
            if self.title is None or self.content is None:
                raise ValueError("승인한 생애 정보에는 title과 content가 필요합니다.")
        elif sent:
            raise ValueError("반영하지 않는 생애 정보에는 최종 값을 넣지 않습니다.")
        return self


class TopicReview(ApiModel):
    proposal_id: UUID = Field(alias="proposalId")
    review_status: Literal["accepted", "rejected"] = Field(alias="reviewStatus")
    action: TopicAction | None = None

    @model_validator(mode="after")
    def _final_values_match_status(self) -> "TopicReview":
        if self.review_status == "accepted":
            if self.action is None:
                raise ValueError("승인한 주제 제안에는 action이 필요합니다.")
        elif "action" in self.model_fields_set:
            raise ValueError("반영하지 않는 주제 제안에는 action을 넣지 않습니다.")
        return self


class ProposalReviewRequest(ApiModel):
    """7-4 요청. 회차의 `pending` 제안을 모두 담는다."""

    life_facts: list[LifeFactReview] = Field(alias="lifeFacts")
    topics: list[TopicReview]
