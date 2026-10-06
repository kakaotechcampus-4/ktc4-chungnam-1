"""API 4절(카드 생성) 검증.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). 값은 모두 합성 데이터.
카드는 worker가 만들므로 4-1은 `running` 작업만 만듦.
"""

import pytest

from tests.card_fixtures import (
    card_set_in,
    completed_card_set,
    make_app,
    query,
    user_and_profile,
    visit_with,
    with_db,
)
from tests.support import request


def _request_cards(database_url, user_id, profile_id, **settings):
    app = make_app(database_url, user_id, **settings)
    return request(app, "POST", f"/api/v1/profiles/{profile_id}/card-generations")


def _sets(database_url, profile_id):
    return query(
        database_url,
        "SELECT status, model, prompt_version FROM card_sets "
        "WHERE profile_id = %s ORDER BY created_at",
        (profile_id,),
    )


# ── 4-1 ──────────────────────────────────────────────
def test_request_creates_one_running_set(migrated_database_url):
    user_id, profile_id = with_db(migrated_database_url, user_and_profile)

    first = _request_cards(migrated_database_url, user_id, profile_id)
    again = _request_cards(migrated_database_url, user_id, profile_id)

    assert first.status_code == 202
    assert first.json() == {"schemaVersion": 1, "status": "running"}
    assert again.status_code == 202 and again.json()["status"] == "running"
    assert _sets(migrated_database_url, profile_id) == [
        {"status": "running", "model": "gpt-5.6-luna", "prompt_version": "1"}
    ]


def test_request_uses_model_and_prompt_version_from_settings(migrated_database_url):
    user_id, profile_id = with_db(migrated_database_url, user_and_profile)

    _request_cards(
        migrated_database_url,
        user_id,
        profile_id,
        card_generation_model="synthetic-model",
        card_generation_prompt_version=3,
    )

    assert _sets(migrated_database_url, profile_id) == [
        {"status": "running", "model": "synthetic-model", "prompt_version": "3"}
    ]


def test_failed_or_used_set_can_be_requested_again(migrated_database_url):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        set_id, _ = await completed_card_set(connection, profile_id)
        await visit_with(connection, profile_id, set_id, evaluated=True)
        await card_set_in(connection, profile_id, "failed")
        return user_id, profile_id

    user_id, profile_id = with_db(migrated_database_url, build)

    res = _request_cards(migrated_database_url, user_id, profile_id)

    assert res.status_code == 202
    assert [row["status"] for row in _sets(migrated_database_url, profile_id)] == [
        "completed",
        "failed",
        "running",
    ]


def test_request_is_refused_while_a_visit_uses_the_set(migrated_database_url):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        set_id, _ = await completed_card_set(connection, profile_id)
        await visit_with(connection, profile_id, set_id, evaluated=False)
        return user_id, profile_id

    user_id, profile_id = with_db(migrated_database_url, build)

    res = _request_cards(migrated_database_url, user_id, profile_id)

    assert res.status_code == 409 and res.json()["errorCode"] == "VISIT_IN_PROGRESS"
    assert len(_sets(migrated_database_url, profile_id)) == 1


def test_request_is_refused_without_ml_key(migrated_database_url):
    user_id, profile_id = with_db(migrated_database_url, user_and_profile)

    res = _request_cards(migrated_database_url, user_id, profile_id, ml_api_key="")

    assert res.status_code == 503
    assert res.json()["errorCode"] == "CARD_GENERATION_NOT_CONFIGURED"
    assert _sets(migrated_database_url, profile_id) == []


def test_other_accounts_profile_is_not_found(migrated_database_url):
    async def build(connection):
        _, profile_id = await user_and_profile(connection)
        other_user, _ = await user_and_profile(connection)
        return other_user, profile_id

    other_user, profile_id = with_db(migrated_database_url, build)

    res = _request_cards(migrated_database_url, other_user, profile_id)

    assert res.status_code == 404 and res.json()["errorCode"] == "PROFILE_NOT_FOUND"
    assert _sets(migrated_database_url, profile_id) == []


# ── 4-2 ──────────────────────────────────────────────
def _status(database_url, user_id, profile_id):
    app = make_app(database_url, user_id)
    return request(app, "GET", f"/api/v1/profiles/{profile_id}/card-generations/status")


def test_status_is_none_without_any_card_set(migrated_database_url):
    user_id, profile_id = with_db(migrated_database_url, user_and_profile)

    res = _status(migrated_database_url, user_id, profile_id)

    assert res.status_code == 200 and res.json() == {"schemaVersion": 1, "status": "none"}


@pytest.mark.parametrize("status", ["running", "failed"])
def test_status_of_running_and_failed_sets(migrated_database_url, status):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        await card_set_in(connection, profile_id, status)
        return user_id, profile_id

    user_id, profile_id = with_db(migrated_database_url, build)

    assert _status(migrated_database_url, user_id, profile_id).json()["status"] == status


@pytest.mark.parametrize(
    ("visit", "expected"),
    [(None, "ready"), ("pending", "inVisit"), ("evaluated", "none")],
)
def test_status_of_a_completed_set_follows_its_visit(migrated_database_url, visit, expected):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        set_id, _ = await completed_card_set(connection, profile_id)
        if visit:
            await visit_with(connection, profile_id, set_id, evaluated=visit == "evaluated")
        return user_id, profile_id

    user_id, profile_id = with_db(migrated_database_url, build)

    assert _status(migrated_database_url, user_id, profile_id).json()["status"] == expected


def test_status_follows_only_the_latest_set(migrated_database_url):
    async def build(connection):
        user_id, profile_id = await user_and_profile(connection)
        await completed_card_set(connection, profile_id)
        await card_set_in(connection, profile_id, "running")
        return user_id, profile_id

    user_id, profile_id = with_db(migrated_database_url, build)

    assert _status(migrated_database_url, user_id, profile_id).json()["status"] == "running"


def test_status_of_other_accounts_profile_is_not_found(migrated_database_url):
    async def build(connection):
        _, profile_id = await user_and_profile(connection)
        other_user, _ = await user_and_profile(connection)
        return other_user, profile_id

    other_user, profile_id = with_db(migrated_database_url, build)

    res = _status(migrated_database_url, other_user, profile_id)
    assert res.status_code == 404 and res.json()["errorCode"] == "PROFILE_NOT_FOUND"
