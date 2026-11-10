"""첫 사진 대기: 실제 임시 PostgreSQL, 합성 사진, 모델과 S3는 대역."""
from uuid import UUID, uuid4

import pytest
from pydantic import SecretStr

from app.core.database import connect
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.card_sets import CardGenerationProcessor
from photo_analysis import PhotoDescription
from tests.support import run
from tests.test_card_generation_worker import fake_result
from tests.test_photo_analysis_pipeline import setup, worker
from tests.test_profile_photos import _upload


def prepare(url, count=5):
    api, user, profile, first = setup(url)
    api.settings.ml_api_key = SecretStr("synthetic-key")
    api.query("UPDATE profiles SET hobby='합성 취미' WHERE profile_id=%s", (profile,))
    photos = [first] + [_upload(user, profile).json()["photoId"] for _ in range(count-1)]
    base = f"/api/v1/profiles/{profile}/card-generations"
    response = user.call("POST", base)
    assert response.status_code == 202, response.text
    return api, user, profile, photos, base, response.json()["photoPreparation"]["setId"]


def claim(url):
    async def one():
        async with connect(url) as conn:
            return await CardGenerationQueue().claim(conn, lease_seconds=60)
    return run(one())


def analyze(url):
    return run(worker(url, lambda _: PhotoDescription(description="합성 사진 속 기차")).run_once())


def choose(user, base, set_id, action):
    return user.call("POST", base+"/photo-preparation", json={"setId":set_id, "action":action})


def test_five_photos_enter_first_generation_and_survive_new_connection(migrated_database_url):
    url = migrated_database_url
    api, user, profile, photos, base, set_id = prepare(url)
    assert claim(url) is None
    for n in range(4):
        assert analyze(url)
        assert claim(url) is None
        progress = user.call("GET", base+"/status").json()["photoPreparation"]
        assert (progress["completed"], progress["total"], progress["state"]) == (n+1, 5, "waiting")
    assert analyze(url)
    # 앱 조회 없이, 새 worker 연결이 사진 준비를 마치고 작업을 가져간다.
    job = claim(url)
    assert str(job.set_id) == set_id
    seen = []
    def generate(request):
        seen.extend(str(p.photo_id) for p in request.context.photos)
        result = fake_result(request)
        # 사진 근거가 저장된 주제와 카드까지 이어지는지 검사한다.
        evidence = [{"photoId":photos[0]}]
        result.cards[0].evidence_source = "photo"
        result.cards[0].evidence = evidence
        result.cards[0].topic.evidence = evidence
        return result
    async def finish():
        async with connect(url) as conn:
            await CardGenerationProcessor(queue=CardGenerationQueue(), generate=generate)(conn, job)
    run(finish())
    assert set(seen) == set(photos)
    assert user.call("GET", base+"/status").json() == {
        "schemaVersion":1, "status":"ready", "needsRefresh":False}
    cards = user.call("GET", base+"/current").json()["cards"]
    assert len(cards) == 12 and cards[0]["evidence"] == [{"photoId":photos[0]}]
    assert api.query("SELECT cardinality(photo_wait_ids) AS n FROM card_sets")[0]["n"] == 5


@pytest.mark.parametrize("action", ["retry", "continue"])
def test_partial_failure_requires_explicit_choice(migrated_database_url, action):
    url = migrated_database_url
    api, user, _, photos, base, set_id = prepare(url, 2)
    assert analyze(url)
    api.query("UPDATE photos SET analysis_status='failed', error_code='SYNTHETIC' WHERE photo_id=%s", (photos[1],))
    assert claim(url) is None
    progress = user.call("GET", base+"/status").json()["photoPreparation"]
    assert (progress["completed"], progress["failed"], progress["reason"]) == (1, 1, "analysisFailed")
    assert choose(user, base, set_id, action).status_code == 200
    if action == "retry":
        assert claim(url) is None
        assert analyze(url)
    job = claim(url)
    assert job is not None
    async def finish():
        async with connect(url) as conn:
            def generate(request):
                assert len(request.context.photos) == (2 if action == "retry" else 1)
                return fake_result(request)
            await CardGenerationProcessor(queue=CardGenerationQueue(), generate=generate)(conn, job)
    run(finish())
    assert user.call("GET", base+"/status").json()["status"] == "ready"
    assert api.query("SELECT count(*) AS n FROM card_sets")[0]["n"] == 1


