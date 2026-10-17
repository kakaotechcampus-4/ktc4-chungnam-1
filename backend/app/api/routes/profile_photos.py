"""프로필 사진 (API 3-1, 3-2).

온보딩의 사진 첨부와 마이페이지의 갤러리 추가에서 사진을 한 장씩 올린다. 서버는 사진을
S3에 저장하고 분석 대기(`pending`) 행을 만든다. 앱은 3-2로 분석이 끝날 때까지 폴링한다.
다른 계정의 자원은 없는 자원과 같은 404를 받는다.
"""

import logging
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, File, UploadFile, status

from app.api.deps import (
    CurrentAccountDep,
    DbConnectionDep,
    ImageStorageDep,
    SettingsDep,
)
from app.api.routes.profiles import to_profile_photo_response
from app.schemas.common import ErrorResponse
from app.schemas.profiles import ProfilePhotoResponse
from app.services import profile_photos

logger = logging.getLogger("saerok.profile_photos")

router = APIRouter(prefix="/api/v1", tags=["profile-photos"])


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI에 적는다."""
    descriptions = {
        401: "인증 실패",
        404: "프로필, 프로필 사진 또는 계정 없음",
        409: "프로필당 사진 수 초과",
        413: "사진 크기 초과",
        422: "요청 형식 오류 또는 JPEG, PNG가 아닌 사진",
        503: "DB 또는 사진 저장소 설정 미완료, 사진 저장소 사용 불가",
    }
    return {
        code: {"model": ErrorResponse, "description": descriptions[code]}
        for code in statuses
    }


@router.post(
    "/profiles/{profile_id}/photos",
    status_code=status.HTTP_201_CREATED,
    response_model=ProfilePhotoResponse,
    responses=_errors(401, 404, 409, 413, 422, 503),
)
async def upload_profile_photo(
    profile_id: UUID,
    image: Annotated[UploadFile, File()],
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    storage: ImageStorageDep,
    settings: SettingsDep,
) -> ProfilePhotoResponse:
    photo = await profile_photos.add_profile_photo(
        connection,
        storage,
        profile_id,
        account_id=account.account_id,
        image=image,
        max_size_bytes=settings.max_image_bytes,
    )
    logger.info("profile_photo_uploaded")
    return await to_profile_photo_response(photo, storage)


@router.get(
    "/profile-photos/{photo_id}",
    response_model=ProfilePhotoResponse,
    responses=_errors(401, 404, 422, 503),
)
async def read_profile_photo(
    photo_id: UUID,
    account: CurrentAccountDep,
    connection: DbConnectionDep,
    storage: ImageStorageDep,
) -> ProfilePhotoResponse:
    photo = await profile_photos.get_profile_photo(
        connection, photo_id, account_id=account.account_id
    )
    return await to_profile_photo_response(photo, storage)
