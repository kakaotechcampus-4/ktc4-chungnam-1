"""변경 제안 조회와 확인 (API 7-3, 7-4).

제안은 리포트 생성기(8-3)가 `pending`으로 만든다. 보호자가 확인하면(7-4) 모두
`settled`로 바꾸고, 승인한 생애 정보 제안은 생애 정보로, 승인한 주제 제안은
`topic_feedback`으로 남긴다. DB에는 `pending`과 `settled`만 저장하므로 응답의
`accepted`, `rejected`는 승인 결과(생애 정보 또는 주제 피드백)가 있는지로 정한다.
제안 값(`title`, `content`, `reason`, `suggested_action`)은 확인 뒤에도 바꾸지 않는다.
"""

import importlib.util
from collections.abc import Awaitable, Callable
from typing import Any
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
from app.services import ownership
from app.services.reports import report_not_found

# 작업 A(PR #105)의 생애 정보 모듈. 7-4에서 승인한 생애 정보 제안을 그 모듈의
# `create_life_fact`로 만든다.
LIFE_FACTS_MODULE = "app.services.life_facts"


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
) -> ChangeProposal:
    """7-4. 회차의 `pending` 제안을 한 트랜잭션에서 모두 확인한다."""
    profile_id = await ownership.require_owned(
        connection, ownership.VISIT_SESSION, session_id, account_id=account_id
    )
    async with connection.transaction():
        # 같은 회차의 확인이 동시에 들어와도 한 번만 처리되게 회차 행을 잠근다.
        await _require_report(connection, session_id, lock=True)
        cursor = await connection.execute(
            "SELECT proposal_id, status FROM life_fact_proposals "
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
        create_life_fact = _life_fact_creator() if accepted_facts else None

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
        if create_life_fact is not None:
            for review in accepted_facts:
                await create_life_fact(
                    connection,
                    profile_id=profile_id,
                    title=review.title,
                    content=review.content,
                    source_proposal_id=review.proposal_id,
                )
        topic_ids = {row["proposal_id"]: row["topic_id"] for row in topic_rows}
        for review in payload.topics:
            if review.review_status != "accepted":
                continue
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


def _life_fact_creator() -> Callable[..., Awaitable[Any]]:
    """작업 A의 `create_life_fact`를 가져온다.

    임시 가드: PR #105가 develop에 병합되기 전에는 `app.services.life_facts`가 없다.
    모듈 맨 위에서 가져오면 앱 전체가 뜨지 않으므로 여기서 가져오고, 없으면 DB를 쓰기
    전에 503 `LIFE_FACT_STORE_NOT_READY`로 명시적으로 거절한다. #105가 병합되면 맨 위
    import로 옮기고 이 함수와 오류 코드를 지운다.
    """
    if importlib.util.find_spec(LIFE_FACTS_MODULE) is None:
        raise AppError(
            status_code=503,
            error_code="LIFE_FACT_STORE_NOT_READY",
            message="생애 정보 저장 기능이 아직 준비되지 않았습니다.",
        )
    from app.services.life_facts import create_life_fact  # type: ignore[import-not-found]

    return create_life_fact


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
        "SELECT p.proposal_id, p.title, p.content, p.reason, "
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