@pytest.mark.parametrize("action", ["retry", "continue"])
def test_timeout_does_not_start_model_or_expire_card_queue(migrated_database_url, action):
    url = migrated_database_url
    api, user, _, _, base, set_id = prepare(url, 1)
    api.query("UPDATE card_sets SET created_at=now()-interval '1 hour', photo_wait_until=now()-interval '1 second'")
    progress = user.call("GET", base+"/status").json()["photoPreparation"]
    assert progress["reason"] == "timedOut" and progress["pending"] == 1
    assert claim(url) is None
    assert choose(user, base, set_id, action).status_code == 200
    if action == "retry":
        assert user.call("GET", base+"/status").json()["photoPreparation"]["state"] == "waiting"
        assert analyze(url)
    assert user.call("GET", base+"/status").json()["status"] == "running"
    assert claim(url) is not None  # 사진 대기 한 시간은 카드 시작 제한에 포함하지 않는다.


def test_other_profiles_are_not_blocked_and_repeated_post_keeps_snapshot(migrated_database_url):
    url = migrated_database_url
    api, user, profile, photos, base, set_id = prepare(url, 1)
    new = _upload(user, profile).json()["photoId"]
    again = user.call("POST", base)
    assert again.json()["photoPreparation"]["setId"] == set_id
    assert again.json()["photoPreparation"]["total"] == 1
    other = user.create_profile()["profileId"]
    assert user.call("POST", f"/api/v1/profiles/{other}/card-generations").status_code == 202
    assert str(claim(url).profile_id) == other
    assert analyze(url)
    assert str(claim(url).profile_id) == profile  # 새로 추가한 사진은 기다리지 않는다.
    assert api.query("SELECT analysis_status FROM photos WHERE photo_id=%s", (new,))[0]["analysis_status"] == "pending"


def test_consent_revoked_while_waiting_requires_choice(migrated_database_url):
    url = migrated_database_url
    api, user, _, _, base, set_id = prepare(url, 1)
    assert user.call("PATCH", "/auth/me/consents", json={"photoAnalysis":False}).status_code == 200
    assert claim(url) is None
    assert user.call("GET", base+"/status").json()["photoPreparation"]["reason"] == "consentRequired"
    assert choose(user, base, set_id, "retry").json()["errorCode"] == "PHOTO_ANALYSIS_CONSENT_REQUIRED"
    assert choose(user, base, set_id, "continue").status_code == 200
    assert claim(url) is not None


def test_reconsent_then_retry_resumes_same_job(migrated_database_url):
    url = migrated_database_url
    _, user, _, _, base, set_id = prepare(url, 1)
    user.call("PATCH", "/auth/me/consents", json={"photoAnalysis":False})
    assert user.call("GET", base+"/status").json()["photoPreparation"]["state"] == "choice"
    user.call("PATCH", "/auth/me/consents", json={"photoAnalysis":True})
    # 지금은 다시 waiting 상태다. 오래된 선택 요청은 작업을 바꾸지 않고 상태 재조회를 요구한다.
    assert choose(user, base, set_id, "retry").status_code == 409
    assert analyze(url)
    assert str(claim(url).set_id) == set_id


def test_no_consent_never_waits_or_calls_photo_worker(migrated_database_url):
    url = migrated_database_url
    from tests.test_photo_description import setup as no_consent_setup
    api, user, profile, _ = no_consent_setup(url)
    api.settings.ml_api_key = SecretStr("synthetic-key")
    response = user.call("POST", f"/api/v1/profiles/{profile}/card-generations")
    assert "photoPreparation" not in response.json()
    assert not analyze(url)
    assert claim(url) is not None


def test_deleted_photo_does_not_leave_permanent_wait(migrated_database_url):
    url = migrated_database_url
    api, _, _, photos, _, _ = prepare(url, 1)
    api.query("DELETE FROM photos WHERE photo_id=%s", (photos[0],))
    assert claim(url) is not None


def test_failed_analysis_with_caregiver_description_is_ready(migrated_database_url):
    url = migrated_database_url
    api, _, _, photos, _, _ = prepare(url, 1)
    api.query("UPDATE photos SET analysis_status='failed', error_code='SYNTHETIC', "
              "user_description='보호자가 적은 합성 사진 설명', description_updated_at=now() WHERE photo_id=%s", (photos[0],))
    assert claim(url) is not None


def test_active_photo_not_restarted_by_timeout_retry(migrated_database_url):
    url = migrated_database_url
    api, user, _, photos, base, set_id = prepare(url, 1)
    api.query("UPDATE photos SET analysis_status='processing', attempt_count=1, lease_expires_at=now()+interval '1 minute'")
    api.query("UPDATE card_sets SET photo_wait_until=now()-interval '1 second'")
    assert choose(user, base, set_id, "retry").status_code == 200
    assert api.query("SELECT analysis_status, attempt_count FROM photos")[0] == {"analysis_status":"processing", "attempt_count":1}
    assert claim(url) is None


