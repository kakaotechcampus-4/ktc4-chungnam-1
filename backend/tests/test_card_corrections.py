"""카드 묶음을 받은 뒤 프로필이나 일대기를 고쳤을 때의 처리 검증(#158).

2-4, 2-7, 2-9로 고치면 아직 면회에 안 쓴 묶음이 `needsRefresh`가 됨. 이 묶음으로는 5-1로
면회를 시작할 수 없고, 4-1로 새 묶음을 만들 수 있음.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`).
"""

import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import connect
from tests.card_fixtures import (
    card_set_in,
    completed_card_set,
    make_app,
    query,
    user_and_profile,
    value,
    visit_with,
    with_db,
)
from tests.support import request, run


async def _profile_with_story(connection):
    user_id, profile_id = await user_and_profile(connection)
    await connection.execute(
        "UPDATE profiles SET occupation = '초등학교 교사' WHERE profile_id = %s", (profile_id,)
    )
    fact_id = await value(
        connection,
        "INSERT INTO life_facts (profile_id, title, content) "
        "VALUES (%s, '교단에 서던 시절', '시골 분교에서 30년 동안 아이들을 가르치셨어요.') "
        "RETURNING fact_id",
        (profile_id,),
    )
    return user_id, profile_id, fact_id


async def _ready(connection):
    """카드 묶음을 받았고 아직 면회는 하지 않은 프로필."""
    user_id, profile_id, fact_id = await _profile_with_story(connection)
    set_id, cards = await completed_card_set(connection, profile_id)
    return user_id, profile_id, fact_id, set_id, cards


def _call(database_url, user_id, method, path, body=None):
    return request(make_app(database_url, user_id), method, path, json=body)


def _status(database_url, user_id, profile_id):
    res = _call(
        database_url, user_id, "GET", f"/api/v1/profiles/{profile_id}/card-generations/status"
    )
    assert res.status_code == 200
    return res.json()


def _stale_at(database_url, set_id):
    rows = query(database_url, "SELECT stale_at FROM card_sets WHERE set_id = %s", (set_id,))
    return rows[0]["stale_at"]


def _correct_story(database_url, user_id, fact_id, body):
    return _call(database_url, user_id, "PATCH", f"/api/v1/life-facts/{fact_id}", body)


def _correct_profile(database_url, user_id, profile_id, body):
    return _call(database_url, user_id, "PATCH", f"/api/v1/profiles/{profile_id}", body)


def _session_count(database_url):
    return query(database_url, "SELECT count(*) AS n FROM visit_sessions")[0]["n"]


def _start_visit(database_url, user_id, set_id, card_ids):
    body = {"setId": str(set_id), "selectedCardIds": [str(card_id) for card_id in card_ids]}
    return _call(database_url, user_id, "POST", "/api/v1/visit-sessions", body)


# ── needsRefresh 표시 ────────────────────────────────────
def test_story_correction_marks_ready_set(migrated_database_url):
    user_id, profile_id, fact_id, set_id, cards = with_db(migrated_database_url, _ready)

    res = _correct_story(
        migrated_database_url,
        user_id,
        fact_id,
        {"content": "시내버스를 30년 동안 운전하셨어요."},
    )

    assert res.status_code == 200
    assert _status(migrated_database_url, user_id, profile_id) == {
        "schemaVersion": 1,
        "status": "ready",
        "needsRefresh": True,
    }
    current = _call(
        migrated_database_url,
        user_id,
        "GET",
        f"/api/v1/profiles/{profile_id}/card-generations/current",
    )
    assert current.status_code == 200
    assert current.json()["setId"] == str(set_id) and current.json()["needsRefresh"] is True


@pytest.mark.parametrize(
    "body",
    [
        {"occupation": "시내버스 기사"},
        {"birthDate": "1953-04-01"},
        {"hometown": "강원도 정선"},
        {"hobby": "라디오로 트로트 듣기"},
        {"family": "아들 둘, 딸 하나"},
        {"occupation": None},
    ],
)
def test_profile_correction_of_card_input_marks_ready_set(migrated_database_url, body):
    user_id, profile_id, _, set_id, _ = with_db(migrated_database_url, _ready)

    res = _correct_profile(migrated_database_url, user_id, profile_id, body)

    assert res.status_code == 200
    assert _status(migrated_database_url, user_id, profile_id)["needsRefresh"] is True
    assert _stale_at(migrated_database_url, set_id) is not None


def test_story_deletion_marks_ready_set(migrated_database_url):
    user_id, profile_id, fact_id, set_id, _ = with_db(migrated_database_url, _ready)

    res = _call(migrated_database_url, user_id, "DELETE", f"/api/v1/life-facts/{fact_id}")

    assert res.status_code == 204
    assert _stale_at(migrated_database_url, set_id) is not None
    left = query(migrated_database_url, "SELECT 1 FROM life_facts WHERE fact_id = %s", (fact_id,))
    assert left == []


