"""보호자 평가 (API 6-1, 6-4) 형식."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, StrictBool, StrictInt

from app.schemas.common import ApiModel

CareRecipientReaction = Literal["pleased", "calm", "angry", "lowEnergy", "unknown"]
CaregiverReaction = Literal["positive", "neutral", "negative"]


class CardReview(ApiModel):
    """카드 하나의 평가. 답하지 않은 카드는 `cardReviews`에 넣지 않는다.

    `wasUsed`와 `caregiverReaction`의 짝은 명세의 422 `INVALID_CARD_REVIEW`로
    거절해야 하므로 여기서 막지 않고 서비스에서 확인한다.
    """

    card_id: UUID = Field(alias="cardId")
    was_used: StrictBool = Field(alias="wasUsed")
    caregiver_reaction: CaregiverReaction | None = Field(alias="caregiverReaction")


class CaregiverEvaluationRequest(ApiModel):
    """6-1 요청."""

    conversation_satisfaction: StrictInt = Field(
        alias="conversationSatisfaction", ge=1, le=5
    )
    care_recipient_reaction: CareRecipientReaction = Field(
        alias="careRecipientReaction"
    )
    card_reviews: list[CardReview] = Field(alias="cardReviews")
    free_note: str | None = Field(alias="freeNote")


class CaregiverEvaluation(ApiModel):
    """6-1, 6-4 응답."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    session_id: UUID = Field(alias="sessionId")
    conversation_satisfaction: int = Field(alias="conversationSatisfaction")
    care_recipient_reaction: CareRecipientReaction = Field(
        alias="careRecipientReaction"
    )
    card_reviews: list[CardReview] = Field(alias="cardReviews")
    free_note: str | None = Field(alias="freeNote")
    evaluated_at: datetime = Field(alias="evaluatedAt")
