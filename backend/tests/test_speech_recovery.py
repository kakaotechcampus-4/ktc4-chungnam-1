"""실제 임시 PostgreSQL, 합성 전사와 외부 API 대역으로 수동 복구를 검사한다."""

import asyncio
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest

from app.api.deps import get_current_account, get_speech_audio_storage
from app.core.config import Settings, get_settings
from app.core.database import connect
from app.core.errors import AppError
from app.main import create_app
from app.services.speech_analysis_jobs import (
    InMemorySpeechAnalysisJobRepository, PostgresSpeechAnalysisJobRepository,
)
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import VisitReportGenerator
from tests.support import request, run
from tests.test_speech_analyses import ACCOUNT, synthetic_wav
from tests.test_speech_analyses import FakeAudioStorage as UploadStorage
from tests.test_speech_job_repository import TRANSCRIPT, _Db, _accept, _generating, _job
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


def _fail_retry(db, owner, analysis_id, **kwargs):
    """`analysis_id`의 리포트를 재요청하고, worker가 가져가 다시 실패한 것으로 만든다."""
    retry = run(db.repository.retry_report(analysis_id=analysis_id, account_id=owner, **kwargs))
    run(db.repository.claim_next(lease_seconds=900, include_reports=True))
    run(db.repository.mark_failed(analysis_id=retry.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    return retry


def test_fourth_report_retry_in_a_session_is_rejected(migrated_database_url):
    """2026-11-09 PM 결정: 리포트 재요청(6-5)은 면회 회차당 3회까지다."""
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    latest = old
    for _ in range(3):
        latest = _fail_retry(db, owner, latest.analysis_id)

    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=latest.analysis_id, account_id=owner))

    assert error.value.status_code == 409
    assert error.value.error_code == "REPORT_RETRY_LIMIT_EXCEEDED"
    assert error.value.retryable is False
    assert db.execute("SELECT count(*) AS n FROM speech_analysis_jobs")[0]["n"] == 4
    # 거절한 재요청은 전사를 옮기거나 지우지 않는다. 기한이 지나면 기존 정리가 지운다.
    assert db.job_row(latest.analysis_id)["transcript"] is not None


