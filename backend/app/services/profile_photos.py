"""프로필 사진(`photos` 중 `session_id IS NULL`) (API 3-1, 3-2, 2-3의 `photos`).

사진 파일은 `ImageStorage`로 S3에 올리고, 행에는 객체 키만 둔다. 응답의 `imageUrl`은
라우트가 `storage.create_download`로 만든다. 면회 사진(`session_id` 있음)은 같은 테이블에
있지만 여기서 다루지 않는다.

업로드 순서는 검증 → 객체 키 → S3 업로드 → 행 저장이다. S3 업로드 동안 프로필 행을 잠가
두지 않도록, 장수 상한은 올리기 전에 한 번 세어 일찍 거절하고 행을 넣을 때 프로필 행을
잠근 뒤 다시 센다. 행을 넣지 못하면 올린 객체를 지우고, 지우지도 못하면 S3 삭제
대기열(`storage_deletion_request_queue`)에 넣는다.

넣은 행은 `analysis_status = 'pending'`이며 사진 분석 worker(8-4)가 가져간다.
"""

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal
from uuid import UUID, uuid4

from fastapi import UploadFile

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services import ownership
from app.services.image_storage import ImageStorage
from app.services.image_validation import validate_image

logger = logging.getLogger("saerok.profile_photos")

# 프로필당 사진 수. 면회 사진은 세지 않는다. DB 제약이 없어 서버가 확인한다.
PHOTO_LIMIT = 5

AnalysisStatus = Literal["pending", "processing", "completed", "failed"]


@dataclass(frozen=True)
class ProfilePhoto:
    photo_id: UUID
    profile_id: UUID
    object_key: str
    analysis_status: AnalysisStatus
    description: str | None
    error_code: str | None
    created_at: datetime


_COLUMNS = (
    "photo_id, profile_id, s3_object_key, analysis_status, description, "
    "error_code, created_at"
)


async def list_profile_photos(
    connection: DbConnection, *, profile_id: UUID
) -> list[ProfilePhoto]:
    """프로필 사진을 올린 순서대로 돌려준다. 소유 확인은 부르는 쪽이 한다."""
    cursor = await connection.execute(
        f"SELECT {_COLUMNS} FROM photos "
        "WHERE profile_id = %s AND session_id IS NULL "
        "ORDER BY created_at, photo_id",
        (profile_id,),
    )
    return [_to_photo(row) for row in await cursor.fetchall()]


async def add_profile_photo(
    connection: DbConnection,
    storage: ImageStorage,
    profile_id: UUID,
    *,
    account_id: str,
    image: UploadFile,
    max_size_bytes: int,
) -> ProfilePhoto:
    """사진 한 장을 S3에 올리고 분석 대기(`pending`) 행으로 저장한다(API 3-1)."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    validated = await validate_image(image, max_size_bytes=max_size_bytes)
    # 상한을 넘은 요청이 큰 파일을 S3에 올린 뒤에야 거절되지 않도록 먼저 센다.
    if await _count_profile_photos(connection, profile_id) >= PHOTO_LIMIT:
        raise _limit_exceeded()

    photo_id = uuid4()
    object_key = storage.object_key(photo_id=photo_id, image=validated)
    await storage.upload(object_key=object_key, file=image.file, image=validated)

    try:
        async with connection.transaction():
            # 같은 프로필의 동시 업로드가 함께 세어 상한을 넘기지 않도록 프로필 행을 잠근다.
            cursor = await connection.execute(
                "SELECT 1 FROM profiles WHERE profile_id = %s FOR UPDATE",
                (profile_id,),
            )
            if await cursor.fetchone() is None:
                # 소유 확인 뒤 같은 계정의 다른 요청이 프로필을 지운 경우다.
                raise _profile_not_found()
            if await _count_profile_photos(connection, profile_id) >= PHOTO_LIMIT:
                raise _limit_exceeded()
            cursor = await connection.execute(
                "INSERT INTO photos (photo_id, profile_id, s3_object_key) "
                f"VALUES (%s, %s, %s) RETURNING {_COLUMNS}",
                (photo_id, profile_id, object_key),
            )
            row = await cursor.fetchone()
    except BaseException:
        await _discard_upload(connection, storage, object_key)
        raise
    return _to_photo(row)


async def get_profile_photo(
    connection: DbConnection, photo_id: UUID, *, account_id: str
) -> ProfilePhoto:
    """프로필 사진 한 장을 돌려준다(API 3-2). 면회 사진은 없는 사진과 같은 404다."""
    await ownership.require_owned(
        connection, ownership.PROFILE_PHOTO, photo_id, account_id=account_id
    )
    cursor = await connection.execute(
        f"SELECT {_COLUMNS} FROM photos WHERE photo_id = %s AND session_id IS NULL",
        (photo_id,),
    )
    row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 같은 계정의 다른 요청이 사진이나 프로필을 지운 경우다.
        raise AppError(
            status_code=404,
            error_code=ownership.PROFILE_PHOTO.error_code,
            message=ownership.PROFILE_PHOTO.message,
        )
    return _to_photo(row)


async def _count_profile_photos(connection: DbConnection, profile_id: UUID) -> int:
    cursor = await connection.execute(
        "SELECT count(*) AS n FROM photos "
        "WHERE profile_id = %s AND session_id IS NULL",
        (profile_id,),
    )
    return (await cursor.fetchone())["n"]


async def _discard_upload(
    connection: DbConnection, storage: ImageStorage, object_key: str
) -> None:
    """행을 넣지 못한 사진의 S3 객체를 지운다. 객체 키는 로그에 남기지 않는다."""
    try:
        await storage.delete(object_key=object_key)
        return
    except AppError:
        pass
    # 지우지 못한 객체는 행이 없어 trigger도 대기열에 넣지 않으므로 직접 넣는다.
    try:
        await connection.execute(
            "INSERT INTO storage_deletion_request_queue (s3_object_key) "
            "VALUES (%s) ON CONFLICT DO NOTHING",
            (object_key,),
        )
    except Exception:
        logger.error("profile_photo_upload_orphaned")
    else:
        logger.warning("profile_photo_upload_queued_for_deletion")


def _to_photo(row: dict[str, Any]) -> ProfilePhoto:
    return ProfilePhoto(
        photo_id=row["photo_id"],
        profile_id=row["profile_id"],
        object_key=row["s3_object_key"],
        analysis_status=row["analysis_status"],
        description=row["description"],
        error_code=row["error_code"],
        created_at=row["created_at"],
    )


def _limit_exceeded() -> AppError:
    return AppError(
        status_code=409,
        error_code="PHOTO_LIMIT_EXCEEDED",
        message=f"사진은 {PHOTO_LIMIT}장까지 올릴 수 있습니다.",
    )


def _profile_not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code=ownership.PROFILE.error_code,
        message=ownership.PROFILE.message,
    )
