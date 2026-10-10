"""프로필 사진 분석 작업(`photos`) 대기열.

`pending`인 프로필 사진(`session_id IS NULL`)을 `processing`으로 임대해 가져온다. 면회
사진도 `pending`으로 남지만 분석하지 않으므로 가져가지 않는다. 이 모듈은 작업을
가져오고 실패를 기록하는 일만 한다. 8-4 호출, 응답 검증과 결과 저장은 처리 함수(작업
A)가 한다. 결과를 저장할 때는 `analysis_status = 'completed'`, `description`, `model`,
`prompt_version`과 함께 `lease_expires_at = NULL`로 바꾼다(CHECK `photos_lease_check`).

**사진 동의 설계 전에는 worker에 연결하지 않는다.** ADR-001의 2026-10-05 개정안은 사진
보관 동의와 AI 분석 동의를 나누고, 분석 동의를 확인하지 않은 사진으로 분석 작업을 만들지
못하게 한다. 지금은 `pending`인 프로필 사진을 모두 가져오므로, 분석 동의의 저장 위치와
"분석하지 않는 사진"의 상태가 정해지면 그 조건을 가져오기 조건에 더한 뒤 사용한다.
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
             WHERE photo_id = %s AND analysis_status = 'processing'
            """,
            (error_code, job.photo_id),
        )