def test_expired_photo_is_retryable_and_late_attempt_cannot_overwrite(migrated_database_url):
    url = migrated_database_url
    api, user, profile, photos, base, set_id = prepare(url, 1)
    api.query("UPDATE photos SET analysis_status='processing', attempt_count=1, lease_expires_at=now()-interval '1 second'")
    assert user.call("GET", base+"/status").json()["photoPreparation"]["failed"] == 1
    assert choose(user, base, set_id, "retry").status_code == 200
    assert analyze(url)
    assert api.query("SELECT attempt_count FROM photos")[0]["attempt_count"] == 2
    from app.services.photo_analysis_jobs import PhotoAnalysisJob, PhotoAnalysisQueue
    async def late_error():
        async with connect(url) as conn:
            job = PhotoAnalysisJob(UUID(photos[0]), UUID(profile), "unused", 1)
            await PhotoAnalysisQueue().fail(conn, job, error_code="OLD_ATTEMPT")
    # 재시도 성공 뒤 도착한 이전 시도의 실패는 버린다.
    run(late_error())
    assert api.query("SELECT analysis_status FROM photos")[0]["analysis_status"] == "completed"


def test_ownership_stale_set_and_invalid_choice_are_rejected(migrated_database_url):
    api, user, profile, photos, base, set_id = prepare(migrated_database_url, 1)
    api.query("UPDATE photos SET analysis_status='failed', error_code='SYNTHETIC'")
    other = api.create_account()
    assert choose(other, base, set_id, "continue").status_code == 404
    assert choose(user, base, str(uuid4()), "continue").status_code == 409
    assert choose(user, base, set_id, "invalid").status_code == 422
    assert choose(user, base, set_id, "continue").status_code == 200
    assert choose(user, base, set_id, "retry").status_code == 409


def test_all_failed_continue_uses_no_unfinished_photo(migrated_database_url):
    from app.services.card_sets import build_context
    url = migrated_database_url
    api, user, profile, _, base, set_id = prepare(url)
    api.query("UPDATE photos SET analysis_status='failed', error_code='SYNTHETIC'")
    state = user.call("GET", base+"/status").json()["photoPreparation"]
    assert state["failed"] == 5 and state["completed"] == 0
    assert choose(user, base, set_id, "continue").status_code == 200
    job = claim(url)
    assert job is not None
    async def context():
        async with connect(url) as conn:
            return await build_context(conn, UUID(profile))
    assert run(context()).photos == []
    async def finish():
        async with connect(url) as conn:
            await CardGenerationProcessor(queue=CardGenerationQueue(), generate=fake_result)(conn, job)
    run(finish())
    assert user.call("GET", base+"/status").json()["status"] == "ready"


def test_later_card_generation_does_not_wait_for_new_photos(migrated_database_url):
    from tests.card_fixtures import completed_card_set, with_db
    url = migrated_database_url
    api, user, profile, _ = setup(url)
    api.settings.ml_api_key = SecretStr("synthetic-key")
    async def seed(conn):
        return await completed_card_set(conn, UUID(profile))
    with_db(url, seed)
    api.query("UPDATE card_sets SET stale_at=now()")
    response = user.call("POST", f"/api/v1/profiles/{profile}/card-generations")
    assert response.status_code == 202 and "photoPreparation" not in response.json()
    assert claim(url) is not None


def test_simultaneous_workers_claim_ready_job_once(migrated_database_url):
    import asyncio
    url = migrated_database_url
    _, _, _, _, _, set_id = prepare(url, 1)
    assert analyze(url)
    async def scenario():
        async def once():
            async with connect(url) as conn:
                return await CardGenerationQueue().claim(conn, lease_seconds=60)
        return await asyncio.gather(once(), once(), once())
    jobs = [job for job in run(scenario()) if job is not None]
    assert len(jobs) == 1 and str(jobs[0].set_id) == set_id


def test_photo_timeout_while_profile_locked_records_failure(migrated_database_url):
    url = migrated_database_url
    api, user, profile, _, base, _ = prepare(url, 1)
    async def scenario():
        async with connect(url) as blocker:
            async with blocker.transaction():
                await blocker.execute("SELECT 1 FROM profiles WHERE profile_id=%s FOR UPDATE", (profile,))
                assert await worker(url, lambda _: pytest.fail("시간 초과 뒤 모델 호출 금지"), timeout=.05).run_once()
    run(scenario())
    assert api.query("SELECT error_code FROM photos")[0]["error_code"] == "IMAGE_ANALYSIS_TIMEOUT"
    assert user.call("GET", base+"/status").json()["photoPreparation"]["reason"] == "analysisFailed"