def test_retries_are_counted_per_session(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    _fail_retry(db, owner, old.analysis_id, max_retries=1)
    other_owner, other = _failed_report(db)

    retried = run(db.repository.retry_report(
        analysis_id=other.analysis_id, account_id=other_owner, max_retries=1,
    ))
    # 처리 중인 재요청을 다시 보내면 같은 작업을 돌려주고 횟수를 쓰지 않는다.
    again = run(db.repository.retry_report(
        analysis_id=other.analysis_id, account_id=other_owner, max_retries=1,
    ))

    assert retried.analysis_id == again.analysis_id
    assert retried.status == "sttCompleted"


def test_retry_limit_follows_the_setting_through_the_api(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(
        database_url=migrated_database_url, session_secret="s" * 32,
        report_retries_per_session=1,
    )
    app.dependency_overrides[get_current_account] = lambda: replace(ACCOUNT, account_id=owner)
    first = request(app, "POST", f"/api/v1/speech-analyses/{old.analysis_id}/retry")
    assert first.status_code == 202, first.text
    new_id = first.json()["analysisId"]
    run(db.repository.claim_next(lease_seconds=900, include_reports=True))
    run(db.repository.mark_failed(analysis_id=new_id, error_code="AI_SERVER_TIMEOUT"))

    second = request(app, "POST", f"/api/v1/speech-analyses/{new_id}/retry")

    assert second.status_code == 409
    assert second.json()["errorCode"] == "REPORT_RETRY_LIMIT_EXCEEDED"
    assert second.json()["retryable"] is False


def test_expired_transcript_after_the_limit_asks_for_the_recording_again(migrated_database_url):
    """한도는 남은 전사를 다시 쓸 때만 막는다. 전사 기한이 지나면 6-5는 `RECORDING_REQUIRED`이고
    6-2는 기기 녹음을 다시 받는다. 그 재제출은 재요청 횟수에 넣지 않는다(2026-11-09 PM 결정)."""
    db = _Db(migrated_database_url)
    owner, old = _failed_report(db)
    latest = old
    for _ in range(3):
        latest = _fail_retry(db, owner, latest.analysis_id)
    storage = UploadStorage()
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(
        database_url=migrated_database_url, session_secret="s" * 32,
    )
    app.dependency_overrides[get_current_account] = lambda: replace(ACCOUNT, account_id=owner)
    app.dependency_overrides[get_speech_audio_storage] = lambda: storage

    def retry(analysis_id):
        return request(app, "POST", f"/api/v1/speech-analyses/{analysis_id}/retry")

    def upload():
        return request(
            app, "POST", f"/api/v1/visit-sessions/{old.session_id}/speech-analyses",
            data={"participantCount": "2"},
            files={"audio": ("synthetic.wav", synthetic_wav(), "audio/wav")},
        )

    # 전사가 남아 있는 동안은 6-5도 6-2도 받지 않는다.
    assert retry(latest.analysis_id).json()["errorCode"] == "REPORT_RETRY_LIMIT_EXCEEDED"
    assert upload().json()["errorCode"] == "REPORT_RETRY_AVAILABLE"

    # 기한은 지났지만 worker 정리 전이라 전사 행이 남은 경우와, 정리로 지워진 경우 모두 녹음을 다시 받는다.
    db.execute("UPDATE speech_analysis_jobs SET transcript_expires_at=now()-interval '1 second' "
               "WHERE transcript IS NOT NULL")
    expired = retry(latest.analysis_id)
    assert expired.status_code == 409
    assert expired.json()["errorCode"] == "RECORDING_REQUIRED"
    run(db.repository.expire_transcripts())
    assert db.job_row(latest.analysis_id)["transcript"] is None
    assert retry(latest.analysis_id).json()["errorCode"] == "RECORDING_REQUIRED"

    uploaded = upload()
    assert uploaded.status_code == 202, uploaded.text
    new_id = uploaded.json()["analysisId"]
    assert len(storage.objects) == 1
    assert db.job_row(new_id)["retry_of_analysis_id"] is None
    retries = db.execute(
        "SELECT count(*) AS n FROM speech_analysis_jobs "
        "WHERE session_id=%s AND retry_of_analysis_id IS NOT NULL", (old.session_id,),
    )
    assert retries[0]["n"] == 3

    # 재제출한 작업의 리포트가 다시 실패하면 그 전사로는 한도가 적용된다.
    run(db.repository.claim_next(lease_seconds=900))
    run(db.repository.mark_stt_completed(analysis_id=new_id, transcript=TRANSCRIPT))
    run(db.repository.mark_generating_report(analysis_id=new_id))
    run(db.repository.mark_failed(analysis_id=new_id, error_code="AI_SERVER_TIMEOUT"))
    assert retry(new_id).json()["errorCode"] == "REPORT_RETRY_LIMIT_EXCEEDED"
    # 재제출을 횟수에 넣었다면 4번째가 되어 한도 4에서도 거절된다.
    fourth = run(db.repository.retry_report(analysis_id=new_id, account_id=owner, max_retries=4))
    assert fourth.status == "sttCompleted"


def _memory_session_at_limit():
    """메모리 저장소에서 한도 1회를 쓰고 그 재요청도 실패한 회차를 만든다."""
    jobs = InMemorySpeechAnalysisJobRepository()
    jobs.allow_session(account_id="synthetic-account", session_id="synthetic-session")
    first = _job("synthetic-session")
    run(jobs.reserve(first))
    run(jobs.mark_queued(analysis_id=first.analysis_id, size_bytes=100, sha256="a" * 64))
    run(jobs.claim_next(lease_seconds=900))
    run(jobs.mark_stt_completed(analysis_id=first.analysis_id, transcript=TRANSCRIPT))
    run(jobs.mark_failed(analysis_id=first.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    retry = run(jobs.retry_report(analysis_id=first.analysis_id, account_id="synthetic-account",
                                  max_retries=1))
    run(jobs.mark_failed(analysis_id=retry.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    return jobs, retry


def test_in_memory_repository_applies_the_same_limit():
    jobs, retry = _memory_session_at_limit()

    with pytest.raises(AppError) as error:
        run(jobs.retry_report(analysis_id=retry.analysis_id, account_id="synthetic-account",
                              max_retries=1))

    assert error.value.error_code == "REPORT_RETRY_LIMIT_EXCEEDED"


def test_in_memory_repository_asks_for_the_recording_once_the_transcript_expires():
    jobs, retry = _memory_session_at_limit()
    # 메모리 저장소는 만료 정리를 하지 않으므로 기한만 지난 전사가 남는다.
    jobs._jobs[retry.analysis_id] = replace(
        jobs._jobs[retry.analysis_id], transcript_expires_at=datetime.now(UTC) - timedelta(seconds=1),
    )

    with pytest.raises(AppError) as error:
        run(jobs.retry_report(analysis_id=retry.analysis_id, account_id="synthetic-account",
                              max_retries=1))
    uploaded, created = run(jobs.reserve(_job("synthetic-session")))

    assert error.value.error_code == "RECORDING_REQUIRED"
    assert created and uploaded.analysis_id != retry.analysis_id


class _Crash(BaseException):
    """worker 프로세스가 죽은 상황. 골격은 `Exception`만 잡으므로 실패 기록 없이 끝난다."""


def _speech_worker(database_url, ai, *, storage=None, jobs_for=None):
    return create_speech_worker(
        jobs_for=jobs_for or (lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=900)),
        audio_storage=storage or FakeAudioStorage(), ai_server=ai.client(),
        open_connection=lambda: connect(database_url), lease_seconds=900,
        report_generator=VisitReportGenerator(generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS),
    )


def _stt_completed(db, *, hand_off):
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=900))
    assert run(db.repository.mark_stt_completed(
        analysis_id=job.analysis_id, transcript=TRANSCRIPT, hand_off=hand_off,
    ))
    return job


@pytest.mark.parametrize("crash_at", ["queue_audio_deletion", "mark_generating_report"])
def test_job_left_after_stt_is_resumed_once_the_hand_off_ends(migrated_database_url, crash_at):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = str(records.job(visit.session_id, "queued"))
    ai = FakeAi(_report(visit, analysis_id=analysis_id))

    def crashing(connection):
        jobs = PostgresSpeechAnalysisJobRepository(connection, lease_seconds=900)

        async def crash(**kwargs):
            raise _Crash

        setattr(jobs, crash_at, crash)
        return jobs

    with pytest.raises(_Crash):
        run(_speech_worker(migrated_database_url, ai, jobs_for=crashing).run_once())
    db = _Db(migrated_database_url)
    stuck = db.job_row(analysis_id)
    assert stuck["status"] == "sttCompleted" and stuck["transcript"]
    assert stuck["lease_expires_at"] is not None

    storage = FakeAudioStorage()
    worker = _speech_worker(migrated_database_url, ai, storage=storage)
    # 인계 임대 안에서는 STT를 마친 worker가 이어 갈 수 있으므로 가져가지 않는다.
    assert run(worker.run_once()) is False
    assert db.job_row(analysis_id)["status"] == "sttCompleted"

    db.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second' "
        "WHERE analysis_id = %s", (analysis_id,),
    )
    assert run(worker.run_once()) is True
    assert run(worker.run_once()) is False

    row = db.job_row(analysis_id)
    assert (row["status"], row["error_code"], row["attempt_count"]) == ("completed", None, 2)
    assert row["transcript"] is None and row["transcript_deleted_at"] is not None
    assert len(ai.report_requests) == 1
    assert records.scalar("SELECT count(*) FROM life_fact_proposals") == 1
    # 이어받은 리포트 생성은 S3를 부르지 않는다. 빠진 원본 삭제 요청만 대기열에 남긴다.
    assert storage.deleted == []
    queued = {r["s3_object_key"] for r in db.execute("SELECT s3_object_key FROM storage_deletion_request_queue")}
    if crash_at == "queue_audio_deletion":
        assert row["audio_deleted_at"] is None and queued == {row["s3_object_key"]}
    else:
        assert row["audio_deleted_at"] is not None and queued == set()


def test_resume_waits_for_the_hand_off_and_does_not_run_twice(migrated_database_url):
    db = _Db(migrated_database_url)
    job = _stt_completed(db, hand_off=True)
    assert run(db.repository.claim_next(lease_seconds=900, include_reports=True)) is None

    db.execute("UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second'")
    # STT 단독 worker는 리포트 단계를 이어받지 않는다.
    assert run(db.repository.claim_next(lease_seconds=900)) is None
    resumed = run(db.repository.claim_next(lease_seconds=900, include_reports=True))
    assert (resumed.analysis_id, resumed.status) == (job.analysis_id, "generatingReport")
    assert resumed.transcript == TRANSCRIPT
    # 늦게 돌아온 원래 worker는 리포트 생성을 시작하지 못한다.
    assert run(db.repository.mark_generating_report(analysis_id=job.analysis_id)) is False
    assert run(db.repository.claim_next(lease_seconds=900, include_reports=True)) is None


def test_stt_only_result_is_not_handed_to_report_generation(migrated_database_url):
    db = _Db(migrated_database_url)
    job = _stt_completed(db, hand_off=False)
    db.execute("UPDATE speech_analysis_jobs SET stt_completed_at = now() - interval '1 hour'")

    assert db.job_row(job.analysis_id)["lease_expires_at"] is None
    assert run(db.repository.claim_next(lease_seconds=900, include_reports=True)) is None


def test_job_left_after_stt_with_an_expired_transcript_is_not_resumed(migrated_database_url):
    db = _Db(migrated_database_url)
    job = _stt_completed(db, hand_off=True)
    db.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second', "
        "transcript_expires_at = now() - interval '1 second'"
    )

    assert run(db.repository.claim_next(lease_seconds=900, include_reports=True)) is None
    assert run(db.repository.expire_transcripts()) == 1
    row = db.job_row(job.analysis_id)
    assert (row["status"], row["error_code"]) == ("failed", "TRANSCRIPT_EXPIRED")
    assert row["transcript"] is None and row["lease_expires_at"] is None
