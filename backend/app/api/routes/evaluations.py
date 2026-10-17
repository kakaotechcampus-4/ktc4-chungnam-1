"""보호자 평가 (API 6-1, 6-4).

보호자 평가의 `리포트 만들기`에서 6-1 다음 6-2(음성 제출, `speech_analyses.py`)를
부른다. 6-1이 성공하고 6-2가 실패하면 앱은 6-2만 다시 보낸다.
"""

from uuid import UUID

from fastapi import APIRouter, status

from app.api.deps import CurrentAccountDep, DbConnectionDep
from app.schemas.common import ErrorResponse
from app.schemas.evaluation import CaregiverEvaluation, CaregiverEvaluationRequest
from app.services import evaluations

router = APIRouter(prefix="/api/v1", tags=["evaluations"])


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI에 적는다."""
    descriptions = {
        401: "인증 실패",
        404: "회차 또는 평가 없음",
        409: "이미 평가함",
        422: "요청 형식 또는 카드 평가 오류",
        503: "DB 설정 미완료",
    }
    return {
        code: {"model": ErrorResponse, "description": descriptions[code]}
        for code in statuses
    }


@router.post(
    "/visit-sessions/{session_id}/evaluation",
    status_code=status.HTTP_201_CREATED,
    response_model=CaregiverEvaluation,
    responses=_errors(401, 404, 409, 422, 503),
)
async def submit_evaluation(
    session_id: UUID,
    payload: CaregiverEvaluationRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> CaregiverEvaluation:
    return await evaluations.submit_evaluation(
        connection, session_id, account_id=account.account_id, payload=payload
    )


@router.get(
    "/visit-sessions/{session_id}/evaluation",
    response_model=CaregiverEvaluation,
    responses=_errors(401, 404, 422, 503),
)
async def get_evaluation(
    session_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> CaregiverEvaluation:
    return await evaluations.get_evaluation(
        connection, session_id, account_id=account.account_id
    )
