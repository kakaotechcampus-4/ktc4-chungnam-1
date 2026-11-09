"""사진 업로드(3-1, 5-2)의 S3 객체를 삭제 대기열로 추적한다.

S3에 올리기 전에 객체 키를 `storage_deletion_request_queue`에 먼저 넣는다. 짧은 음성 전사와
같은 방식이다. `not_before`를 업로드와 행 저장이 끝날 시간보다 넉넉히 뒤로 두므로 그동안
삭제 실행기는 이 요청을 건너뛴다. 사진 행을 넣는 트랜잭션에서 이 기록을 지우고, 그 뒤의
삭제는 기존 `photos` trigger가 맡는다.

업로드 뒤 행을 넣기 전에 프로세스가 끝나면 기록이 남는다. 기한이 지나면 삭제 실행기가 행이
없는 객체로 보고 지운다. 사진 행이 없어 사진 삭제와 탈퇴가 닿지 않는 객체를 남기지 않기
위해서다.
"""

import logging

from app.core.database import DbConnection
from app.services.image_storage import ImageStorage

logger = logging.getLogger("saerok.photo_uploads")

# 업로드(기본 상한 20MB)와 행 저장에 걸리는 시간보다 충분히 길게 둔다. 이보다 오래 걸린
# 업로드는 실행기가 먼저 지울 수 있다. 행을 넣었다면 같은 트랜잭션에서 기록을 지웠다.
CLEANUP_DELAY_SECONDS = 60 * 60


async def reserve_cleanup(connection: DbConnection, object_key: str) -> None:
    """업로드 전에 부른다. 기록하지 못하면 예외가 나므로 올리지 않는다."""
    await connection.execute(
        "INSERT INTO storage_deletion_request_queue (s3_object_key, not_before) "
        "VALUES (%s, now() + %s * interval '1 second')",
        (object_key, CLEANUP_DELAY_SECONDS),
    )


async def release_cleanup(connection: DbConnection, object_key: str) -> None:
    """사진 행을 넣는 트랜잭션 안에서 부른다. 행과 기록 중 하나만 남지 않게 한다."""
    await connection.execute(
        "DELETE FROM storage_deletion_request_queue WHERE s3_object_key = %s",
        (object_key,),
    )


async def discard(
    connection: DbConnection, storage: ImageStorage, object_key: str
) -> None:
    """행을 넣지 못한 사진의 객체를 지운다. 객체 키와 예외 본문은 로그에 남기지 않는다.

    업로드 호출이 끝난 뒤에만 부른다. 요청 취소로 업로드가 아직 진행 중일 수 있으면 부르지
    않고, 미리 넣은 기록을 기한까지 둔다. 먼저 지우면 객체가 뒤늦게 다시 생길 수 있다.

    삭제 요청은 지운 뒤에도 남긴다. 사진 버킷에 버전 관리가 켜져 있으면 `DeleteObject`가
    삭제 표시만 만들 수 있으므로, 삭제 확인은 실행기의 버전 관리 확인과 HEAD 404에 맡긴다.
    """
    try:
        # 기한을 기다리지 않고 다음 실행에서 처리하도록 앞당긴다. 기록이 없으면 새로 넣는다.
        await connection.execute(
            "INSERT INTO storage_deletion_request_queue (s3_object_key) VALUES (%s) "
            "ON CONFLICT (s3_object_key) DO UPDATE SET not_before = LEAST("
            "storage_deletion_request_queue.not_before, EXCLUDED.not_before)",
            (object_key,),
        )
    except Exception:
        # 미리 넣은 기록이 남아 있으면 처음 정한 기한 뒤에 처리된다.
        logger.warning("photo_upload_cleanup_schedule_failed")
    try:
        await storage.delete(object_key=object_key)
    except Exception:
        logger.warning("photo_upload_deletion_pending")
