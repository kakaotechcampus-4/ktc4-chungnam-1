"""첫 카드의 사진 대기. worker와 DB 연결을 붙잡지 않고 작업 행으로 이어받는다."""
from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.card_generation import PhotoPreparation


async def advance_ready(connection: DbConnection, profile_id: UUID | None = None) -> None:
    """준비된 작업만 카드 대기열로 보낸다. 앱의 조회 없이 worker에서도 부른다."""
    await connection.execute(
        """
        UPDATE card_sets s SET photo_wait_until=NULL, photo_ready_at=clock_timestamp()
        WHERE s.status='running' AND s.photo_wait_until IS NOT NULL
          AND (%(profile)s::uuid IS NULL OR s.profile_id=%(profile)s)
          AND NOT EXISTS (
            SELECT 1 FROM photos p
            WHERE p.photo_id=ANY(s.photo_wait_ids) AND p.profile_id=s.profile_id
              AND p.user_description IS NULL
              AND NOT (p.analysis_status='completed' AND EXISTS (
                SELECT 1 FROM profiles pr JOIN current_consents c USING(user_id)
                WHERE pr.profile_id=s.profile_id AND c.photo_analysis)))
        """,
        {"profile": profile_id},
    )


async def progress(connection: DbConnection, set_id: UUID) -> PhotoPreparation | None:
    row = await (await connection.execute(
        """
        SELECT s.set_id, s.photo_wait_until <= clock_timestamp() AS timed_out,
          coalesce(bool_or(c.photo_analysis),false) AS consent,
          count(p.photo_id) AS total,
          count(p.photo_id) FILTER (WHERE p.user_description IS NOT NULL
            OR (p.analysis_status='completed' AND c.photo_analysis)) AS completed,
          count(p.photo_id) FILTER (WHERE p.user_description IS NULL AND
            (p.analysis_status='failed' OR
             (p.analysis_status='processing' AND p.lease_expires_at <= clock_timestamp()))) AS failed
        FROM card_sets s
        JOIN profiles pr USING(profile_id)
        LEFT JOIN current_consents c USING(user_id)
        LEFT JOIN photos p ON p.photo_id=ANY(s.photo_wait_ids) AND p.profile_id=s.profile_id
        WHERE s.set_id=%s AND s.status='running' AND s.photo_wait_until IS NOT NULL
        GROUP BY s.set_id
        """, (set_id,),
    )).fetchone()
    if row is None:
        return None
    reason = (
        "consentRequired" if not row["consent"] else
        "analysisFailed" if row["failed"] else
        "timedOut" if row["timed_out"] else None
    )
    return PhotoPreparation(
        set_id=set_id, state="choice" if reason else "waiting",
        total=row["total"], completed=row["completed"], failed=row["failed"],
        pending=row["total"]-row["completed"]-row["failed"], reason=reason,
    )


async def choose(
    connection: DbConnection, profile_id: UUID, set_id: UUID, action: str,
    *, timeout_seconds: int,
) -> None:
    # 프로필, 카드 묶음, 사진 순으로 잠근다. 오래된 화면에서 다른 작업을 바꾸지 않는다.
    async with connection.transaction():
        await connection.execute("SELECT 1 FROM profiles WHERE profile_id=%s FOR UPDATE", (profile_id,))
        row = await (await connection.execute(
            "SELECT photo_wait_ids FROM card_sets WHERE set_id=%s AND profile_id=%s "
            "AND status='running' AND photo_wait_until IS NOT NULL "
            "AND lease_expires_at IS NULL FOR UPDATE", (set_id, profile_id),
        )).fetchone()
        state = await progress(connection, set_id) if row else None
        if state is None or state.state != "choice":
            raise AppError(status_code=409, error_code="PHOTO_PREPARATION_CHANGED",
                           message="사진 준비 상태가 바뀌었습니다. 다시 확인해 주세요.")
        if action == "continue":
            await connection.execute(
                "UPDATE card_sets SET photo_wait_until=NULL, photo_ready_at=clock_timestamp() "
                "WHERE set_id=%s", (set_id,),
            )
            return
        if state.reason == "consentRequired":
            raise AppError(status_code=409, error_code="PHOTO_ANALYSIS_CONSENT_REQUIRED",
                           message="설정에서 AI 사진 분석 동의를 확인해 주세요.")
        # 살아 있는 분석은 중복 호출하지 않는다. 다음 claim은 attempt_count를 올려 늦은 결과를 막는다.
        await connection.execute(
            "UPDATE photos SET analysis_status='pending', error_code=NULL, lease_expires_at=NULL "
            "WHERE profile_id=%s AND photo_id=ANY(%s) AND user_description IS NULL "
            "AND (analysis_status='failed' OR (analysis_status='processing' "
            "AND lease_expires_at <= clock_timestamp()))", (profile_id, row["photo_wait_ids"]),
        )
        await connection.execute(
            "UPDATE card_sets SET photo_wait_until=clock_timestamp()+(%s * interval '1 second') "
            "WHERE set_id=%s", (timeout_seconds, set_id),
        )
