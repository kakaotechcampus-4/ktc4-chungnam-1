"""리포트 목록과 리포트 조회 (API 7-1, 7-2).

리포트는 회차(`visit_sessions.report_*`)에 저장하며 리포트 생성기(8-3)가 쓴다.
`mood`는 저장하지 않고 만족도로 계산하고, `visitDate`는 `started_at`의 한국 시간
날짜다.
"""

from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.reports import (
    CardSummary,
    Mood,
    ReportPhoto,
    ReportSummary,
    VisitReport,
)
from app.services import ownership
from app.services.image_storage import ImageStorage


def mood_for(satisfaction: int) -> Mood:
    """만족도 1~2는 `hard`, 3은 `normal`, 4~5는 `good`이다."""
    if satisfaction <= 2:
        return "hard"
    if satisfaction == 3:
        return "normal"
    return "good"


def report_not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code="REPORT_NOT_FOUND",
        message="이 면회의 리포트가 아직 없습니다.",
    )


async def list_reports(
    connection: DbConnection, profile_id: UUID, *, account_id: str, limit: int
) -> list[ReportSummary]:
    """7-1. 리포트가 저장된 회차를 최근 면회(`started_at DESC`)부터 담는다."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    cursor = await connection.execute(
        "SELECT session_id, report_title, evaluation_satisfaction, "
        "(started_at AT TIME ZONE 'Asia/Seoul')::date AS visit_date "
        "FROM visit_sessions "
        "WHERE profile_id = %s AND report_generated_at IS NOT NULL "
        "ORDER BY started_at DESC, session_id LIMIT %s",
        (profile_id, limit),
    )
    return [
        ReportSummary(
            session_id=row["session_id"],
            title=row["report_title"],
            visit_date=row["visit_date"],
            mood=mood_for(row["evaluation_satisfaction"]),
        )
        for row in await cursor.fetchall()
    ]


async def get_report(
    connection: DbConnection,
    session_id: UUID,
    *,
    account_id: str,
    storage: ImageStorage,
) -> VisitReport:
    """7-2. 면회 사진이 있을 때만 사진 저장소에서 조회 URL을 만든다."""
    await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    cursor = await connection.execute(
        "SELECT report_title, report_body, report_generated_at, "
        "evaluation_satisfaction, "
        "(started_at AT TIME ZONE 'Asia/Seoul')::date AS visit_date "
        "FROM visit_sessions WHERE session_id = %s",
        (session_id,),
    )
    session = await cursor.fetchone()
    if session is None or session["report_generated_at"] is None:
        raise report_not_found()

    cursor = await connection.execute(
        "SELECT c.card_id, c.card_title, c.report_summary "
        "FROM conversation_cards c JOIN card_sets s ON s.set_id = c.set_id "
        "WHERE s.session_id = %s AND c.report_summary IS NOT NULL "
        "ORDER BY c.position",
        (session_id,),
    )
    summaries = [
        CardSummary(
            card_id=row["card_id"],
            card_title=row["card_title"],
            summary=row["report_summary"],
        )
        for row in await cursor.fetchall()
    ]

    cursor = await connection.execute(
        "SELECT photo_id, s3_object_key FROM photos WHERE session_id = %s",
        (session_id,),
    )
    photo_row = await cursor.fetchone()
    photo = None
    if photo_row is not None:
        download = await storage.create_download(
            object_key=photo_row["s3_object_key"]
        )
        photo = ReportPhoto(
            photo_id=photo_row["photo_id"],
            image_url=download.url,
            image_url_expires_at=download.expires_at,
        )

    return VisitReport(
        session_id=session_id,
        title=session["report_title"],
        body=session["report_body"],
        visit_date=session["visit_date"],
        mood=mood_for(session["evaluation_satisfaction"]),
        photo=photo,
        card_summaries=summaries,
        generated_at=session["report_generated_at"],
    )