@pytest.mark.parametrize(
    "body",
    [
        {"name": "김순자"},
        {"condition": {"stage": "mildCognitiveImpairment"}},
        {"occupation": "초등학교 교사"},
        {"birthDate": "1943-04-01"},
    ],
)
def test_profile_edit_outside_card_input_keeps_set_usable(migrated_database_url, body):
    """이름, 인지 상태처럼 카드 생성에 안 쓰는 값을 고치거나 같은 값으로 다시 저장한 경우."""
    user_id, profile_id, _, set_id, _ = with_db(migrated_database_url, _ready)

    res = _correct_profile(migrated_database_url, user_id, profile_id, body)

    assert res.status_code == 200
    assert _status(migrated_database_url, user_id, profile_id)["needsRefresh"] is False
    assert _stale_at(migrated_database_url, set_id) is None


@pytest.mark.parametrize(
    "body",
    [
        {"storyCategory": "work", "imageNumber": 2},
        {"title": "교단에 서던 시절", "content": "시골 분교에서 30년 동안 아이들을 가르치셨어요."},
    ],
)
def test_story_edit_outside_card_input_keeps_set_usable(migrated_database_url, body):
    """분류와 그림 번호만 고치거나 제목과 내용을 같은 값으로 다시 저장한 경우."""
    user_id, profile_id, fact_id, set_id, _ = with_db(migrated_database_url, _ready)

    res = _correct_story(migrated_database_url, user_id, fact_id, body)

    assert res.status_code == 200
    assert _stale_at(migrated_database_url, set_id) is None


def test_set_used_by_a_visit_is_not_marked(migrated_database_url):
    """면회에 쓴 묶음은 지난 기록이라 고쳐도 그대로 둠."""

    async def build(connection):
        user_id, profile_id, fact_id, set_id, _ = await _ready(connection)
        await visit_with(connection, profile_id, set_id, evaluated=False)
        return user_id, profile_id, fact_id, set_id

    user_id, profile_id, fact_id, set_id = with_db(migrated_database_url, build)

    res = _correct_story(
        migrated_database_url, user_id, fact_id, {"content": "시내버스를 30년 동안 운전하셨어요."}
    )

    assert res.status_code == 200
    assert _status(migrated_database_url, user_id, profile_id) == {
        "schemaVersion": 1,
        "status": "inVisit",
        "needsRefresh": False,
    }
    assert _stale_at(migrated_database_url, set_id) is None


# ── 다시 만들기와 면회 시작 ──────────────────────────
def test_stale_set_is_regenerated_and_refused_for_a_visit(migrated_database_url):
    user_id, profile_id, fact_id, set_id, cards = with_db(migrated_database_url, _ready)
    _correct_story(
        migrated_database_url, user_id, fact_id, {"content": "시내버스를 30년 동안 운전하셨어요."}
    )

    visit = _start_visit(migrated_database_url, user_id, set_id, cards[:2])
    regenerate = _call(
        migrated_database_url, user_id, "POST", f"/api/v1/profiles/{profile_id}/card-generations"
    )

    assert visit.status_code == 409 and visit.json()["errorCode"] == "CARD_SET_NEEDS_REFRESH"
    assert regenerate.status_code == 202 and regenerate.json()["status"] == "running"
    statuses = query(
        migrated_database_url,
        "SELECT status FROM card_sets WHERE profile_id = %s ORDER BY created_at",
        (profile_id,),
    )
    assert [row["status"] for row in statuses] == ["completed", "running"]
    assert _session_count(migrated_database_url) == 0


def test_stale_set_stays_refused_after_regeneration_fails(migrated_database_url):
    async def build(connection):
        user_id, profile_id, fact_id, set_id, cards = await _ready(connection)
        await connection.execute(
            "UPDATE card_sets SET stale_at = now() WHERE set_id = %s", (set_id,)
        )
        await card_set_in(connection, profile_id, "failed")
        return user_id, profile_id, set_id, cards

    user_id, profile_id, set_id, cards = with_db(migrated_database_url, build)

    visit = _start_visit(migrated_database_url, user_id, set_id, cards[:1])

    assert _status(migrated_database_url, user_id, profile_id)["status"] == "failed"
    assert visit.status_code == 409 and visit.json()["errorCode"] == "CARD_SET_NEEDS_REFRESH"


def test_new_set_after_regeneration_is_usable(migrated_database_url):
    async def build(connection):
        user_id, profile_id, fact_id, set_id, _ = await _ready(connection)
        await connection.execute(
            "UPDATE card_sets SET stale_at = now() WHERE set_id = %s", (set_id,)
        )
        new_set_id, new_cards = await completed_card_set(connection, profile_id)
        return user_id, profile_id, new_set_id, new_cards

    user_id, profile_id, new_set_id, new_cards = with_db(migrated_database_url, build)

    assert _status(migrated_database_url, user_id, profile_id) == {
        "schemaVersion": 1,
        "status": "ready",
        "needsRefresh": False,
    }
    visit = _start_visit(migrated_database_url, user_id, new_set_id, new_cards[:1])
    assert visit.status_code == 201


