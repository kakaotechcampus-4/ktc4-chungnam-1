"""피보호자 프로필 (API 2-1 ~ 2-4, 2-8).

모든 경로는 현재 계정의 프로필만 다룬다. 다른 계정의 프로필은 없는 프로필과 같은 404
(`PROFILE_NOT_FOUND`)를 받는다. 2-5(프로필 입력 마치기)는 작업 B가 만든다.
"""

import logging
from uuid import UUID

from fastapi import APIRouter, status

from app.api.deps import CurrentAccountDep, DbConnectionDep
from app.schemas.common import ErrorResponse
from app.schemas.profiles import (
    Condition,
    LifeFactResponse,
    ProfileCreateRequest,
    ProfileListResponse,
    ProfileResponse,
    ProfileSummaryResponse,
    ProfileUpdateRequest,
)
from app.services import profiles
from app.services.life_facts import LifeFact
from app.services.profiles import Profile

logger = logging.getLogger("saerok.profiles")

router = APIRouter(prefix="/api/v1/profiles", tags=["profiles"])


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI에 적는다."""
    descriptions = {
        401: "인증 실패",
        404: "프로필 또는 계정 없음",
        409: "계정당 프로필 수 초과",
        422: "요청 형식 오류",
        503: "DB 설정 미완료",
    }
    return {
        code: {"model": ErrorResponse, "description": descriptions[code]}
        for code in statuses
    }


def to_life_fact_response(fact: LifeFact) -> LifeFactResponse:
    # 프로필 응답이 생애 정보를 담으므로 여기에 두고 2-6, 2-7 라우트도 쓴다.
    return LifeFactResponse(
        fact_id=fact.fact_id,
        profile_id=fact.profile_id,
        title=fact.title,
        content=fact.content,
        created_at=fact.created_at,
    )


def to_profile_response(profile: Profile) -> ProfileResponse:
    return ProfileResponse(
        profile_id=profile.profile_id,
        setup_status=profile.setup_status,
        name=profile.name,
        gender=profile.gender,
        birth_date=profile.birth_date,
        condition=Condition(
            stage=profile.condition_stage, symptom_note=profile.symptom_note
        ),
        occupation=profile.occupation,
        hometown=profile.hometown,
        hobby=profile.hobby,
        family=profile.family,
        life_facts=[to_life_fact_response(fact) for fact in profile.life_facts],
        created_at=profile.created_at,
    )


@router.get(
    "",
    response_model=ProfileListResponse,
    responses=_errors(401, 404, 503),
)
async def list_profiles(
    account: CurrentAccountDep, connection: DbConnectionDep
) -> ProfileListResponse:
    summaries = await profiles.list_profiles(
        connection, account_id=account.account_id
    )
    return ProfileListResponse(
        profiles=[
            ProfileSummaryResponse(
                profile_id=summary.profile_id,
                name=summary.name,
                gender=summary.gender,
                setup_status=summary.setup_status,
            )
            for summary in summaries
        ]
    )


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=ProfileResponse,
    responses=_errors(401, 404, 409, 422, 503),
)
async def create_profile(
    payload: ProfileCreateRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> ProfileResponse:
    profile = await profiles.create_profile(
        connection,
        account_id=account.account_id,
        name=payload.name,
        gender=payload.gender,
        birth_date=payload.birth_date,
        condition_stage=payload.condition.stage,
        symptom_note=payload.condition.symptom_note,
    )
    logger.info("profile_created")
    return to_profile_response(profile)


@router.get(
    "/{profile_id}",
    response_model=ProfileResponse,
    responses=_errors(401, 404, 422, 503),
)
async def read_profile(
    profile_id: UUID, account: CurrentAccountDep, connection: DbConnectionDep
) -> ProfileResponse:
    profile = await profiles.get_profile(
        connection, profile_id, account_id=account.account_id
    )
    return to_profile_response(profile)


@router.patch(
    "/{profile_id}",
    response_model=ProfileResponse,
    responses=_errors(401, 404, 422, 503),
)
async def update_profile(
    profile_id: UUID,
    payload: ProfileUpdateRequest,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
) -> ProfileResponse:
    profile = await profiles.update_profile(
        connection,
        profile_id,
        account_id=account.account_id,
        changes=payload.column_changes(),
    )
    return to_profile_response(profile)


@router.delete(
    "/{profile_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=_errors(401, 404, 422, 503),
)
async def delete_profile(
    profile_id: UUID, account: CurrentAccountDep, connection: DbConnectionDep
) -> None:
    await profiles.delete_profile(
        connection, profile_id, account_id=account.account_id
    )
    logger.info("profile_deleted")
