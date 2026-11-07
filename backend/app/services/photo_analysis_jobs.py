"""프로필 사진 분석 작업(`photos`) 대기열.

`pending`인 프로필 사진(`session_id IS NULL`)을 `processing`으로 임대해 가져온다. 면회
사진도 `pending`으로 남지만 분석하지 않으므로 가져가지 않는다. 이 모듈은 작업을
가져오고 실패를 기록하는 일만 한다. 8-4 호출, 응답 검증과 결과 저장은 처리 함수(작업
A)가 한다. 결과를 저장할 때는 `analysis_status = 'completed'`, `description`, `model`,
`prompt_version`과 함께 `lease_expires_at = NULL`로 바꾼다(CHECK `photos_lease_check`).

합성 데이터용 worker를 연결했다. 실제 사용자 자료에서는 계정의 사진 분석 동의 조건을
조회하고 철회 여부를 저장 직전에 다시 검사하는 연결이 필요하다. 현재 실행 진입점은
운영 환경 실행을 거절한다. 이 제한을 동의 없이 분석해도 된다는 뜻으로 바꾸지 않는다.
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from app.core.database import DbConnection
from app.workers.base import LEASE_EXPIRED_ERROR


@dataclass(frozen=True)
class PhotoAnalysisJob:
    photo_id: UUID
    profile_id: UUID
    s3_object_key: str
    attempt_count: int


class PhotoAnalysisQueue:
    name = "photo_analysis"
    unexpected_error_code = "IMAGE_ANALYSIS_FAILED"

    async def expire_leases(self, connection: DbConnection) -> int:
        cursor = await connection.execute(
            """
            UPDATE photos
               SET analysis_status = 'failed', error_code = %s, lease_expires_at = NULL
             WHERE analysis_status = 'processing' AND lease_expires_at <= now()
            """,
            (LEASE_EXPIRED_ERROR,),
        )
        return cursor.rowcount

    async def claim(
        self, connection: DbConnection, *, lease_seconds: int
    ) -> PhotoAnalysisJob | None:
        cursor = await connection.execute(
            """
            WITH candidate AS (
                SELECT photo_id FROM photos
                 WHERE analysis_status = 'pending' AND session_id IS NULL
                 ORDER BY created_at
                 FOR UPDATE SKIP LOCKED
                 LIMIT 1
            )
            UPDATE photos AS photo
               SET analysis_status = 'processing',
                   lease_expires_at = now() + (%s * interval '1 second'),
                   attempt_count = attempt_count + 1
              FROM candidate
             WHERE photo.photo_id = candidate.photo_id
            RETURNING photo.photo_id, photo.profile_id, photo.s3_object_key,
                      photo.attempt_count
            """,
            (lease_seconds,),
        )
        row = await cursor.fetchone()
        return PhotoAnalysisJob(**row) if row else None

    async def fail(
        self, connection: DbConnection, job: PhotoAnalysisJob, *, error_code: str
    ) -> None:
        await connection.execute(
            """
            UPDATE photos
               SET analysis_status = 'failed', error_code = %s, lease_expires_at = NULL
             WHERE photo_id = %s AND analysis_status = 'processing' AND attempt_count = %s
            """,
            (error_code, job.photo_id, job.attempt_count),
        )
