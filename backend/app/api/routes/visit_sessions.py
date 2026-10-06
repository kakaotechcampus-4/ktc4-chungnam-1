from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Path, status

from app.api.deps import CurrentAccountDep, DbConnectionDep
from app.schemas.visit_session import (
    AddCardsRequest,
    CreateVisitSessionRequest,
    VisitSession,
)
from app.services.ownership import CARD_SET, VISIT_SESSION, require_owned
from app.services.visit_sessions import (
    add_session_cards,
    create_visit_session,
    load_visit_session,
)


router = APIRouter(tags=["visit-sessions"])


@router.post(
    "/api/v1/visit-sessions",
    status_code=status.HTTP_201_CREATED,
    response_model=VisitSession,
    response_model_by_alias=True,
)
async def create_session(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    body: CreateVisitSessionRequest,
) -> VisitSession:
    """5-1. 녹음을 시작할 때 고른 카드(1~9번)로 회차 생성. `startedAt`은 서버 수신 시각."""

    await require_owned(connection, CARD_SET, body.set_id, account_id=account.account_id)
    session_id = await create_visit_session(connection, body.set_id, body.selected_card_ids)
    return await load_visit_session(connection, session_id)


@router.patch(
    "/api/v1/visit-sessions/{session_id}/cards",
    response_model=VisitSession,
    response_model_by_alias=True,
)
async def add_cards(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    session_id: Annotated[UUID, Path()],
    body: AddCardsRequest,
) -> VisitSession:
    """5-3. 면회 중 꺼낸 보충 카드(10~12번) 추가. 같은 요청을 다시 보내도 결과가 같음."""

    await require_owned(connection, VISIT_SESSION, session_id, account_id=account.account_id)
    await add_session_cards(connection, session_id, body.card_ids)
    return await load_visit_session(connection, session_id)
