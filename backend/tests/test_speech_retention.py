"""합성 전사의 실패 보관 기한과 삭제 경로를 실제 격리 PostgreSQL로 검사한다."""

from datetime import timedelta

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services.speech_analysis_jobs import (
    PostgresSpeechAnalysisJobRepository, TRANSCRIPT_RETENTION_SECONDS,
)
from app.services.speech_analysis_pipeline import SpeechAnalysisQueue
from app.workers.base import Worker
from tests.support import run
from tests.test_speech_job_repository import _Db, _generating, TRANSCRIPT


def test_report_failure_retains_only_original_stt_deadline(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, session = db.seed_session()
    job = _generating(db, session)
    initial = db.job_row(job.analysis_id)
    assert TRANSCRIPT_RETENTION_SECONDS == 86400
    assert initial["transcript_expires_at"] - initial["stt_completed_at"] == timedelta(hours=24)

    run(db.repository.mark_failed(analysis_id=job.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    failed = db.job_row(job.analysis_id)
    assert failed["transcript"] == TRANSCRIPT
    assert failed["transcript_deleted_at"] is None
    assert failed["transcript_expires_at"] == initial["transcript_expires_at"]

    retried = run(db.repository.retry_report(analysis_id=job.analysis_id, account_id=owner))
    old = db.job_row(job.analysis_id)
    assert old["transcript"] is None
    assert old["transcript_deleted_at"] is not None
    assert retried.transcript_expires_at == initial["transcript_expires_at"]
    assert retried.stt_completed_at == initial["stt_completed_at"]
    assert db.execute("SELECT count(*) AS n FROM speech_analysis_jobs WHERE transcript IS NOT NULL")[0]["n"] == 1


@pytest.mark.parametrize("expired", [False, True])
def test_failure_discards_expired_transcript_only(migrated_database_url, expired):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _generating(db, session)
    if expired:
        db.execute("UPDATE speech_analysis_jobs SET transcript_expires_at = now() - interval '1 second'")
    before = db.job_row(job.analysis_id)
    run(db.repository.mark_failed(analysis_id=job.analysis_id, error_code="AI_SERVER_ERROR"))
    row = db.job_row(job.analysis_id)
    assert row["status"] == "failed"
    assert row["transcript_expires_at"] == before["transcript_expires_at"]
    assert (row["transcript"] is None) is expired
    assert (row["transcript_deleted_at"] is not None) is expired


@pytest.mark.parametrize("expired", [False, True])
def test_worker_lease_failure_uses_the_same_retention_deadline(migrated_database_url, expired):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _generating(db, session)
    db.execute("UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second'")
    if expired:
        db.execute("UPDATE speech_analysis_jobs SET transcript_expires_at = now() - interval '1 second'")
    before = db.job_row(job.analysis_id)
    assert run(db.repository.expire_leases()) == 1
    row = db.job_row(job.analysis_id)
    assert row["error_code"] == "WORKER_LEASE_EXPIRED"
    assert row["transcript_expires_at"] == before["transcript_expires_at"]
    assert (row["transcript"] is None) is expired
    assert (row["transcript_deleted_at"] is not None) is expired


# 전사 기한 경계. 이 시험 DB에만 `clock_timestamp()`를 대신하는 함수를 두고, 처음 부르면
# 기한 1마이크로초 전을, 그 뒤로는 기한 시각을 돌려준다. 한 문장이 시각을 식마다 따로 읽으면
# 전사는 남기고 삭제 시각만 채워 CHECK (transcript_deleted_at IS NULL OR transcript IS NULL)에 걸린다.
_BOUNDARY = "2030-01-01 00:00:00+00"


def _install_boundary_clock(db: _Db) -> None:
    db.execute("CREATE SCHEMA boundary_clock")
    db.execute("CREATE SEQUENCE boundary_clock.calls")
    db.execute(
        "CREATE FUNCTION boundary_clock.clock_timestamp() RETURNS timestamptz "
        "LANGUAGE plpgsql AS $$ BEGIN "
        "IF nextval('boundary_clock.calls') = 1 THEN "
        f"RETURN timestamptz '{_BOUNDARY}' - interval '1 microsecond'; END IF; "
        f"RETURN timestamptz '{_BOUNDARY}'; END $$"
    )


def _clock_reads(db: _Db) -> int:
    row = db.execute("SELECT last_value, is_called FROM boundary_clock.calls")[0]
    return row["last_value"] if row["is_called"] else 0


def _on_boundary_clock(db: _Db, method: str, **kwargs):
    async def call():
        async with connect(db.dsn) as connection:
            # pg_catalog보다 앞에 두어야 기본 clock_timestamp() 대신 쓰인다.
            await connection.execute("SET search_path TO boundary_clock, pg_catalog, public")
            repository = PostgresSpeechAnalysisJobRepository(connection, lease_seconds=900)
            return await getattr(repository, method)(**kwargs)

    return run(call())


@pytest.mark.parametrize("cleanup", ["mark_failed", "expire_leases"])
def test_failure_at_the_transcript_deadline_reads_the_clock_once(migrated_database_url, cleanup):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _generating(db, session)
    db.execute(
        "UPDATE speech_analysis_jobs SET transcript_expires_at = %s, "
        "lease_expires_at = now() - interval '1 second' WHERE analysis_id = %s",
        (_BOUNDARY, job.analysis_id),
    )
    _install_boundary_clock(db)

    if cleanup == "mark_failed":
        _on_boundary_clock(db, cleanup, analysis_id=job.analysis_id, error_code="AI_SERVER_ERROR")
    else:
        assert _on_boundary_clock(db, cleanup) == 1

    row = db.job_row(job.analysis_id)
    assert row["status"] == "failed"
    # 처음 읽은 시각(기한 1마이크로초 전) 하나로 전사 유지와 삭제 시각을 함께 정한다.
    assert row["transcript"] == TRANSCRIPT
    assert row["transcript_deleted_at"] is None
    assert _clock_reads(db) == 1


def test_failed_transcript_is_deleted_without_any_new_job(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, session = db.seed_session()
    expired = _generating(db, session)
    run(db.repository.mark_failed(analysis_id=expired.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    _, other_session = db.seed_session()
    valid = _generating(db, other_session)
    run(db.repository.mark_failed(analysis_id=valid.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    db.execute(
        "UPDATE speech_analysis_jobs SET transcript_expires_at = now() - interval '1 second' "
        "WHERE analysis_id = %s", (expired.analysis_id,),
    )
    # 기한만 지났다고 DB가 스스로 지우지는 않는다. 사용은 거절하고 worker 정리가 지운다.
    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=expired.analysis_id, account_id=owner))
    assert error.value.error_code == "RECORDING_REQUIRED"
    assert db.job_row(expired.analysis_id)["transcript"] is not None

    async def process(connection, job):
        pytest.fail("새 작업 없이 정리만 해야 한다")

    class NoStorage:
        async def delete(self, **kwargs):
            pytest.fail("전사 DB 정리에 S3 삭제는 필요하지 않다")

    queue = SpeechAnalysisQueue(
        jobs_for=lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=900),
        audio_storage=NoStorage(), resume_reports=True,
    )
    worker = Worker(queue=queue, process=process,
                    open_connection=lambda: connect(migrated_database_url), lease_seconds=900)
    assert run(worker.run_once()) is False
    row = db.job_row(expired.analysis_id)
    assert row["status"] == "failed"
    assert row["error_code"] == "TRANSCRIPT_EXPIRED"
    assert row["transcript"] is None
    assert row["transcript_deleted_at"] is not None
    assert db.job_row(valid.analysis_id)["transcript"] == TRANSCRIPT
    assert run(worker.run_once()) is False
    assert db.job_row(expired.analysis_id)["transcript_deleted_at"] == row["transcript_deleted_at"]


def test_completed_job_deletes_transcript_before_its_deadline(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _generating(db, session)
    before = db.job_row(job.analysis_id)
    run(db.repository.mark_completed(analysis_id=job.analysis_id))
    row = db.job_row(job.analysis_id)
    assert row["status"] == "completed"
    assert row["transcript"] is None
    assert row["transcript_deleted_at"] < before["transcript_expires_at"]


@pytest.mark.parametrize("parent", ["users", "profiles"])
def test_account_or_profile_deletion_removes_failed_transcript(migrated_database_url, parent):
    db = _Db(migrated_database_url)
    owner, session = db.seed_session()
    job = _generating(db, session)
    run(db.repository.mark_failed(analysis_id=job.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    if parent == "users":
        db.execute("DELETE FROM users WHERE user_id = %s", (owner,))
    else:
        db.execute("DELETE FROM profiles WHERE user_id = %s", (owner,))
    assert db.execute("SELECT 1 FROM speech_analysis_jobs WHERE analysis_id = %s", (job.analysis_id,)) == []
