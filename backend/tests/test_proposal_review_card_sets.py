"""변경 제안 확인(API 7-4)과 카드 묶음의 관계 검증.

승인한 생애 정보와 주제 피드백은 다음 카드 생성(4-1)의 입력이다. 그래서 승인이 있는
확인은 2-4, 2-7, 2-9처럼 카드를 만드는 중이면 `CARD_GENERATION_IN_PROGRESS`로 거절하고,
아직 면회에 안 쓴 완료 묶음은 `needsRefresh`로 바꾼다. 모두 거절한 확인은 둘 다 하지 않는다.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import connect
from tests.card_fixtures import card_set_in, completed_card_set, make_app, with_db
from tests.support import run
from tests.visit_records import Records


def _reported_with_proposals(records: Records):
    """리포트까지 받은 회차와 그 회차의 생애 정보 제안, 주제 제안 하나씩."""
    user_id, profile_id = records.account()
    visit = records.visit(profile_id)
    records.evaluate(visit)
    records.report(visit)
    fact = records.life_fact_proposal(visit)
    topic = records.topic_proposal(visit, 0, "more")
    return user_id, profile_id, visit, fact, topic


def _body(fact, topic, accept: str | None) -> dict:
    """`accept`가 `lifeFact`이면 생애 정보 제안을, 주제 행동이면 그 행동으로 주제 제안을
    승인한다. `None`이면 모두 거절한다."""
    life = {"proposalId": str(fact), "reviewStatus": "rejected"}
    chosen = {"proposalId": str(topic), "reviewStatus": "rejected"}
    if accept == "lifeFact":
        life = {**life, "reviewStatus": "accepted", "title": "합성 제목", "content": "합성 내용"}
    elif accept is not None:
        chosen = {**chosen, "reviewStatus": "accepted", "action": accept}
    return {"lifeFacts": [life], "topics": [chosen]}


def _review_path(visit) -> str:
    return f"/api/v1/visit-sessions/{visit.session_id}/proposals/review"


def _stale_at(records: Records, set_id):
    return records.scalar("SELECT stale_at FROM card_sets WHERE set_id = %s", (set_id,))


def _assert_nothing_reviewed(records: Records) -> None:
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 0
    assert records.scalar(
        "SELECT count(*) FROM life_fact_proposals WHERE status <> 'pending'"
    ) == 0
    assert records.scalar("SELECT count(*) FROM topic_proposals WHERE status <> 'pending'") == 0


# ── 카드를 만드는 중 ─────────────────────────────────────
@pytest.mark.parametrize("accept", ["lifeFact", "exclude"])
def test_review_with_an_approval_is_refused_while_cards_are_being_made(
    migrated_database_url, accept
):
    records = Records(migrated_database_url)
    user_id, profile_id, visit, fact, topic = _reported_with_proposals(records)
    running = with_db(migrated_database_url, lambda c: card_set_in(c, profile_id, "running"))
    body = _body(fact, topic, accept)

    refused = records.call(user_id, "POST", _review_path(visit), json=body)

    assert refused.status_code == 409
    assert refused.json()["errorCode"] == "CARD_GENERATION_IN_PROGRESS"
    _assert_nothing_reviewed(records)

    # 카드 생성이 끝나면(여기서는 실패) 같은 확인을 다시 보낼 수 있다.
    records.execute(
        "UPDATE card_sets SET status = 'failed', error_code = 'NOT_ENOUGH_TOPICS', "
        "generation_log = '{\"input\": null}' WHERE set_id = %s",
        (running,),
    )
    again = records.call(user_id, "POST", _review_path(visit), json=body)

    assert again.status_code == 200


def test_reject_only_review_is_allowed_while_cards_are_being_made(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id, visit, fact, topic = _reported_with_proposals(records)
    with_db(migrated_database_url, lambda c: card_set_in(c, profile_id, "running"))

    response = records.call(user_id, "POST", _review_path(visit), json=_body(fact, topic, None))

    assert response.status_code == 200
    assert {p["reviewStatus"] for p in response.json()["topicProposals"]} == {"rejected"}
    assert records.scalar("SELECT count(*) FROM life_facts") == 0
    assert records.scalar("SELECT count(*) FROM topic_feedback") == 0


def test_review_waits_for_a_card_generation_that_is_starting(migrated_database_url):
    """4-1이 프로필을 잠그고 `running` 작업을 넣는 동안 들어온 확인.

    확인은 프로필 잠금을 기다렸다가 `running`을 보고 거절해야 한다. 잠그지 않으면 생성
    작업이 확인 전 입력으로 카드를 만들고 그 묶음이 `needsRefresh` 없이 저장된다.
    """
    records = Records(migrated_database_url)
    user_id, profile_id, visit, fact, topic = _reported_with_proposals(records)
    app = make_app(migrated_database_url, user_id)

    async def scenario():
        transport = ASGITransport(app=app)
        async with (
            AsyncClient(transport=transport, base_url="http://testserver") as client,
            connect(migrated_database_url) as holder,
        ):
            sent = None
            try:
                async with holder.transaction():
                    await holder.execute(
                        "SELECT 1 FROM profiles WHERE profile_id = %s FOR UPDATE", (profile_id,)
                    )
                    sent = asyncio.create_task(
                        client.post(_review_path(visit), json=_body(fact, topic, "exclude"))
                    )
                    await _until_a_request_waits_for_lock(holder)
                    await card_set_in(holder, profile_id, "running")
            finally:
                # 중간에 실패해도 요청을 끝까지 기다려 시험 DB에 연결을 남기지 않는다.
                response = await sent if sent is not None else None
            return response

    response = run(scenario())

    assert response.status_code == 409
    assert response.json()["errorCode"] == "CARD_GENERATION_IN_PROGRESS"
    _assert_nothing_reviewed(records)


# ── 아직 면회에 안 쓴 묶음 ───────────────────────────────
@pytest.mark.parametrize("accept", ["lifeFact", "exclude"])
def test_approval_marks_the_unused_card_set(migrated_database_url, accept):
    records = Records(migrated_database_url)
    user_id, profile_id, visit, fact, topic = _reported_with_proposals(records)
    # 평가를 마친 뒤 다음 면회 카드를 먼저 받았다.
    next_set, _ = with_db(migrated_database_url, lambda c: completed_card_set(c, profile_id))

    response = records.call(user_id, "POST", _review_path(visit), json=_body(fact, topic, accept))

    assert response.status_code == 200
    assert _stale_at(records, next_set) is not None
    # 면회에 쓴 묶음은 지난 기록이라 표시하지 않는다.
    assert _stale_at(records, visit.set_id) is None
    status = records.call(
        user_id, "GET", f"/api/v1/profiles/{profile_id}/card-generations/status"
    ).json()
    assert status["status"] == "ready" and status["needsRefresh"] is True


def test_reject_only_review_keeps_the_unused_card_set(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id, visit, fact, topic = _reported_with_proposals(records)
    next_set, _ = with_db(migrated_database_url, lambda c: completed_card_set(c, profile_id))

    response = records.call(user_id, "POST", _review_path(visit), json=_body(fact, topic, None))

    assert response.status_code == 200
    assert _stale_at(records, next_set) is None
    status = records.call(
        user_id, "GET", f"/api/v1/profiles/{profile_id}/card-generations/status"
    ).json()
    assert status["status"] == "ready" and status["needsRefresh"] is False


async def _until_a_request_waits_for_lock(holder):
    # pg_stat_activity는 트랜잭션 안에서 처음 읽은 값을 계속 돌려주므로 pg_locks를 본다.
    # 같은 서버의 다른 시험 DB에서 기다리는 잠금은 세지 않게 이 연결이 막은 것만 센다.
    for _ in range(200):
        await asyncio.sleep(0.05)
        cursor = await holder.execute(
            "SELECT count(*) AS n FROM pg_locks"
            " WHERE NOT granted AND pg_backend_pid() = ANY(pg_blocking_pids(pid))"
        )
        if (await cursor.fetchone())["n"] > 0:
            return
    raise AssertionError("요청이 프로필 잠금을 기다리지 않음")
