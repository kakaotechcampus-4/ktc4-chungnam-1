from fastapi import APIRouter, status

from app.api.deps import CurrentAccountDep, DbConnectionDep
from app.schemas.visit_session import CreateVisitSessionRequest, VisitSession
from app.services.ownership import CARD_SET, require_owned
from app.services.visit_sessions import create_visit_session, load_visit_session


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
