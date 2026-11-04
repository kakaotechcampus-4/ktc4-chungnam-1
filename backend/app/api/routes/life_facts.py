"""생애 정보 (API 2-6, 2-7, 2-9).

일대기에서 세부 정보 네 항목 밖의 생애 정보를 추가하고 고치고 지운다. 변경 제안 승인으로
만드는 생애 정보(7-4)는 작업 C가 `app.services.life_facts.create_life_fact`로 만든다.
2-9 번호는 임시다(`backend/docs/work-split/D-life-story.md`).
"""

from uuid import UUID

from fastapi import APIRouter, Response, status

from app.api.deps import CurrentAccountDep, DbConnectionDep, SettingsDep
from app.api.routes.profiles import to_life_fact_response
from app.schemas.common import ErrorResponse
from app.schemas.profiles import (
    LifeFactCreateRequest,
    LifeFactResponse,
    LifeFactUpdateRequest,
)
from app.services import life_facts

router = APIRouter(prefix="/api/v1", tags=["life-facts"])


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI에 적는다."""
    descriptions = {
        401: "인증 실패",
        404: "프로필, 생애 정보 또는 계정 없음",
        409: "카드를 만드는 중이라 고칠 수 없음",
        422: "요청 형식 오류",
        503: "DB 설정 미완료",
    }
    return {
        code: {"model": ErrorResponse, "description": descriptions[code]}
        for code in statuses
    }


@router.post(
    "/profiles/{profile_id}/life-facts",
    summary="생애 정보 추가",
    status_code=status.HTTP_201_CREATED,
    response_model=LifeFactResponse,
    responses=_errors(401, 404, 422, 503),
)
async def add_life_fact(
    profile_id: UUID,
    payload: LifeFactCreateRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> LifeFactResponse:
    """일대기에서 세부 정보 네 항목 밖의 생애 정보 추가.

    API 명세 2-6
    """

    fact = await life_facts.add_life_fact(
        connection,
        profile_id,
        account_id=account.account_id,
        title=payload.title,
        content=payload.content,
        story_category=payload.story_category,
        image_number=payload.image_number,
    )
    return to_life_fact_response(fact)


@router.patch(
    "/life-facts/{fact_id}",
    summary="생애 정보 수정",
    response_model=LifeFactResponse,
    responses=_errors(401, 404, 409, 422, 503),
)
async def update_life_fact(
    fact_id: UUID,
    payload: LifeFactUpdateRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    settings: SettingsDep,
) -> LifeFactResponse:
    """생애 정보 중 보낸 필드(`storyCategory`, `title`, `content`, `imageNumber`)만 수정.

    API 명세 2-7
    """

    fact = await life_facts.update_life_fact(
        connection,
        fact_id,
        account_id=account.account_id,
        changes=payload.column_changes(),
        start_timeout_seconds=settings.card_generation_start_timeout_seconds,
    )
    return to_life_fact_response(fact)


@router.delete(
    "/life-facts/{fact_id}",
    summary="생애 정보 삭제",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    responses=_errors(401, 404, 409, 503),
)
async def delete_life_fact(
    fact_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    settings: SettingsDep,
) -> Response:
    """일대기에서 생애 정보 삭제. 이미 만든 카드와 주제는 남는다. 아직 면회에 안 쓴 카드 묶음은 면회에 쓸 수 없게 된다.

    API 명세 2-9
    """

    await life_facts.delete_life_fact(
        connection,
        fact_id,
        account_id=account.account_id,
        start_timeout_seconds=settings.card_generation_start_timeout_seconds,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
