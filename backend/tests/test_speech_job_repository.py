"""PostgreSQL 음성 분석 작업 저장소 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest
from psycopg.rows import dict_row

from app.core.database import connect, psycopg_dsn
from app.core.errors import AppError
from app.services.speech_analysis_jobs import (
    PostgresSpeechAnalysisJobRepository,
    SpeechAnalysisJob,
    SpeechAnalysisStatus,
)
from tests.support import run

TRANSCRIPT = {
    "durationMs": 3200,
    "segments": [
        {"startMs": 0, "endMs": 3200, "speakerLabel": "SPEAKER_00", "text": "합성 발화"}
    ],
}


class _PerCallRepository:
    """호출마다 연결을 열어 저장소 메서드를 실행한다. 테스트의 `run`은 호출마다 새
    이벤트 루프를 쓰므로 연결을 호출 사이에 이어 쓸 수 없다."""

    def __init__(self, database_url: str) -> None:
        self._database_url = database_url

    def __getattr__(self, name: str):
        async def call(*args, **kwargs):
            async with connect(self._database_url) as connection:
                repository = PostgresSpeechAnalysisJobRepository(
                    connection, lease_seconds=900
                )
                return await getattr(repository, name)(*args, **kwargs)

        return call


class _Db:
    def __init__(self, database_url: str) -> None:
        self.dsn = psycopg_dsn(database_url)
        self.repository = _PerCallRepository(database_url)

    def execute(self, query: str, params: tuple = ()) -> list[dict]:
        with psycopg.connect(self.dsn, autocommit=True, row_factory=dict_row) as conn:
            cursor = conn.execute(query, params)
            return cursor.fetchall() if cursor.description else []

    def seed_session(self, *, evaluated: bool = True) -> tuple[str, str]:
        """계정, 프로필과 회차를 만들고 (계정 ID, 회차 ID)를 돌려준다."""
        user_id = self.execute(
            "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id",
            (f"synthetic-sub-{uuid4().hex[:8]}",),
        )[0]["user_id"]
        profile_id = self.execute(
            "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage) "
            "VALUES (%s, '합성 이름', 'female', '1943-03-12', 'unknown') "
            "RETURNING profile_id",
            (user_id,),
        )[0]["profile_id"]
        if evaluated:
            session_id = self.execute(
                "INSERT INTO visit_sessions "
                "(profile_id, evaluation_satisfaction, evaluation_reaction, evaluated_at) "
                "VALUES (%s, 4, 'pleased', now()) RETURNING session_id",
                (profile_id,),
            )[0]["session_id"]
        else:
            session_id = self.execute(
                "INSERT INTO visit_sessions (profile_id) VALUES (%s) "
                "RETURNING session_id",
                (profile_id,),
            )[0]["session_id"]
        return str(user_id), str(session_id)

    def job_row(self, analysis_id: str) -> dict:
        return self.execute(
            "SELECT * FROM speech_analysis_jobs WHERE analysis_id = %s", (analysis_id,)
        )[0]


def _job(session_id: str) -> SpeechAnalysisJob:
    analysis_id = str(uuid4())
    return SpeechAnalysisJob(
        analysis_id=analysis_id,
        session_id=session_id,
        status=SpeechAnalysisStatus.UPLOADING,
        participant_count=2,
        object_key=f"temporary/speech/{analysis_id}.wav",
        data_expires_at=datetime.now(UTC) + timedelta(days=1),
    )


def _accept(db: _Db, session_id: str) -> SpeechAnalysisJob:
    job, created = run(db.repository.reserve(_job(session_id)))
    assert created
    return run(
        db.repository.mark_queued(
            analysis_id=job.analysis_id, size_bytes=3200, sha256="a" * 64
        )
    )


def test_submission_requires_an_owned_and_evaluated_session(migrated_database_url):
    db = _Db(migrated_database_url)
    account_id, session_id = db.seed_session()
    other_account, other_session = db.seed_session()
    _, unevaluated = db.seed_session(evaluated=False)
    unevaluated_owner = db.execute(
        "SELECT p.user_id FROM visit_sessions v JOIN profiles p USING (profile_id) "
        "WHERE v.session_id = %s",
        (unevaluated,),
    )[0]["user_id"]

    run(db.repository.assert_session_access(account_id=account_id, session_id=session_id))

    for account, session in (
        (account_id, other_session),  # 다른 계정의 회차
        (account_id, str(uuid4())),  # 없는 회차
        (account_id, "not-a-uuid"),
    ):
        with pytest.raises(AppError) as excinfo:
            run(db.repository.assert_session_access(account_id=account, session_id=session))
        assert (excinfo.value.status_code, excinfo.value.error_code) == (
            404,
            "VISIT_SESSION_NOT_FOUND",
        )
    with pytest.raises(AppError) as excinfo:
        run(
            db.repository.assert_session_access(
                account_id=str(unevaluated_owner), session_id=unevaluated
            )
        )
    assert (excinfo.value.status_code, excinfo.value.error_code) == (
        409,
        "EVALUATION_REQUIRED",
    )
    del other_account


def test_reserve_reuses_the_active_job_and_queues_it(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session_id = db.seed_session()

    first, created = run(db.repository.reserve(_job(session_id)))
    again, created_again = run(db.repository.reserve(_job(session_id)))
    queued = run(
        db.repository.mark_queued(
            analysis_id=first.analysis_id, size_bytes=3200, sha256="a" * 64
        )
    )

    assert (created, created_again) == (True, False)
    assert again.analysis_id == first.analysis_id
    assert again.status == SpeechAnalysisStatus.UPLOADING
    assert queued.status == SpeechAnalysisStatus.QUEUED
    row = db.job_row(first.analysis_id)
    assert row["participant_count"] == 2
    assert row["lease_expires_at"] is None


def test_discarded_upload_allows_a_new_submission(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session_id = db.seed_session()
    first, _ = run(db.repository.reserve(_job(session_id)))

    run(db.repository.discard_upload(analysis_id=first.analysis_id))
    second, created = run(db.repository.reserve(_job(session_id)))

    assert created and second.analysis_id != first.analysis_id
    # 지운 작업의 원본 키는 S3 삭제 대기열에 들어간다.
    queued_keys = [
        row["s3_object_key"]
        for row in db.execute("SELECT s3_object_key FROM storage_deletion_request_queue")
    ]
    assert queued_keys == [first.object_key]


def test_worker_flow_keeps_the_transcript_only_until_completion(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session_id = db.seed_session()
    accepted = _accept(db, session_id)

    claimed = run(db.repository.claim_next(lease_seconds=600))
    run(db.repository.mark_audio_deleted(analysis_id=accepted.analysis_id))
    run(
        db.repository.mark_stt_completed(
            analysis_id=accepted.analysis_id, transcript=TRANSCRIPT
        )
    )
    after_stt = db.job_row(accepted.analysis_id)
    run(db.repository.mark_generating_report(analysis_id=accepted.analysis_id))
    generating = db.job_row(accepted.analysis_id)
    run(db.repository.mark_completed(analysis_id=accepted.analysis_id))
    completed = db.job_row(accepted.analysis_id)

    assert claimed.analysis_id == accepted.analysis_id
    assert claimed.status == SpeechAnalysisStatus.TRANSCRIBING
    assert after_stt["status"] == "sttCompleted"
    assert after_stt["transcript"] == TRANSCRIPT
    assert after_stt["transcript_expires_at"] - after_stt["stt_completed_at"] == (
        timedelta(hours=24)
    )
    assert generating["status"] == "generatingReport"
    assert generating["lease_expires_at"] is not None
    assert completed["status"] == "completed"
    assert completed["transcript"] is None
    assert completed["transcript_deleted_at"] is not None


def test_failed_job_after_acceptance_is_not_submitted_again(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session_id = db.seed_session()
    accepted = _accept(db, session_id)
    run(db.repository.claim_next(lease_seconds=600))
    run(
        db.repository.mark_failed(
            analysis_id=accepted.analysis_id, error_code="AI_SERVER_ERROR"
        )
    )

    existing, created = run(db.repository.reserve(_job(session_id)))

    assert created is False
    assert existing.analysis_id == accepted.analysis_id
    assert existing.status == SpeechAnalysisStatus.FAILED


def test_expired_transcript_is_deleted_and_the_job_fails(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session_id = db.seed_session()
    accepted = _accept(db, session_id)
    run(db.repository.claim_next(lease_seconds=600))
    run(
        db.repository.mark_stt_completed(
            analysis_id=accepted.analysis_id, transcript=TRANSCRIPT
        )
    )
    db.execute(
        "UPDATE speech_analysis_jobs SET transcript_expires_at = now() - interval '1 second' "
        "WHERE analysis_id = %s",
        (accepted.analysis_id,),
    )

    expired = run(db.repository.expire_transcripts())

    row = db.job_row(accepted.analysis_id)
    assert expired == 1
    assert (row["status"], row["error_code"]) == ("failed", "TRANSCRIPT_EXPIRED")
    assert row["transcript"] is None
    assert row["transcript_deleted_at"] is not None


def test_status_is_read_only_by_the_owning_account(migrated_database_url):
    db = _Db(migrated_database_url)
    account_id, session_id = db.seed_session()
    other_account, _ = db.seed_session()
    accepted = _accept(db, session_id)

    mine = run(
        db.repository.get_for_account(
            analysis_id=accepted.analysis_id, account_id=account_id
        )
    )
    theirs = run(
        db.repository.get_for_account(
            analysis_id=accepted.analysis_id, account_id=other_account
        )
    )

    assert mine is not None and mine.analysis_id == accepted.analysis_id
    assert theirs is None


def test_jobs_whose_lease_expired_are_cleaned_up(migrated_database_url):
    db = _Db(migrated_database_url)
    _, uploading_session = db.seed_session()
    _, processing_session = db.seed_session()
    stalled_upload, _ = run(db.repository.reserve(_job(uploading_session)))
    stalled = _accept(db, processing_session)
    run(db.repository.claim_next(lease_seconds=600))
    db.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second'"
    )

    cleaned = run(db.repository.expire_leases())

    assert cleaned == 2
    # 업로드 중에 멈춘 작업은 접수 전 실패와 같으므로 지우고 다시 제출할 수 있게 한다.
    assert db.execute(
        "SELECT 1 FROM speech_analysis_jobs WHERE analysis_id = %s",
        (stalled_upload.analysis_id,),
    ) == []
    queued_keys = [
        row["s3_object_key"]
        for row in db.execute("SELECT s3_object_key FROM storage_deletion_request_queue")
    ]
    assert stalled_upload.object_key in queued_keys
    # 처리 중에 멈춘 작업은 실패로 끝낸다.
    row = db.job_row(stalled.analysis_id)
    assert (row["status"], row["error_code"]) == ("failed", "WORKER_LEASE_EXPIRED")
    assert row["lease_expires_at"] is None
