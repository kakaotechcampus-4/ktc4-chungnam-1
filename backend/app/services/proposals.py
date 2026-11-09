"""변경 제안 조회와 확인 (API 7-3, 7-4).

제안은 리포트 생성기(8-3)가 `pending`으로 만든다. 보호자가 확인하면(7-4) 모두
`settled`로 바꾸고, 승인한 생애 정보 제안은 생애 정보로, 승인한 주제 제안은
`topic_feedback`으로 남긴다. DB에는 `pending`과 `settled`만 저장하므로 응답의
`accepted`, `rejected`는 승인 결과(생애 정보 또는 주제 피드백)가 있는지로 정한다.
제안 값(`title`, `content`, `reason`, `story_category`, `sensitive`, `suggested_action`)은 확인
뒤에도 바꾸지 않는다.

생애 정보 제안에는 AI가 고른 일대기 분류(`story_category`)와 아픈 기억일 수 있다는
표시(`sensitive`)가 있다(2026-11-09 PM 결정, #139). 승인한 이야기는 보호자가 7-4에서 고른
분류로, 고르지 않았으면 제안의 분류로 만든다. 그림 번호는 서버가 고른다.

승인한 주제 피드백(`more`, `less`, `exclude`)은 다음 카드 생성(4-1)에서 주제를 고르는 기준을
바꾼다. 그래서 주제 제안을 하나라도 승인하면 2-4, 2-7, 2-9처럼 카드를 만드는 중에는 거절하고,
아직 면회에 안 쓴 완료 묶음은 다시 만들어야 하는 묶음으로 바꾼다(`card_sets.mark_stale`).
생애 정보 제안 승인은 이야기 추가(2-6)와 같아서 둘 다 하지 않고 다음 생성부터 반영한다.
모두 거절한 확인도 둘 다 하지 않는다.
"""

from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.reports import (
    ChangeProposal,
    LifeFactProposal,
    ProposalReviewRequest,
    ProposalTopic,
    TopicProposal,
)
from app.services import card_sets, ownership
from app.services.life_facts import create_life_fact
from app.services.reports import report_not_found


async def get_proposals(
    connection: DbConnection, session_id: UUID, *, account_id: str
) -> ChangeProposal:
    """7-3. 리포트 저장 전이면 404 `REPORT_NOT_FOUND`다."""
    await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    await _require_report(connection, session_id, lock=False)
    return await _load_proposals(connection, session_id)


async def review_proposals(
    connection: DbConnection,
    session_id: UUID,
    *,
    account_id: str,
    payload: ProposalReviewRequest,
    start_timeout_seconds: int,
) -> ChangeProposal:
    """7-4. 회차의 `pending` 제안을 한 트랜잭션에서 모두 확인한다.

    주제 제안 승인이 하나라도 있으면 카드를 만드는 중일 때 409 `CARD_GENERATION_IN_PROGRESS`로
    거절하고 아무것도 저장하지 않는다. 생애 정보만 승인한 확인은 2-6처럼 거절하지 않는다. 확인 여부(409 `PROPOSAL_ALREADY_REVIEWED`)와
    요청 검사(422 `INVALID_PROPOSAL_REVIEW`)가 먼저다.

    승인한 생애 정보를 더해 프로필의 이야기가 `life_facts.LIFE_FACT_LIMIT`개를 넘으면
    `create_life_fact`가 409 `LIFE_FACT_LIMIT_EXCEEDED`로 거절하고, 같은 트랜잭션이라 제안 정리와
    주제 피드백도 저장하지 않는다. 내용 길이(5,000자)는 요청 검증(`LifeFactReview`)이 2-6과 같이
    422 `INVALID_REQUEST`로 막는다.
    """
    profile_id = await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    async with connection.transaction():
        # 리포트 저장(8-3)은 회차 행을 고친 뒤 이 프로필을 참조하는 제안을 넣는다. 저장 중에
        # 이 요청이 프로필을 먼저 잠그면 서로 기다리다 멈출 수 있어 리포트부터 확인한다.
        await _require_report(connection, session_id, lock=False)
        # 2-8, 4-1, 5-1처럼 프로필을 먼저 잠근다. 같은 회차의 확인이 동시에 들어와도 한 번만
        # 처리되게 회차 행도 잠근다.
        await card_sets.lock_profile(connection, profile_id)
        await _require_report(connection, session_id, lock=True)
        cursor = await connection.execute(
            "SELECT proposal_id, status, story_category FROM life_fact_proposals "
            "WHERE session_id = %s",
            (session_id,),
        )
        life_rows = await cursor.fetchall()
        cursor = await connection.execute(
            "SELECT proposal_id, topic_id, status FROM topic_proposals "
            "WHERE session_id = %s",
            (session_id,),
        )
        topic_rows = await cursor.fetchall()

        # 확인은 회차의 제안을 한꺼번에 settled로 바꾸므로, settled가 하나라도
        # 있으면 이미 확인한 회차다.
        if any(row["status"] == "settled" for row in [*life_rows, *topic_rows]):
            raise AppError(
                status_code=409,
                error_code="PROPOSAL_ALREADY_REVIEWED",
                message="이미 확인한 변경 제안입니다.",
            )
        _require_all_pending(
            [review.proposal_id for review in payload.life_facts],
            {row["proposal_id"] for row in life_rows},
        )
        _require_all_pending(
            [review.proposal_id for review in payload.topics],
            {row["proposal_id"] for row in topic_rows},
        )

        accepted_facts = [r for r in payload.life_facts if r.review_status == "accepted"]
        accepted_topics = [r for r in payload.topics if r.review_status == "accepted"]
        if accepted_topics:
            await card_sets.mark_stale(
                connection, profile_id, start_timeout_seconds=start_timeout_seconds
            )

        await connection.execute(
            "UPDATE life_fact_proposals SET status = 'settled' "
            "WHERE session_id = %s AND status = 'pending'",
            (session_id,),
        )
        await connection.execute(
            "UPDATE topic_proposals SET status = 'settled' "
            "WHERE session_id = %s AND status = 'pending'",
            (session_id,),
        )
        proposed_categories = {row["proposal_id"]: row["story_category"] for row in life_rows}
        for review in accepted_facts:
            await create_life_fact(
                connection,
                profile_id=profile_id,
                title=review.title,
                content=review.content,
                source_proposal_id=review.proposal_id,
                # 보호자가 고른 분류가 없으면 AI가 고른 제안의 분류다.
                story_category=review.story_category
                or proposed_categories[review.proposal_id],
            )
        topic_ids = {row["proposal_id"]: row["topic_id"] for row in topic_rows}
        for review in accepted_topics:
            await connection.execute(
                "INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action) "
                "VALUES (%s, %s, %s, %s)",
                (
                    profile_id,
                    topic_ids[review.proposal_id],
                    review.proposal_id,
                    review.action,
                ),
            )
    return await _load_proposals(connection, session_id)


