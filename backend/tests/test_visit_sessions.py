"""API 5절(면회 회차) 검증.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). 값은 모두 합성 데이터.
"""

from uuid import uuid4

import pytest

from tests.card_fixtures import (
    card_set_in,
    completed_card_set,
    make_app,
    query,
    user_and_profile,
    with_db,
)
from tests.support import request


async def _ready_set(connection):
    user_id, profile_id = await user_and_profile(connection)
    set_id, cards = await completed_card_set(connection, profile_id)
    return user_id, set_id, cards


def _create(database_url, user_id, set_id, card_ids):
    app = make_app(database_url, user_id)
    body = {"setId": str(set_id), "selectedCardIds": [str(card_id) for card_id in card_ids]}
    return request(app, "POST", "/api/v1/visit-sessions", json=body)


def _session_count(database_url):
    return query(database_url, "SELECT count(*) AS n FROM visit_sessions")[0]["n"]


# ── 5-1 ──────────────────────────────────────────────
def test_session_marks_selected_cards_and_takes_the_set(migrated_database_url):
    user_id, set_id, cards = with_db(migrated_database_url, _ready_set)

    created = _create(migrated_database_url, user_id, set_id, [cards[0], cards[4]])
    again = _create(migrated_database_url, user_id, set_id, [cards[1]])

    assert created.status_code == 201
    session = created.json()
    assert session["sessionStatus"] == "evaluationPending" and session["setId"] == str(set_id)
    assert session["selectedCardIds"] == [str(cards[0]), str(cards[4])]
    assert session["photoId"] is None
    assert session["participantCount"] is None and session["analysisId"] is None
    assert again.status_code == 409 and again.json()["errorCode"] == "CARD_SET_ALREADY_USED"
    linked = query(
        migrated_database_url, "SELECT session_id FROM card_sets WHERE set_id = %s", (set_id,)
    )
    assert str(linked[0]["session_id"]) == session["sessionId"]


@pytest.mark.parametrize(
    "pick",
    [[], [0, 0], [9], list(range(10))],
    ids=["empty", "duplicate", "reserve-card", "ten-cards"],
)
def test_session_rejects_bad_selection(migrated_database_url, pick):
    user_id, set_id, cards = with_db(migrated_database_url, _ready_set)

    res = _create(migrated_database_url, user_id, set_id, [cards[i] for i in pick])

    assert res.status_code == 422
    assert _session_count(migrated_database_url) == 0


def test_session_rejects_cards_from_another_set(migrated_database_url):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        set_id, _ = await completed_card_set(connection, profile_id)
        _, other_cards = await completed_card_set(connection, profile_id)
        return user_id, set_id, other_cards

    user_id, set_id, other_cards = with_db(migrated_database_url, build)

    res = _create(migrated_database_url, user_id, set_id, [other_cards[0]])

    assert res.status_code == 422 and res.json()["errorCode"] == "INVALID_CARD_SELECTION"


@pytest.mark.parametrize("status", ["running", "failed"])
def test_session_needs_a_completed_set(migrated_database_url, status):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        return user_id, await card_set_in(connection, profile_id, status)

    user_id, set_id = with_db(migrated_database_url, build)

    res = _create(migrated_database_url, user_id, set_id, [uuid4()])

    assert res.status_code == 409 and res.json()["errorCode"] == "CARD_GENERATION_NOT_COMPLETED"


def test_session_on_other_accounts_set_is_not_found(migrated_database_url):
    async def build(connection):
        _, set_id, cards = await _ready_set(connection)
        other_user, _ = await user_and_profile(connection)
        return other_user, set_id, cards

    other_user, set_id, cards = with_db(migrated_database_url, build)

    res = _create(migrated_database_url, other_user, set_id, [cards[0]])

    assert res.status_code == 404 and res.json()["errorCode"] == "CARD_GENERATION_NOT_FOUND"
    assert _session_count(migrated_database_url) == 0
