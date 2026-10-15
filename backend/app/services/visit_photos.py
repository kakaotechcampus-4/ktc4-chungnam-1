"""면회 사진(`photos` 중 `session_id` 있음) 업로드(5-2).

회차당 한 장(`uq_photos_session`)이고, 다시 올리면 기존 행을 지우고 새 행을 넣는다. 지운
행의 객체 키는 trigger가 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣는다. 면회
사진은 분석하지 않는다. `analysis_status`는 기본값 `pending`으로 남지만 사진 분석 대기열은
`session_id IS NULL`인 행만 가져간다.

업로드 순서는 3-1과 같은 검증 → 객체 키 → S3 업로드 → 행 저장이다. S3 업로드 동안 회차
행을 잠가 두지 않도록 평가 여부는 올리기 전에 한 번 확인해 일찍 거절하고, 행을 넣을 때
회차 행을 잠근 뒤 다시 확인한다. 행을 넣지 못하면 올린 객체를 지우고, 지우지도 못하면 S3
삭제 대기열에 넣는다.
"""

import logging
from uuid import UUID, uuid4

from fastapi import UploadFile

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.visit_session import VisitPhoto
from app.services.image_storage import ImageStorage
from app.services.image_validation import validate_image
from app.services.ownership import VISIT_SESSION

logger = logging.getLogger("saerok.visit_photos")


async def replace_visit_photo(
    connection: DbConnection,
    storage: ImageStorage,
    session_id: UUID,
    *,
    image: UploadFile,
    max_size_bytes: int,
) -> VisitPhoto:
    """5-2. 사진 한 장을 S3에 올려 회차의 면회 사진으로 저장한다. 평가 전에만 받는다.

    회차 소유 확인은 부르는 쪽에서 `require_owned(VISIT_SESSION)`로 먼저 한다.
    """
    validated = await validate_image(image, max_size_bytes=max_size_bytes)
    # 평가를 마친 회차가 큰 파일을 S3에 올린 뒤에야 거절되지 않도록 먼저 확인한다.
    await _require_evaluation_pending(connection, session_id)

    photo_id = uuid4()
    object_key = storage.object_key(photo_id=photo_id, image=validated)
    await storage.upload(object_key=object_key, file=image.file, image=validated)

    try:
        async with connection.transaction():
            # 같은 회차의 동시 업로드와 평가 저장이 서로 겹치지 않게 회차 행을 잠근다.
            profile_id = await _require_evaluation_pending(
                connection, session_id, lock=True
            )
            await connection.execute(
                "DELETE FROM photos WHERE session_id = %s", (session_id,)
            )
            cursor = await connection.execute(
                "INSERT INTO photos (photo_id, profile_id, session_id, s3_object_key) "
                "VALUES (%s, %s, %s, %s) RETURNING created_at",
                (photo_id, profile_id, session_id, object_key),
            )
            created_at = (await cursor.fetchone())["created_at"]
    except BaseException:
        await _discard_upload(connection, storage, object_key)
        raise

    download = await storage.create_download(object_key=object_key)
    return VisitPhoto(
        photo_id=photo_id,
        session_id=session_id,
        image_url=download.url,
        image_url_expires_at=download.expires_at,
        created_at=created_at,
    )


async def _require_evaluation_pending(
    connection: DbConnection, session_id: UUID, *, lock: bool = False
) -> UUID:
    """평가 전 회차면 그 `profile_id`를, 아니면 409를 낸다."""
    cursor = await connection.execute(
        "SELECT profile_id, evaluated_at FROM visit_sessions WHERE session_id = %s"
        + (" FOR UPDATE" if lock else ""),
        (session_id,),
    )
    row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 같은 계정의 다른 요청이 프로필을 지운 경우다.
        raise AppError(
            status_code=404,
            error_code=VISIT_SESSION.error_code,
            message=VISIT_SESSION.message,
        )
    if row["evaluated_at"] is not None:
        raise AppError(
            status_code=409,
            error_code="INVALID_SESSION_STATE",
            message="평가를 마친 면회에는 사진을 올릴 수 없습니다.",
        )
    return row["profile_id"]


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
        logger.error("visit_photo_upload_orphaned")
    else:
        logger.warning("visit_photo_upload_queued_for_deletion")
