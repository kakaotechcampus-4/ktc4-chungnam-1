"""삭제 실패와 분석 결과를 분리한다. S3와 AI 응답은 합성 대역이다."""

import logging

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import SpeechAnalysisProcessor
from tests.support import run
from tests.test_speech_analyses import (
    ACCOUNT,
    SESSION_ID,
    FakeAiServer,
    FakeAudioStorage,
    FakeReportGenerator,
    harness,
    speech_worker,
    submit,
)
from tests.test_speech_job_repository import TRANSCRIPT, _accept, _Db


class DeleteUnavailable(FakeAudioStorage):
    async def delete(self, *, object_key):
        raise RuntimeError(f"must-not-log-object-key={object_key}")


@pytest.mark.parametrize("make_report", [False, True])
def test_delete_failure_keeps_stt_and_does_not_fail_report(make_report, caplog):
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    failing = DeleteUnavailable()
    failing.objects = storage.objects
    reports = FakeReportGenerator() if make_report else None
    logging.getLogger().addHandler(caplog.handler)
    caplog.set_level(logging.WARNING, logger="saerok.speech_analysis")

    run(speech_worker(jobs, failing, FakeAiServer(), reports).run_once())

    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.status == ("completed" if make_report else "sttCompleted")
    assert job.stt_completed_at is not None
    assert job.audio_deleted_at is None
    assert job.error_code is None
    assert jobs.pending_audio_deletions == {job.object_key}
    assert job.object_key in failing.objects
    assert "audio_deletion_pending" in caplog.text
    assert job.object_key not in caplog.text
    assert "must-not-log" not in caplog.text
    if make_report:
        assert reports.sessions == [SESSION_ID]


def test_analysis_failure_keeps_its_original_error_and_pending_deletion():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    failing = DeleteUnavailable()
    failing.objects = storage.objects

    class UnavailableAi(FakeAiServer):
        async def analyze_speech(self, payload):
            raise AppError(
                status_code=503,
                error_code="AI_SERVER_UNAVAILABLE",
                message="합성 연결 실패",
            )

    reports = FakeReportGenerator()
    run(speech_worker(jobs, failing, UnavailableAi(), reports).run_once())
    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.status == "failed"
    assert job.error_code == "AI_SERVER_UNAVAILABLE"
    assert job.audio_deleted_at is None
    assert jobs.pending_audio_deletions == {job.object_key}
    assert reports.sessions == []


def test_successful_delete_leaves_no_pending_request():
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    run(speech_worker(jobs, storage, FakeAiServer(), FakeReportGenerator()).run_once())
    assert jobs.pending_audio_deletions == set()
    job = run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job.audio_deleted_at is not None


def test_postgres_keeps_transcript_and_durable_delete_request(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    accepted = _accept(db, session)
    claimed = run(db.repository.claim_next(lease_seconds=900))
    storage = DeleteUnavailable()
    storage.objects[accepted.object_key] = b"synthetic-audio"

    async def process():
        async with connect(migrated_database_url) as connection:
            processor = SpeechAnalysisProcessor(
                jobs_for=lambda conn: PostgresSpeechAnalysisJobRepository(
                    conn, lease_seconds=900
                ),
                audio_storage=storage,
                ai_server=FakeAiServer(),
                report_generator=None,
            )
            await processor(connection, claimed)

    run(process())
    row = db.job_row(accepted.analysis_id)
    assert row["status"] == "sttCompleted"
    assert row["transcript"] is not None
    assert row["audio_deleted_at"] is None
    assert row["error_code"] is None
    assert db.execute("SELECT s3_object_key FROM storage_deletion_request_queue") == [
        {"s3_object_key": accepted.object_key}
    ]
    # 새 연결에서 조회하므로 worker 메모리가 아니라 DB에 보관됐는지 검사한다.
    run(db.repository.queue_audio_deletion(analysis_id=accepted.analysis_id))
    assert (
        db.execute("SELECT count(*) AS n FROM storage_deletion_request_queue")[0]["n"]
        == 1
    )
    run(db.repository.mark_audio_deleted(analysis_id=accepted.analysis_id))
    assert db.job_row(accepted.analysis_id)["audio_deleted_at"] is not None
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []
    run(db.repository.queue_audio_deletion(analysis_id=accepted.analysis_id))
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []


def test_delete_completion_rolls_back_with_outer_transaction(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    accepted = _accept(db, session)
    run(db.repository.queue_audio_deletion(analysis_id=accepted.analysis_id))

    async def rolled_back():
        async with connect(migrated_database_url) as conn, conn.transaction():
            jobs = PostgresSpeechAnalysisJobRepository(conn, lease_seconds=900)
            await jobs.mark_audio_deleted(analysis_id=accepted.analysis_id)
            raise RuntimeError("synthetic rollback")

    with pytest.raises(RuntimeError, match="synthetic rollback"):
        run(rolled_back())
    assert db.job_row(accepted.analysis_id)["audio_deleted_at"] is None
    assert (
        db.execute("SELECT count(*) AS n FROM storage_deletion_request_queue")[0]["n"]
        == 1
    )


def test_lease_expiry_queues_only_audio_not_already_deleted(migrated_database_url):
    db = _Db(migrated_database_url)
    pending = []
    for deleted in (False, True):
        _, session = db.seed_session()
        job = _accept(db, session)
        run(db.repository.claim_next(lease_seconds=900))
        run(
            db.repository.mark_stt_completed(
                analysis_id=job.analysis_id, transcript=TRANSCRIPT
            )
        )
        run(db.repository.mark_generating_report(analysis_id=job.analysis_id))
        if deleted:
            run(db.repository.mark_audio_deleted(analysis_id=job.analysis_id))
        else:
            pending.append(job.object_key)
    db.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second'"
    )
    assert run(db.repository.expire_leases()) == 2
    assert [
        r["s3_object_key"]
        for r in db.execute("SELECT s3_object_key FROM storage_deletion_request_queue")
    ] == pending
