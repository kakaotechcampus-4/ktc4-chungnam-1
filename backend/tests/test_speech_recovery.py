"""실제 임시 PostgreSQL, 합성 전사와 외부 API 대역으로 수동 복구를 검사한다."""

import asyncio
from dataclasses import replace
from uuid import UUID

import pytest

from app.api.deps import get_current_account
from app.core.config import Settings, get_settings
from app.core.database import connect
from app.core.errors import AppError
from app.main import create_app
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import VisitReportGenerator
from tests.support import request, run
from tests.test_speech_analyses import ACCOUNT
from tests.test_speech_job_repository import _Db, _accept, _generating, _job
from tests.test_visit_report_generator import (
    FakeAi, FakeAudioStorage, Records, TIME_LIMIT_SECONDS, _evaluated,
    _report, _run_worker, _violations,
)


def _failed_report(db):
    owner, session = db.seed_session()
    old = _generating(db, session)
    run(db.repository.mark_failed(analysis_id=old.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    return owner, old


def test_retry_uses_a_new_id_preserves_deadline_and_is_idempotent(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    before = db.job_row(old.analysis_id)
    new = run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    again = run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    assert new.analysis_id != old.analysis_id
    assert new.analysis_id == again.analysis_id
    assert new.status == "sttCompleted"
    assert new.transcript_expires_at == before["transcript_expires_at"]
    assert db.job_row(old.analysis_id)["transcript"] is None
    assert db.job_row(new.analysis_id)["retry_of_analysis_id"] == UUID(old.analysis_id)
    # 이전 작업에 늦게 결과가 와도 새 작업이나 전사를 바꾸지 않는다.
    assert run(db.repository.mark_generating_report(analysis_id=old.analysis_id)) is False
    run(db.repository.mark_completed(analysis_id=old.analysis_id))
    assert db.job_row(old.analysis_id)["status"] == "failed"
    assert db.job_row(new.analysis_id)["status"] == "sttCompleted"


def test_concurrent_retry_creates_only_one_job(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)

    async def scenario():
        return await asyncio.gather(*[
            db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner)
            for _ in range(4)
        ])

    jobs = run(scenario())
    assert len({job.analysis_id for job in jobs}) == 1
    assert db.execute("SELECT count(*) AS n FROM speech_analysis_jobs")[0]["n"] == 2


def test_stt_only_worker_does_not_take_a_report_retry(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    new = run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    assert run(db.repository.claim_next(lease_seconds=900)) is None
    claimed = run(db.repository.claim_next(lease_seconds=900, include_reports=True))
    assert claimed.analysis_id == new.analysis_id
    assert claimed.status == "generatingReport"
    assert claimed.transcript


def test_remaining_transcript_blocks_reupload_but_expired_one_does_not(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    existing, created = run(db.repository.reserve(_job(old.session_id)))
    assert not created and existing.analysis_id == old.analysis_id
    db.execute("UPDATE speech_analysis_jobs SET transcript_expires_at=now()-interval '1 second'")
    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    assert error.value.error_code == "RECORDING_REQUIRED"
    new, created = run(db.repository.reserve(_job(old.session_id)))
    assert created and new.analysis_id != old.analysis_id


def test_retry_requires_owner_and_consents_without_an_s3_connection(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    other, _ = db.seed_session()
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(
        database_url=migrated_database_url, session_secret="s" * 32,
    )
    account = replace(ACCOUNT, account_id=owner, consents={})
    app.dependency_overrides[get_current_account] = lambda: account
    path = f"/api/v1/speech-analyses/{old.analysis_id}/retry"
    assert request(app, "POST", path).status_code == 403
    account = replace(ACCOUNT, account_id=other)
    assert request(app, "POST", path).status_code == 404
    account = replace(ACCOUNT, account_id=owner)
    response = request(app, "POST", path)
    assert response.status_code == 202, response.text
    assert response.json()["analysisId"] != old.analysis_id
    assert response.json()["status"] == "sttCompleted"


def test_report_retry_saves_once_without_stt_or_s3(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    old_id = records.job(visit.session_id, "queued")
    bad = _violations(visit)["less_for_unused_card"] | {"analysisId": str(old_id)}
    _run_worker(records, FakeAi(bad))
    owner = str(records.scalar("SELECT user_id FROM profiles WHERE profile_id=%s", (visit.profile_id,)))
    db = _Db(migrated_database_url)
    new = run(db.repository.retry_report(analysis_id=str(old_id), account_id=owner))
    ai = FakeAi(_report(visit, analysis_id=new.analysis_id))

    class NoStorage(FakeAudioStorage):
        async def create_download(self, **kwargs):
            pytest.fail("리포트만 다시 만들 때 S3에서 녹음을 받으면 안 된다")

        async def delete(self, **kwargs):
            pytest.fail("리포트만 다시 만들 때 S3 원본 삭제를 반복하면 안 된다")

    class NoStt:
        async def analyze_speech(self, payload):
            pytest.fail("남아 있는 전사를 재사용해야 한다")

    worker = create_speech_worker(
        jobs_for=lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=900),
        audio_storage=NoStorage(), ai_server=NoStt(),
        open_connection=lambda: connect(migrated_database_url), lease_seconds=900,
        report_generator=VisitReportGenerator(generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS),
    )
    assert run(worker.run_once()) is True
    assert run(worker.run_once()) is False
    assert db.job_row(new.analysis_id)["status"] == "completed"
    assert db.job_row(new.analysis_id)["transcript"] is None
    assert records.scalar("SELECT count(*) FROM life_fact_proposals") == 1
    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=new.analysis_id, account_id=owner))
    assert error.value.error_code == "ANALYSIS_ALREADY_COMPLETED"


def test_transcribing_job_that_has_lost_its_lease_cannot_store_late_stt(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=900))
    db.execute("UPDATE speech_analysis_jobs SET lease_expires_at=now()-interval '1 second'")
    assert run(db.repository.mark_stt_completed(analysis_id=job.analysis_id, transcript={})) is False


def test_repeated_report_failure_requires_latest_id_without_extending_expiry(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    first = run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    run(db.repository.claim_next(lease_seconds=900, include_reports=True))
    run(db.repository.mark_failed(analysis_id=first.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=old.analysis_id, account_id=owner))
    assert error.value.error_code == "ANALYSIS_ALREADY_FAILED"
    second = run(db.repository.retry_report(analysis_id=first.analysis_id, account_id=owner))
    assert second.transcript_expires_at == first.transcript_expires_at