def _require_all_pending(requested: list[UUID], pending: set[UUID]) -> None:
    """요청이 회차의 `pending` 제안과 정확히 같은지 확인한다(빠짐, 다른 회차, 중복)."""
    if len(set(requested)) != len(requested) or set(requested) != pending:
        raise AppError(
            status_code=422,
            error_code="INVALID_PROPOSAL_REVIEW",
            message="이 면회의 확인하지 않은 변경 제안을 모두 담아야 합니다.",
        )


async def _require_report(
    connection: DbConnection, session_id: UUID, *, lock: bool
) -> None:
    query = "SELECT report_generated_at FROM visit_sessions WHERE session_id = %s"
    cursor = await connection.execute(
        query + " FOR UPDATE" if lock else query, (session_id,)
    )
    row = await cursor.fetchone()
    if row is None or row["report_generated_at"] is None:
        raise report_not_found()


async def _load_proposals(
    connection: DbConnection, session_id: UUID
) -> ChangeProposal:
    cursor = await connection.execute(
        "SELECT p.proposal_id, p.title, p.content, p.reason, p.story_category, p.sensitive, "
        "CASE WHEN p.status = 'pending' THEN 'pending' "
        "     WHEN EXISTS (SELECT 1 FROM life_facts f "
        "                   WHERE f.source_proposal_id = p.proposal_id) THEN 'accepted' "
        "     ELSE 'rejected' END AS review_status "
        "FROM life_fact_proposals p WHERE p.session_id = %s "
        "ORDER BY p.created_at, p.proposal_id",
        (session_id,),
    )
    life_facts = [LifeFactProposal(**row) for row in await cursor.fetchall()]
    cursor = await connection.execute(
        "SELECT p.proposal_id, p.card_id, p.topic_id, t.title AS topic_title, "
        "t.description AS topic_description, p.suggested_action, p.reason, "
        "CASE WHEN p.status = 'pending' THEN 'pending' "
        "     WHEN EXISTS (SELECT 1 FROM topic_feedback f "
        "                   WHERE f.proposal_id = p.proposal_id) THEN 'accepted' "
        "     ELSE 'rejected' END AS review_status "
        "FROM topic_proposals p "
        "JOIN profile_topics t ON t.topic_id = p.topic_id "
        "JOIN conversation_cards c ON c.card_id = p.card_id "
        "WHERE p.session_id = %s ORDER BY c.position",
        (session_id,),
    )
    topics = [
        TopicProposal(
            proposal_id=row["proposal_id"],
            card_id=row["card_id"],
            topic=ProposalTopic(
                topic_id=row["topic_id"],
                title=row["topic_title"],
                description=row["topic_description"],
            ),
            suggested_action=row["suggested_action"],
            reason=row["reason"],
            review_status=row["review_status"],
        )
        for row in await cursor.fetchall()
    ]
    return ChangeProposal(
        session_id=session_id, life_fact_proposals=life_facts, topic_proposals=topics
    )