# ── 카드를 만드는 중에 고칠 때 ───────────────────────────
def test_correction_is_refused_while_cards_are_being_made(migrated_database_url):
    async def build(connection):
        user_id, profile_id, fact_id = await _profile_with_story(connection)
        await card_set_in(connection, profile_id, "running")
        return user_id, profile_id, fact_id

    user_id, profile_id, fact_id = with_db(migrated_database_url, build)

    story = _correct_story(
        migrated_database_url, user_id, fact_id, {"content": "시내버스를 30년 동안 운전하셨어요."}
    )
    deletion = _call(migrated_database_url, user_id, "DELETE", f"/api/v1/life-facts/{fact_id}")
    # 이름은 고칠 수 있는 값이지만 직업과 같이 보냈으므로 요청 전체가 거절돼야 함
    profile = _correct_profile(
        migrated_database_url,
        user_id,
        profile_id,
        {"name": "김순자", "occupation": "시내버스 기사"},
    )

    for res in (story, deletion, profile):
        assert res.status_code == 409 and res.json()["errorCode"] == "CARD_GENERATION_IN_PROGRESS"
    saved = query(
        migrated_database_url,
        "SELECT f.content, p.name, p.occupation"
        "  FROM life_facts f JOIN profiles p USING (profile_id) WHERE f.fact_id = %s",
        (fact_id,),
    )
    assert saved == [
        {
            "content": "시골 분교에서 30년 동안 아이들을 가르치셨어요.",
            "name": "합성이름",
            "occupation": "초등학교 교사",
        }
    ]

    rename = _correct_profile(migrated_database_url, user_id, profile_id, {"name": "김순자"})

    assert rename.status_code == 200


def test_correction_after_regeneration_marks_the_new_set(migrated_database_url):
    async def build(connection):
        user_id, profile_id, fact_id, set_id, _ = await _ready(connection)
        await connection.execute(
            "UPDATE card_sets SET stale_at = now() WHERE set_id = %s", (set_id,)
        )
        new_set_id, _ = await completed_card_set(connection, profile_id)
        return user_id, profile_id, fact_id, new_set_id

    user_id, profile_id, fact_id, new_set_id = with_db(migrated_database_url, build)

    res = _correct_story(migrated_database_url, user_id, fact_id, {"title": "운전대를 잡던 시절"})

    assert res.status_code == 200
    assert _stale_at(migrated_database_url, new_set_id) is not None
    assert _status(migrated_database_url, user_id, profile_id)["needsRefresh"] is True
    sets = query(
        migrated_database_url, "SELECT 1 FROM card_sets WHERE profile_id = %s", (profile_id,)
    )
    assert len(sets) == 2



# ── 다른 요청이 프로필을 잠근 채 이야기를 지울 때 ─────────
@pytest.mark.parametrize(
    "method, body",
    [("PATCH", {"content": "시내버스를 30년 동안 운전하셨어요."}), ("DELETE", None)],
)
def test_story_deleted_while_waiting_for_profile_lock(migrated_database_url, method, body):
    """2-7, 2-9가 프로필 잠금을 기다리는 사이 다른 요청이 이야기를 지우고 끝낸 경우.

    잠금이 풀린 뒤 이야기가 없으니 404로 끝나고, 묶음에는 표시가 남지 않아야 함.
    """
    user_id, profile_id, fact_id, set_id, _ = with_db(migrated_database_url, _ready)
    app = make_app(migrated_database_url, user_id)

    async def scenario():
        async with connect(migrated_database_url) as holder:
            async with holder.transaction():
                await holder.execute(
                    "SELECT 1 FROM profiles WHERE profile_id = %s FOR UPDATE", (profile_id,)
                )
                client = AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver")
                sent = asyncio.create_task(
                    client.request(method, f"/api/v1/life-facts/{fact_id}", json=body)
                )
                await _until_a_request_waits_for_lock(holder)
                await holder.execute("DELETE FROM life_facts WHERE fact_id = %s", (fact_id,))
            res = await sent
            await client.aclose()
            return res

    res = run(scenario())

    assert res.status_code == 404 and res.json()["errorCode"] == "LIFE_FACT_NOT_FOUND"
    assert _stale_at(migrated_database_url, set_id) is None


async def _until_a_request_waits_for_lock(holder):
    # pg_stat_activity는 트랜잭션 안에서 처음 읽은 값을 계속 돌려주므로 pg_locks를 봄
    for _ in range(100):
        await asyncio.sleep(0.05)
        cursor = await holder.execute("SELECT count(*) AS n FROM pg_locks WHERE NOT granted")
        if (await cursor.fetchone())["n"] > 0:
            return
    raise AssertionError("요청이 프로필 잠금을 기다리지 않음")
