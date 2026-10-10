"""보호자 평가 저장과 조회 (API 6-1, 6-4).

평가는 회차의 `evaluation_*`, `evaluated_at`에, 카드별 평가는 선택 카드의
`review_reaction`에 저장한다. 쓰고 평가하면 그 값, 쓰지 않았으면 `notUsed`, 답하지
않은 카드는 `null`이다.
"""

from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.evaluation import (
    CardReview,
    CaregiverEvaluation,
    CaregiverEvaluationRequest,
)
from app.services import ownership


def _invalid_card_review(message: str) -> AppError:
    return AppError(status_code=422, error_code="INVALID_CARD_REVIEW", message=message)


def _check_card_reviews(reviews: list[CardReview], selected: set[UUID]) -> None:
    card_ids = [review.card_id for review in reviews]
    if len(set(card_ids)) != len(card_ids):
        raise _invalid_card_review("같은 카드를 두 번 평가할 수 없습니다.")
    if not set(card_ids) <= selected:
        raise _invalid_card_review("이 면회에서 고른 카드만 평가할 수 있습니다.")
    for review in reviews:
        if review.was_used != (review.caregiver_reaction is not None):
            raise _invalid_card_review(
                "쓴 카드에는 반응이 필요하고 쓰지 않은 카드에는 반응을 넣지 않습니다."
            )


async def submit_evaluation(
    connection: DbConnection,
    session_id: UUID,
    *,
    account_id: str,
    payload: CaregiverEvaluationRequest,
) -> CaregiverEvaluation:
    """6-1. 평가 전 회차에만 저장한다. 저장하면 회차는 `audioPending`이 된다."""
    await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    async with connection.transaction():
        # 같은 회차의 평가가 동시에 들어와도 한 번만 저장되게 회차 행을 잠근다.
        cursor = await connection.execute(
            "SELECT evaluated_at FROM visit_sessions WHERE session_id = %s FOR UPDATE",
            (session_id,),
        )
        session = await cursor.fetchone()
        if session is None:
            raise AppError(
                status_code=404,
                error_code=ownership.VISIT_SESSION.error_code,
                message=ownership.VISIT_SESSION.message,
            )
        if session["evaluated_at"] is not None:
            raise AppError(
                status_code=409,
                error_code="EVALUATION_ALREADY_SUBMITTED",
                message="이미 평가를 저장한 면회입니다.",
            )
        cursor = await connection.execute(
            "SELECT c.card_id FROM conversation_cards c "
            "JOIN card_sets s ON s.set_id = c.set_id "
            "WHERE s.session_id = %s AND c.selected",
            (session_id,),
        )
        selected = {row["card_id"] for row in await cursor.fetchall()}
        _check_card_reviews(payload.card_reviews, selected)

        await connection.execute(
            "UPDATE visit_sessions SET evaluation_satisfaction = %s, "
            "evaluation_reaction = %s, evaluation_note = %s, evaluated_at = now() "
            "WHERE session_id = %s",
            (
                payload.conversation_satisfaction,
                payload.care_recipient_reaction,
                payload.free_note,
                session_id,
            ),
        )
        for review in payload.card_reviews:
            await connection.execute(
                "UPDATE conversation_cards SET review_reaction = %s WHERE card_id = %s",
                (review.caregiver_reaction or "notUsed", review.card_id),
            )
    return await _load_evaluation(connection, session_id)


async def get_evaluation(
    connection: DbConnection, session_id: UUID, *, account_id: str
) -> CaregiverEvaluation:
    """6-4. 평가 전이면 404 `EVALUATION_NOT_FOUND`다."""
    await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    return await _load_evaluation(connection, session_id)


async def _load_evaluation(
    connection: DbConnection, session_id: UUID
) -> CaregiverEvaluation:
    cursor = await connection.execute(
        "SELECT evaluation_satisfaction, evaluation_reaction, evaluation_note, "
        "evaluated_at FROM visit_sessions WHERE session_id = %s",
        (session_id,),
    )
    session = await cursor.fetchone()
    if session is None or session["evaluated_at"] is None:
        raise AppError(
            status_code=404,
            error_code="EVALUATION_NOT_FOUND",
            message="이 면회의 평가가 없습니다.",
        )
    # 답하지 않은 카드(`review_reaction IS NULL`)는 넣지 않는다.
    cursor = await connection.execute(
        "SELECT c.card_id, c.review_reaction FROM conversation_cards c "
        "JOIN card_sets s ON s.set_id = c.set_id "
        "WHERE s.session_id = %s AND c.review_reaction IS NOT NULL "
        "ORDER BY c.position",
        (session_id,),
    )
    reviews = [
        CardReview(
            card_id=row["card_id"],
            was_used=row["review_reaction"] != "notUsed",
            caregiver_reaction=(
                None if row["review_reaction"] == "notUsed" else row["review_reaction"]
            ),
        )
        for row in await cursor.fetchall()
    ]
    return CaregiverEvaluation(
        session_id=session_id,
        conversation_satisfaction=session["evaluation_satisfaction"],
        care_recipient_reaction=session["evaluation_reaction"],
        card_reviews=reviews,
        free_note=session["evaluation_note"],
        evaluated_at=session["evaluated_at"],
    )
