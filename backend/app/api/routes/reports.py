"""회차 목록, 리포트와 변경 제안 (API 5-4, 7-1 ~ 7-4).

회차 생성(5-1)과 보충 카드 추가(5-3)는 작업 B가 맡는다. 리포트와 변경 제안은 음성
worker의 리포트 생성기(8-3, `app/services/visit_report_generator.py`)가 저장한다.
"""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query

from app.api.deps import CurrentAccountDep, DbConnectionDep, ImageStorageDep
from app.schemas.common import ErrorResponse
from app.schemas.reports import (
    ChangeProposal,
    ProposalReviewRequest,
    ReportListResponse,
    VisitReport,
    VisitSessionListResponse,
)
from app.services import proposals, reports, session_status

router = APIRouter(prefix="/api/v1", tags=["reports"])

# 5-4, 7-1의 `limit`. 기본 20, 최대 100이며 범위 밖이면 422 `INVALID_REQUEST`다.
Limit = Annotated[int, Query(ge=1, le=100)]


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI에 적는다."""
    descriptions = {
        401: "인증 실패",
        404: "프로필, 회차 또는 리포트 없음",
        409: "이미 확인한 변경 제안",
        422: "요청 형식 또는 변경 제안 확인 오류",
        503: "DB 또는 사진 저장소 설정 미완료, 사진 저장소 오류",
    }
    return {
        code: {"model": ErrorResponse, "description": descriptions[code]}
        for code in statuses
    }


@router.get(
    "/profiles/{profile_id}/visit-sessions",
    response_model=VisitSessionListResponse,
    responses=_errors(401, 404, 422, 503),
)
async def list_visit_sessions(
    profile_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    limit: Limit = 20,
) -> VisitSessionListResponse:
    sessions = await session_status.list_visit_sessions(
        connection, profile_id, account_id=account.account_id, limit=limit
    )
    return VisitSessionListResponse(sessions=sessions)


@router.get(
    "/profiles/{profile_id}/reports",
    response_model=ReportListResponse,
    responses=_errors(401, 404, 422, 503),
)
async def list_reports(
    profile_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    limit: Limit = 20,
) -> ReportListResponse:
    items = await reports.list_reports(
        connection, profile_id, account_id=account.account_id, limit=limit
    )
    return ReportListResponse(reports=items)


@router.get(
    "/visit-sessions/{session_id}/report",
    response_model=VisitReport,
    responses=_errors(401, 404, 422, 503),
)
async def get_report(
    session_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    storage: ImageStorageDep,
) -> VisitReport:
    return await reports.get_report(
        connection, session_id, account_id=account.account_id, storage=storage
    )


@router.get(
    "/visit-sessions/{session_id}/proposals",
    response_model=ChangeProposal,
    responses=_errors(401, 404, 422, 503),
)
async def get_proposals(
    session_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> ChangeProposal:
    return await proposals.get_proposals(
        connection, session_id, account_id=account.account_id
    )


@router.post(
    "/visit-sessions/{session_id}/proposals/review",
    response_model=ChangeProposal,
    responses=_errors(401, 404, 409, 422, 503),
)
async def review_proposals(
    session_id: UUID,
    payload: ProposalReviewRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> ChangeProposal:
    return await proposals.review_proposals(
        connection, session_id, account_id=account.account_id, payload=payload
    )
