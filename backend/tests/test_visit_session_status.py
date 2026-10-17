"""회차 상태 계산(`load_visit_session`)과 회차 목록(API 5-4) 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest

from app.core.database import connect
from app.services.session_status import load_visit_session
from tests.support import run
from tests.visit_records import MISSING_ID, Records


def _status(records: Records, session_id: UUID):
    async def scenario():
        async with connect(records.database_url) as connection:
            return await load_visit_session(connection, session_id)

    return run(scenario())


def test_session_status_follows_evaluation_jobs_and_report(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()

    pending = records.visit(profile_id)
    assert _status(records, pending.session_id).session_status == "evaluationPending"

    audio = records.visit(profile_id)
    records.evaluate(audio)
    assert _status(records, audio.session_id).session_status == "audioPending"

    # 업로드 단계의 작업(접수 전)은 아직 음성을 받지 않은 것과 같다.
    uploading = records.visit(profile_id)
    records.evaluate(uploading)
    records.job(uploading.session_id, "uploading")
    assert _status(records, uploading.session_id).session_status == "audioPending"

    for job_status in ("queued", "transcribing", "sttCompleted", "generatingReport"):
        visit = records.visit(profile_id)
        records.evaluate(visit)
        records.job(visit.session_id, job_status)
        assert _status(records, visit.session_id).session_status == "processing"

    failed = records.visit(profile_id)
    records.evaluate(failed)
    records.job(failed.session_id, "failed")
    assert _status(records, failed.session_id).session_status == "failed"

    completed = records.visit(profile_id)
    records.evaluate(completed)
    records.job(completed.session_id, "completed")
    records.report(completed)
    assert _status(records, completed.session_id).session_status == "completed"


def test_failed_job_before_acceptance_does_not_fail_the_session(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    visit = records.visit(profile_id)
    records.evaluate(visit)
    records.job(visit.session_id, "failed", accepted=False)

    assert _status(records, visit.session_id).session_status == "audioPending"


def test_session_uses_latest_job_and_selected_cards(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    visit = records.visit(profile_id, cards=3, selected=2)
    records.evaluate(visit)
    now = datetime.now(UTC)
    records.job(
        visit.session_id, "failed", participant_count=3, created_at=now - timedelta(hours=1)
    )
    latest = records.job(visit.session_id, "queued", participant_count=5, created_at=now)
    photo_id = records.scalar(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, 'synthetic/visit.jpg') RETURNING photo_id",
        (profile_id, visit.session_id),
    )

    session = _status(records, visit.session_id)

    # 실패한 작업이 있어도 처리 중인 작업이 있으면 processing이다.
    assert session.session_status == "processing"
    assert session.participant_count == 5
    assert session.analysis_id == latest
    assert session.selected_card_ids == visit.selected
    assert session.set_id == visit.set_id
    assert session.photo_id == photo_id


def test_list_visit_sessions_contract(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    visit = records.visit(profile_id, started_at=datetime(2026, 8, 21, 5, 0, tzinfo=UTC))

    response = records.call(user_id, "GET", f"/api/v1/profiles/{profile_id}/visit-sessions")

    assert response.status_code == 200
    body = response.json()
    assert body["schemaVersion"] == 1
    assert body["sessions"] == [
        {
            "schemaVersion": 1,
            "sessionId": str(visit.session_id),
            "profileId": str(profile_id),
            "setId": str(visit.set_id),
            "selectedCardIds": [str(card_id) for card_id in visit.selected],
            "sessionStatus": "evaluationPending",
            "photoId": None,
            "participantCount": None,
            "startedAt": "2026-08-21T05:00:00Z",
            "analysisId": None,
        }
    ]


def test_list_visit_sessions_is_recent_first_and_limited(migrated_database_url):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    base = datetime(2026, 8, 1, tzinfo=UTC)
    visits = [records.visit(profile_id, started_at=base + timedelta(days=day)) for day in range(3)]
    path = f"/api/v1/profiles/{profile_id}/visit-sessions"

    all_ids = [s["sessionId"] for s in records.call(user_id, "GET", path).json()["sessions"]]
    limited = records.call(user_id, "GET", f"{path}?limit=2").json()["sessions"]

    assert all_ids == [str(v.session_id) for v in reversed(visits)]
    assert [s["sessionId"] for s in limited] == all_ids[:2]


@pytest.mark.parametrize("limit", ["0", "101", "abc"])
def test_list_visit_sessions_rejects_limit_out_of_range(migrated_database_url, limit):
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()

    response = records.call(
        user_id, "GET", f"/api/v1/profiles/{profile_id}/visit-sessions?limit={limit}"
    )

    assert response.status_code == 422
    assert response.json()["errorCode"] == "INVALID_REQUEST"


def test_other_accounts_profile_looks_missing(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    other_user, _ = records.account()

    responses = [
        records.call(other_user, "GET", f"/api/v1/profiles/{target}/visit-sessions")
        for target in (profile_id, MISSING_ID)
    ]

    assert {r.status_code for r in responses} == {404}
    assert {r.json()["errorCode"] for r in responses} == {"PROFILE_NOT_FOUND"}
