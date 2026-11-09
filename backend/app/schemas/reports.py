"""회차 목록, 리포트와 변경 제안 (API 5-4, 7-1 ~ 7-4) 형식."""

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.common import ApiModel
from app.schemas.profiles import LifeFactContent, LifeFactTitle, StoryCategory
from app.schemas.visit_session import VisitSession

Mood = Literal["hard", "normal", "good"]
TopicAction = Literal["more", "less", "exclude"]
ReviewStatus = Literal["pending", "accepted", "rejected"]


class VisitSessionListResponse(ApiModel):
    """5-4 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    sessions: list[VisitSession]


class ReportPhoto(ApiModel):
    photo_id: UUID = Field(alias="photoId")
    image_url: str = Field(alias="imageUrl")
    image_url_expires_at: datetime = Field(alias="imageUrlExpiresAt")


class ReportSummary(ApiModel):
    session_id: UUID = Field(alias="sessionId")
    title: str
    visit_date: date = Field(alias="visitDate")
    mood: Mood
    photo: ReportPhoto | None


class ReportListResponse(ApiModel):
    """7-1 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    reports: list[ReportSummary]


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
    # AI가 고른 일대기 분류. 보호자가 7-4에서 다른 분류로 승인해도 이 값은 바뀌지 않는다.
    story_category: StoryCategory = Field(alias="storyCategory")
    # 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 후보. 앱이 안내 문구를 붙인다.
    sensitive: bool
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


class LifeFactReview(ApiModel):
    """7-4의 생애 정보 확인 항목. 최종 제목과 내용은 2-6과 같은 형식이다(제목 100자, 내용
    5,000자 이하, 둘 다 비울 수 없음). 프로필당 개수 상한은 `create_life_fact`가 확인한다.

    `storyCategory`는 승인 항목에만 넣을 수 있고 생략할 수 있다. 생략하면 제안의 분류(AI가 고른
    값)로 이야기를 만든다. `null`은 받지 않는다(2026-11-09 PM 결정).
    """

    proposal_id: UUID = Field(alias="proposalId")
    review_status: Literal["accepted", "rejected"] = Field(alias="reviewStatus")
    title: LifeFactTitle | None = None
    content: LifeFactContent | None = None
    story_category: StoryCategory | None = Field(default=None, alias="storyCategory")

    @model_validator(mode="after")
    def _final_values_match_status(self) -> "LifeFactReview":
        # 승인 항목에만 보호자가 확인한 최종 값을 담는다(422 INVALID_REQUEST).
        sent = {"title", "content", "story_category"} & self.model_fields_set
        if self.review_status == "accepted":
            if self.title is None or self.content is None:
                raise ValueError("승인한 생애 정보에는 title과 content가 필요합니다.")
            if "story_category" in sent and self.story_category is None:
                raise ValueError("storyCategory는 null일 수 없습니다.")
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
