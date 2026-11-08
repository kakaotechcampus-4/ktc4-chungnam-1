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

# 정해진 시간이 지나도 worker가 가져가지 않았고, 그동안 worker가 다른 작업도 가져가지 않은
# 작업의 실패 코드. worker가 없거나 멈췄다.
NOT_STARTED_ERROR = "CARD_GENERATION_NOT_STARTED"


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

    async def expire_stuck(
        self, connection: DbConnection, profile_id: UUID, *, start_timeout_seconds: int
    ) -> int:
        """프로필에서 더는 끝나지 않을 작업을 실패로 정리하고 정리한 수를 돌려준다.

        `expire_leases`는 worker 루프 안에서만 돌아서, worker가 없으면 작업이 계속
        `running`으로 남는다. 4-1과 4-2가 상태를 보기 전에 불러 다음 두 작업을 정리한다.

        - 임대 없이 `start_timeout_seconds`가 지났고, 그 시간 동안 worker가 어떤 작업도
          가져가지 않았으며 임대가 남은 작업도 없다: 가져갈 worker가 없거나 멈췄다
        - 임대가 만료된 작업: 가져간 worker가 멈췄다

        worker 하나가 다른 계정의 작업을 차례로 처리하는 동안에는 오래 기다린 작업도 실패시키지
        않는다. worker는 작업 하나를 임대 시간 안에 끝내고 바로 다음 작업을 가져가므로, 임대
        시간보다 긴 `start_timeout_seconds` 안에 가져간 작업(`claimed_at`)이 있거나 임대가 남은
        작업이 있으면 worker가 일하고 있다.

        worker가 먼저 가져간 작업은 임대가 남아 있어 건드리지 않는다. 여기서 실패로 바꾼
        작업은 `claim`이 `running`만 고르므로 worker가 가져가지 않는다.
        """
        cursor = await connection.execute(
            """
            UPDATE card_sets
               SET status = 'failed',
                   error_code = CASE WHEN lease_expires_at IS NULL THEN %(not_started)s
                                     ELSE %(lease_expired)s END,
                   lease_expires_at = NULL,
                   generation_log = jsonb_build_object('input', NULL)
             WHERE profile_id = %(profile_id)s AND status = 'running'
               AND (
                    (lease_expires_at IS NULL
                     AND created_at <= now() - (%(timeout)s * interval '1 second')
                     AND NOT EXISTS (
                         SELECT 1 FROM card_sets AS progress
                          WHERE progress.claimed_at > now() - (%(timeout)s * interval '1 second')
                             OR progress.lease_expires_at > now()
                     ))
                    OR lease_expires_at <= now()
               )
            """,
            {
                "not_started": NOT_STARTED_ERROR,
                "lease_expired": LEASE_EXPIRED_ERROR,
                "profile_id": profile_id,
                "timeout": start_timeout_seconds,
            },
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
                   claimed_at = now(),
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
