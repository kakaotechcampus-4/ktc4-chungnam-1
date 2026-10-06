"""면회 회차(API 5절) 형식. JSON 이름은 필드 이름에서 camelCase로 만듦."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas.card_generation import CamelModel


class CreateVisitSessionRequest(CamelModel):
    """5-1 요청."""

    set_id: UUID
    selected_card_ids: list[UUID] = Field(min_length=1, max_length=9)


class VisitSession(CamelModel):
    """5-1 응답."""

    schema_version: Literal[1] = 1
    session_id: UUID
    profile_id: UUID
    set_id: UUID
    selected_card_ids: list[UUID]
    session_status: Literal[
        "evaluationPending", "audioPending", "processing", "completed", "failed"
    ]
    photo_id: UUID | None
    participant_count: int | None
    started_at: datetime
    analysis_id: UUID | None
