"""면회 회차(`visit_sessions`) 저장소. 작업 B 담당 범위(5-1, 5-3)만 둠.

회차 상태 계산은 C의 `load_visit_session` 담당. 그 함수가 들어오기 전까지 5-1, 5-3 응답은
항상 평가 전이라 `sessionStatus = evaluationPending`, `participantCount`와 `analysisId`는 null
(작업 B 문서).
"""

from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.visit_session import VisitSession


def _invalid_selection(message: str) -> AppError:
    return AppError(status_code=422, error_code="INVALID_CARD_SELECTION", message=message)


def _already_used() -> AppError:
    return AppError(
        status_code=409, error_code="CARD_SET_ALREADY_USED", message="이미 면회에 쓴 카드 묶음입니다."
    )


async def load_visit_session(connection: DbConnection, session_id: UUID) -> VisitSession:
    """C의 `load_visit_session`이 들어오면 그걸로 바꿈. 평가 전 회차만 맞음."""
    cursor = await connection.execute(
        "SELECT v.session_id, v.profile_id, v.started_at, s.set_id,"
        "       (SELECT photo_id FROM photos p WHERE p.session_id = v.session_id) AS photo_id"
        "  FROM visit_sessions v JOIN card_sets s ON s.session_id = v.session_id"
        " WHERE v.session_id = %s",
        (session_id,),
    )
    row = await cursor.fetchone()
    cursor = await connection.execute(
        "SELECT card_id FROM conversation_cards WHERE set_id = %s AND selected ORDER BY position",
        (row["set_id"],),
    )
    return VisitSession(
        session_id=row["session_id"],
        profile_id=row["profile_id"],
        set_id=row["set_id"],
        selected_card_ids=[card["card_id"] for card in await cursor.fetchall()],
        session_status="evaluationPending",
        photo_id=row["photo_id"],
        participant_count=None,
        started_at=row["started_at"],
        analysis_id=None,
    )


async def create_visit_session(
    connection: DbConnection, set_id: UUID, card_ids: list[UUID]
) -> UUID:
    """5-1. 한 트랜잭션에서 회차 생성, 묶음 연결, 고른 카드 `selected` 표시.

    묶음 소유 확인은 부르는 쪽에서 `require_owned(CARD_SET)`로 먼저 함.
    """
    if len(set(card_ids)) != len(card_ids):
        raise _invalid_selection("같은 카드를 두 번 고를 수 없습니다.")
    async with connection.transaction():
        cursor = await connection.execute(
            "SELECT profile_id, status, session_id FROM card_sets WHERE set_id = %s FOR UPDATE",
            (set_id,),
        )
        card_set = await cursor.fetchone()
        if card_set["status"] != "completed":
            raise AppError(
                status_code=409,
                error_code="CARD_GENERATION_NOT_COMPLETED",
                message="카드가 아직 준비되지 않았습니다.",
            )
        if card_set["session_id"] is not None:
            raise _already_used()
        cursor = await connection.execute(
            "SELECT count(*) AS n FROM conversation_cards"
            " WHERE set_id = %s AND card_id = ANY(%s) AND position BETWEEN 1 AND 9",
            (set_id, card_ids),
        )
        if (await cursor.fetchone())["n"] != len(card_ids):
            raise _invalid_selection("고를 수 있는 카드는 이 묶음의 1~9번 카드입니다.")
        cursor = await connection.execute(
            "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
            (card_set["profile_id"],),
        )
        session_id = (await cursor.fetchone())["session_id"]
        await connection.execute(
            "UPDATE card_sets SET session_id = %s WHERE set_id = %s", (session_id, set_id)
        )
        await connection.execute(
            "UPDATE conversation_cards SET selected = true WHERE set_id = %s AND card_id = ANY(%s)",
            (set_id, card_ids),
        )
    return session_id
