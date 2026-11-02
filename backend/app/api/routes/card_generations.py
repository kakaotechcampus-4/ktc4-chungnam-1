from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Path, status

from app.api.deps import CurrentAccountDep, DbConnectionDep, SettingsDep
from app.core.errors import AppError
from app.schemas.card_generation import CardGenerationStatus, CardSet
from app.services.card_sets import (
    current_card_set,
    generation_status,
    start_card_generation,
)
from app.services.ownership import PROFILE, require_owned


router = APIRouter(tags=["card-generations"])


@router.post(
    "/api/v1/profiles/{profile_id}/card-generations",
    summary="카드 생성 시작",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=CardGenerationStatus,
    response_model_by_alias=True,
)
async def create_card_generation(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    settings: SettingsDep,
    profile_id: Annotated[UUID, Path()],
) -> CardGenerationStatus:
    """카드 생성 작업 생성. 이미 만드는 중이면 새로 만들지 않음.

    평가 전 회차가 묶음을 쓰는 중(`inVisit`)이면 거절함. 새 묶음이 생기면 4-3이 면회 중인 카드를 못 줌.
    아직 안 쓴 묶음이 있어도(`ready`) 거절함. 단 `needsRefresh`이면 거절하지 않고 새 묶음을 만듦.

    API 명세 4-1
    """

    await require_owned(connection, PROFILE, profile_id, account_id=account.account_id)
    if not settings.ml_api_key.get_secret_value():
        # 키 없이 작업을 만들면 worker에서 실패함
        raise AppError(
            status_code=503,
            error_code="CARD_GENERATION_NOT_CONFIGURED",
            message="카드 생성이 설정되지 않았습니다.",
        )
    await start_card_generation(
        connection,
        profile_id,
        model=settings.card_generation_model,
        prompt_version=settings.card_generation_prompt_version,
        start_timeout_seconds=settings.card_generation_start_timeout_seconds,
    )
    return CardGenerationStatus(status="running")


@router.get(
    "/api/v1/profiles/{profile_id}/card-generations/status",
    summary="카드 생성 상태 조회",
    response_model=CardGenerationStatus,
    response_model_by_alias=True,
)
async def get_card_generation_status(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    settings: SettingsDep,
    profile_id: Annotated[UUID, Path()],
) -> CardGenerationStatus:
    """홈 버튼 상태. 작업이 없어도 오류가 아니라 `none`.

    worker가 가져가지 않거나 멈춘 작업은 정해진 시간이 지나면 `failed`로 바뀜. 앱이 다시 요청할 수 있음.

    API 명세 4-2
    """

    await require_owned(connection, PROFILE, profile_id, account_id=account.account_id)
    return await generation_status(
        connection,
        profile_id,
        start_timeout_seconds=settings.card_generation_start_timeout_seconds,
    )


@router.get(
    "/api/v1/profiles/{profile_id}/card-generations/current",
    summary="현재 카드 묶음 조회",
    response_model=CardSet,
    response_model_by_alias=True,
)
async def get_current_card_set(
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    profile_id: Annotated[UUID, Path()],
) -> CardSet:
    """지금 쓸 카드 묶음. 고르기 전과 평가 전 회차에 쓰는 중에 같은 묶음.

    API 명세 4-3
    """

    await require_owned(connection, PROFILE, profile_id, account_id=account.account_id)
    return await current_card_set(connection, profile_id)
