"""카드 생성 작업(`card_sets`) 대기열.

`running` 중에서 임대가 없는 작업이 대기 중인 작업이다. 이 모듈은 작업을 가져오고
실패를 기록하는 일만 한다. 8-2 요청 조립, AI 호출, 응답 검증과 결과 저장은 처리
함수(작업 B)가 한다. 결과를 저장할 때는 `status = 'completed'`와 함께
`lease_expires_at = NULL`로 바꾼다(CHECK `card_sets_lease_check`).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from uuid import UUID

from psycopg.types.json import Jsonb

from app.core.database import DbConnection
from app.workers.base import LEASE_EXPIRED_ERROR


@dataclass(frozen=True)
class CardGenerationJob:
    set_id: UUID
    profile_id: UUID
    attempt_count: int


class CardGenerationQueue:
    name = "card_generation"
    unexpected_error_code = "CARD_GENERATION_FAILED"

    async def expire_leases(self, connection: DbConnection) -> int:
        cursor = await connection.execute(
            """
            UPDATE card_sets
               SET status = 'failed', error_code = %s, lease_expires_at = NULL,
                   generation_log = jsonb_build_object('input', NULL)
             WHERE status = 'running' AND lease_expires_at <= now()
            """,
            (LEASE_EXPIRED_ERROR,),
        )
        return cursor.rowcount

    async def claim(
        self, connection: DbConnection, *, lease_seconds: int
    ) -> CardGenerationJob | None:
        cursor = await connection.execute(
            """
            WITH candidate AS (
                SELECT set_id FROM card_sets
                 WHERE status = 'running' AND lease_expires_at IS NULL
                 ORDER BY created_at
                 FOR UPDATE SKIP LOCKED
                 LIMIT 1
            )
            UPDATE card_sets AS card_set
               SET lease_expires_at = now() + (%s * interval '1 second'),
                   attempt_count = attempt_count + 1
              FROM candidate
             WHERE card_set.set_id = candidate.set_id
            RETURNING card_set.set_id, card_set.profile_id, card_set.attempt_count
            """,
            (lease_seconds,),
        )
        row = await cursor.fetchone()
        return CardGenerationJob(**row) if row else None

    async def fail(
        self,
        connection: DbConnection,
        job: CardGenerationJob,
        *,
        error_code: str,
        generation_input: dict[str, Any] | None = None,
    ) -> None:
        """작업을 실패로 끝낸다.

        실패한 작업에도 `generation_log`가 있어야 한다(CHECK). 처리 함수가 AI에 보낸
        요청을 남기려면 `generation_input`으로 넘기고 처리 함수에서 정상 반환한다.
        """
        await connection.execute(
            """
            UPDATE card_sets
               SET status = 'failed', error_code = %s, lease_expires_at = NULL,
                   generation_log = %s
             WHERE set_id = %s AND status = 'running'
            """,
            (error_code, Jsonb({"input": generation_input}), job.set_id),
        )
