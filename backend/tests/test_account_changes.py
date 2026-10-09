"""선택 동의 변경(1-6)과 탈퇴 이유 저장(1-5) 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import asyncio
from datetime import datetime
from uuid import UUID

from app.core.database import connect
from app.services.accounts import PostgresAccountRepository
from tests.db_api import CONSENT_VERSION, SIGNED_UP_AT, DbApi
from tests.support import request, run
from tests.test_profiles import seed_profile_records


def _history(api: DbApi, account_id: str) -> list[dict]:
    return api.query(
        "SELECT terms_version, service_data, sensitive_data, service_improvement, "
        "       push_notification "
        "FROM consent_records WHERE user_id = %s ORDER BY recorded_at, record_id",
        (account_id,),
    )


def test_changing_optional_consents_adds_a_history_record(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    granted = caregiver.call(
        "PATCH", "/auth/me/consents", json={"serviceImprovement": True}
    )
    refused = caregiver.call(
        "PATCH", "/auth/me/consents", json={"pushNotification": False}
    )

    assert granted.status_code == 200
    consent = granted.json()["consent"]
    assert consent["consentVersion"] == CONSENT_VERSION
    assert consent["serviceImprovement"]["granted"] is True
    assert consent["serviceImprovement"]["grantedAt"] is not None
    # 바꾸지 않은 항목은 직전 이력 그대로다.
    assert consent["pushNotification"]["granted"] is True
    assert (
        datetime.fromisoformat(consent["pushNotification"]["grantedAt"])
        == SIGNED_UP_AT
    )
    after = refused.json()["consent"]
    assert after["pushNotification"] == {"granted": False, "grantedAt": None}
    assert after["serviceImprovement"] == consent["serviceImprovement"]
    assert after["serviceData"]["granted"] is True
    assert caregiver.call("GET", "/auth/me").json()["consent"] == after
    assert _history(api, caregiver.account_id) == [
        {
            "terms_version": CONSENT_VERSION,
            "service_data": True,
            "sensitive_data": True,
            "service_improvement": improvement,
            "push_notification": push,
        }
        for improvement, push in ((False, True), (True, True), (True, False))
    ]


def test_required_consents_cannot_be_changed(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    responses = [
        caregiver.call("PATCH", "/auth/me/consents", json=body)
        for body in (
            {"serviceData": False},
            {"sensitiveData": True, "pushNotification": False},
        )
    ]

    assert [r.status_code for r in responses] == [422, 422]
    assert {r.json()["errorCode"] for r in responses} == {
        "REQUIRED_CONSENT_NOT_CHANGEABLE"
    }
    assert len(_history(api, caregiver.account_id)) == 1


def test_empty_or_malformed_consent_changes_are_rejected(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    responses = [
        caregiver.call("PATCH", "/auth/me/consents", json=body)
        for body in (
            {},
            {"pushNotification": None},
            {"pushNotification": "yes"},
            {"marketing": True},
        )
    ]
    missing_body = caregiver.call("PATCH", "/auth/me/consents")

    assert [r.status_code for r in [*responses, missing_body]] == [422] * 5
    assert {r.json()["errorCode"] for r in [*responses, missing_body]} == {
        "INVALID_REQUEST"
    }
    assert len(_history(api, caregiver.account_id)) == 1


def test_concurrent_consent_changes_keep_both_changes(migrated_database_url):
    api = DbApi(migrated_database_url)
    account_id = api.create_account().account_id

    async def change(name: str, granted: bool) -> None:
        async with connect(migrated_database_url) as connection:
            await PostgresAccountRepository(
                connection, default_display_name="보호자"
            ).change_optional_consents(account_id, {name: granted})

    async def scenario() -> None:
        await asyncio.gather(
            change("serviceImprovement", True), change("pushNotification", False)
        )

    run(scenario())

    latest = api.query(
        "SELECT service_improvement, push_notification FROM current_consents "
        "WHERE user_id = %s",
        (account_id,),
    )
    assert latest == [{"service_improvement": True, "push_notification": False}]


def test_withdrawal_reasons_are_stored_without_the_account(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    response = caregiver.call(
        "DELETE",
        "/auth/me",
        json={"reasons": ["cardsNotHelpful", "other"], "otherText": "합성 기타 사유"},
    )

    assert response.status_code == 204
    assert api.query("SELECT count(*) AS n FROM users")[0]["n"] == 0
    feedback = api.query("SELECT * FROM withdrawal_feedback")
    assert len(feedback) == 1
    row = feedback[0]
    assert set(row) == {"feedback_id", "reasons", "other_text", "submitted_on"}
    assert (row["reasons"], row["other_text"]) == (
        ["cardsNotHelpful", "other"],
        "합성 기타 사유",
    )
    assert row["feedback_id"] != UUID(caregiver.account_id)
    assert caregiver.call("GET", "/auth/me").json()["errorCode"] == "UNAUTHENTICATED"


def test_withdrawal_without_reasons_stores_no_feedback(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    response = caregiver.call("DELETE", "/auth/me")

    assert response.status_code == 204
    assert api.query("SELECT count(*) AS n FROM users")[0]["n"] == 0
    assert api.query("SELECT count(*) AS n FROM withdrawal_feedback")[0]["n"] == 0


def test_invalid_withdrawal_reasons_keep_the_account(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()

    responses = [
        caregiver.call("DELETE", "/auth/me", json=body)
        for body in (
            {"reasons": []},
            {"reasons": ["other"]},
            {"reasons": ["other"], "otherText": "  "},
            {"reasons": ["hardToUse"], "otherText": "합성 기타 사유"},
            {"reasons": ["hardToUse", "hardToUse"]},
            {"reasons": ["tooExpensive"]},
            {"otherText": "합성 기타 사유"},
        )
    ]

    assert [r.status_code for r in responses] == [422] * len(responses)
    assert {r.json()["errorCode"] for r in responses} == {"INVALID_REQUEST"}
    assert caregiver.call("GET", "/auth/me").status_code == 200
    assert api.query("SELECT count(*) AS n FROM withdrawal_feedback")[0]["n"] == 0


def test_withdrawal_removes_profiles_with_cards_and_topics(migrated_database_url):
    api = DbApi(migrated_database_url)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]

    async def seed() -> list[str]:
        async with connect(migrated_database_url) as connection:
            return await seed_profile_records(connection, UUID(profile_id))

    keys = run(seed())

    response = caregiver.call(
        "DELETE", "/auth/me", json={"reasons": ["conditionChanged"]}
    )

    assert response.status_code == 204
    for table in (
        "users",
        "consent_records",
        "profiles",
        "card_sets",
        "profile_topics",
        "conversation_cards",
        "visit_sessions",
        "photos",
        "speech_analysis_jobs",
    ):
        assert api.query(f"SELECT count(*) AS n FROM {table}")[0]["n"] == 0, table
    queued = api.query("SELECT s3_object_key FROM storage_deletion_request_queue")
    assert {row["s3_object_key"] for row in queued} == set(keys)
    assert api.query("SELECT reasons FROM withdrawal_feedback") == [
        {"reasons": ["conditionChanged"]}
    ]


def test_withdrawal_body_is_ignored_without_a_session(migrated_database_url):
    api = DbApi(migrated_database_url)
    api.create_account()

    response = request(
        api.app, "DELETE", "/auth/me", json={"reasons": ["hardToUse"]}
    )

    assert response.status_code == 401
    assert api.query("SELECT count(*) AS n FROM withdrawal_feedback")[0]["n"] == 0
