import time
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from photo_analysis import PhotoDescription

from app.core.config import Settings
from app.core.database import connect
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.card_sets import CardGenerationProcessor, build_context
from app.services.photo_analysis_jobs import PhotoAnalysisQueue
from app.services.photo_analysis_pipeline import PhotoAnalysisProcessor
from app.services.image_storage import ImageDownload
from app.workers.base import Worker
from app.workers.photo_analysis import create_worker
from tests.card_fixtures import completed_card_set, with_db
from tests.support import run
from tests.test_card_generation_worker import fake_result
from tests.test_photo_description import setup, patch
from tests.test_profile_photos import MemoryImageStorage


class FreshSyntheticStorage(MemoryImageStorage):
    async def create_download(self, *, object_key):
        return ImageDownload(url="https://synthetic.invalid/image?signature=test",
                             expires_at=datetime.now(UTC) + timedelta(minutes=5))


def worker(url, analyze, timeout=1):
    return Worker(
        queue=PhotoAnalysisQueue(),
        process=PhotoAnalysisProcessor(storage=FreshSyntheticStorage(), analyze=analyze,
                                       model="synthetic-model", timeout_seconds=timeout),
        open_connection=lambda: connect(url), lease_seconds=60,
    )


def test_upload_analysis_query_card_input(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    assert run(worker(migrated_database_url, lambda _: PhotoDescription(description="합성 사진 분석")).run_once())
    read = user.call("GET", f"/api/v1/profile-photos/{photo}").json()
    assert (read["analysisStatus"], read["description"], read["descriptionSource"]) == (
        "completed", "합성 사진 분석", "ai")
    async def context(conn):
        return await build_context(conn, UUID(profile))
    assert with_db(migrated_database_url, context).photos[0].description == "합성 사진 분석"
    row = api.query("SELECT model, prompt_version, lease_expires_at FROM photos")[0]
    assert row == {"model": "synthetic-model", "prompt_version": "photo-1", "lease_expires_at": None}


def test_ai_completion_does_not_overwrite_caregiver(migrated_database_url):
    api, user, profile, photo = setup(migrated_database_url)
    assert patch(user, photo, "보호자 정정").status_code == 200
    run(worker(migrated_database_url, lambda _: PhotoDescription(description="AI 설명")).run_once())
    read = user.call("GET", f"/api/v1/profile-photos/{photo}").json()
    assert (read["description"], read["descriptionSource"]) == ("보호자 정정", "caregiver")
    assert api.query("SELECT description FROM photos")[0]["description"] == "AI 설명"


@pytest.mark.parametrize("change", ["delete", "expire", "new_attempt"])
def test_late_result_cannot_restore_deleted_or_expired_job(migrated_database_url, change):
    api, _, _, photo = setup(migrated_database_url)
    called = []
    def analyze(_):
        called.append(True)
        if change == "delete":
            api.query("DELETE FROM photos WHERE photo_id=%s", (photo,))
        elif change == "expire":
            api.query("UPDATE photos SET lease_expires_at=now()-interval '1 second' WHERE photo_id=%s", (photo,))
        else:
            api.query("UPDATE photos SET attempt_count=attempt_count+1 WHERE photo_id=%s", (photo,))
        return PhotoDescription(description="저장하면 안 되는 결과")
    run(worker(migrated_database_url, analyze).run_once())
    assert called == [True]
    rows = api.query("SELECT description, analysis_status FROM photos")
    assert not rows or rows[0]["description"] is None


def test_timeout_and_late_thread_result_never_store(migrated_database_url):
    api, _, _, _ = setup(migrated_database_url)
    def slow(_):
        time.sleep(.08)
        return PhotoDescription(description="늦게 도착")
    run(worker(migrated_database_url, slow, timeout=.01).run_once())
    assert api.query("SELECT analysis_status, error_code, description FROM photos")[0] == {
        "analysis_status": "failed", "error_code": "IMAGE_ANALYSIS_TIMEOUT", "description": None}


def test_invalid_response_is_failed_without_leaking_content(migrated_database_url, caplog):
    api, _, _, _ = setup(migrated_database_url)
    run(worker(migrated_database_url, lambda _: {"description": " "}).run_once())
    assert api.query("SELECT error_code FROM photos")[0]["error_code"] == "IMAGE_ANALYSIS_FAILED"
    assert "synthetic.invalid" not in caplog.text


def test_completed_ready_cards_become_stale_when_photo_finishes(migrated_database_url):
    api, _, profile, _ = setup(migrated_database_url)
    async def seed(conn):
        return await completed_card_set(conn, UUID(profile))
    with_db(migrated_database_url, seed)
    run(worker(migrated_database_url, lambda _: PhotoDescription(description="새 사진 설명")).run_once())
    assert api.query("SELECT stale_at FROM card_sets")[0]["stale_at"] is not None


def test_photo_finishes_during_card_generation_result_requires_refresh(migrated_database_url):
    api, _, profile, _ = setup(migrated_database_url)
    api.query("UPDATE profiles SET hobby='합성 취미' WHERE profile_id=%s", (profile,))
    api.query("INSERT INTO card_sets(profile_id,status,model,prompt_version) VALUES (%s,'running','synthetic','1')", (profile,))
    def generate(request):
        run(worker(migrated_database_url, lambda _: PhotoDescription(description="생성 중 새 설명")).run_once())
        return fake_result(request)
    async def scenario():
        async with connect(migrated_database_url) as conn:
            queue = CardGenerationQueue()
            job = await queue.claim(conn, lease_seconds=60)
            await CardGenerationProcessor(queue=queue, generate=generate)(conn, job)
    run(scenario())
    row = api.query("SELECT status, stale_at FROM card_sets")[0]
    assert row["status"] == "completed" and row["stale_at"] is not None


def test_production_or_unconfirmed_dataset_is_not_started():
    with pytest.raises(RuntimeError, match="합성 사진"):
        create_worker(Settings(environment="production"), synthetic_test_data=True)
    with pytest.raises(RuntimeError, match="합성 사진"):
        create_worker(Settings(environment="test"))


def test_short_lease_is_refused_before_storage_connection():
    settings = Settings(environment="test", database_url="synthetic",
                        image_s3_bucket="synthetic", ml_api_key="synthetic",
                        photo_analysis_lease_seconds=60)
    with pytest.raises(RuntimeError, match="60초"):
        create_worker(settings, synthetic_test_data=True)


def test_job_deleted_before_processing_does_not_send_photo(migrated_database_url):
    api, _, _, photo = setup(migrated_database_url)
    async def scenario():
        async with connect(migrated_database_url) as conn:
            job = await PhotoAnalysisQueue().claim(conn, lease_seconds=60)
            await conn.execute("DELETE FROM photos WHERE photo_id=%s", (photo,))
            processor = PhotoAnalysisProcessor(
                storage=FreshSyntheticStorage(), analyze=lambda _: pytest.fail("호출 금지"),
                model="synthetic", timeout_seconds=1)
            await processor(conn, job)
    run(scenario())


def test_old_attempt_error_does_not_fail_new_attempt(migrated_database_url):
    api, _, _, photo = setup(migrated_database_url)
    async def scenario():
        async with connect(migrated_database_url) as conn:
            queue = PhotoAnalysisQueue()
            job = await queue.claim(conn, lease_seconds=60)
            await conn.execute("UPDATE photos SET attempt_count=attempt_count+1 WHERE photo_id=%s", (photo,))
            await queue.fail(conn, job, error_code="OLD_ATTEMPT_ERROR")
    run(scenario())
    assert api.query("SELECT analysis_status,error_code FROM photos")[0] == {
        "analysis_status": "processing", "error_code": None}
