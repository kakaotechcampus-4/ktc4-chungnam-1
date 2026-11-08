"""리포트 생성이 전사 보관 기한을 넘기거나 지워진 작업의 전사를 보내지 않는지 검사한다.

- 시작 조건: 남은 전사 기한이 생성 단계 임대(생성 제한 시간 + 저장 여유 이상)보다
  짧으면 생성을 시작하지 않고 `TRANSCRIPT_EXPIRED`로 끝낸다.
- 두 번째 호출 직전 확인: 리포트 호출과 변경 제안 호출 사이에 계정, 프로필이나 회차가
  지워지거나, 작업이 끝나거나, 전사 기한이 지나면 변경 제안 호출을 하지 않는다.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 실제 모델은 부르지 않으며
값은 모두 합성 데이터다.
"""

from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services.speech_analysis_jobs import (
    InMemorySpeechAnalysisJobRepository,
    PostgresSpeechAnalysisJobRepository,
    SpeechAnalysisJob,
    SpeechAnalysisStatus,
)
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import VisitReportGenerator
from tests.support import run
from tests.test_speech_job_repository import TRANSCRIPT, _accept, _Db, _generating
from tests.test_visit_report_generator import (
    ANALYSIS_ID,
    NOTHING_SAVED,
    TIME_LIMIT_SECONDS,
    FakeAi,
    FakeAudioStorage,
    _ai_report,
    _connected,
    _connected_generator,
    _evaluated,
    _generate_with,
    _job,
    _report,
    _run_worker,
    _saved_rows,
    _violations,
)
from tests.visit_records import Records

# 테스트 worker와 저장소의 임대 시간(초). 리포트 생성은 남은 전사 기한이 이보다 길어야 시작한다.
LEASE_SECONDS = 900


def _set_transcript_left(execute, analysis_id, seconds: int) -> None:
    execute(
        "UPDATE speech_analysis_jobs "
        "SET transcript_expires_at = now() + (%s * interval '1 second') WHERE analysis_id = %s",
        (seconds, analysis_id),
    )


# ── 시작 조건 ─────────────────────────────────────────────


def test_generation_does_not_start_when_the_transcript_expires_within_the_lease(
    migrated_database_url,
):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=600))
    assert run(db.repository.mark_stt_completed(analysis_id=job.analysis_id, transcript=TRANSCRIPT))
    _set_transcript_left(db.execute, job.analysis_id, LEASE_SECONDS - 60)

    assert run(db.repository.mark_generating_report(analysis_id=job.analysis_id)) is False
    assert db.job_row(job.analysis_id)["status"] == "sttCompleted"

    # 처리 중으로 남기지 않고 다음 정리에서 전사를 지우고 끝낸다.
    assert run(db.repository.expire_transcripts()) == 1
    row = db.job_row(job.analysis_id)
    assert (row["status"], row["error_code"]) == ("failed", "TRANSCRIPT_EXPIRED")
    assert row["transcript"] is None and row["transcript_deleted_at"] is not None


def test_generation_starts_when_the_whole_lease_fits_before_the_transcript_expires(
    migrated_database_url,
):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=600))
    assert run(db.repository.mark_stt_completed(analysis_id=job.analysis_id, transcript=TRANSCRIPT))
    _set_transcript_left(db.execute, job.analysis_id, LEASE_SECONDS + 60)

    assert run(db.repository.expire_transcripts()) == 0
    assert run(db.repository.mark_generating_report(analysis_id=job.analysis_id)) is True
    assert db.job_row(job.analysis_id)["status"] == "generatingReport"


def test_cleanup_keeps_running_and_failed_transcripts_until_their_deadline(migrated_database_url):
    """앞당겨 끝내는 것은 시작을 기다리는 작업뿐이다. 실패 전사는 원래 기한까지 남는다."""
    db = _Db(migrated_database_url)
    _, running_session = db.seed_session()
    running = _generating(db, running_session)
    _, failed_session = db.seed_session()
    failed = _generating(db, failed_session)
    run(db.repository.mark_failed(analysis_id=failed.analysis_id, error_code="AI_SERVER_TIMEOUT"))
    for job in (running, failed):
        _set_transcript_left(db.execute, job.analysis_id, LEASE_SECONDS - 60)

    assert run(db.repository.expire_transcripts()) == 0
    assert db.job_row(running.analysis_id)["transcript"] == TRANSCRIPT
    assert db.job_row(failed.analysis_id)["transcript"] == TRANSCRIPT
    assert db.job_row(failed.analysis_id)["error_code"] == "AI_SERVER_TIMEOUT"


def _failed_retry(records: Records):
    """리포트 생성에 실패한 회차를 6-5로 다시 요청해 둔다. (회차, 재요청 작업, 저장소)."""
    visit = _evaluated(records)
    old_id = records.job(visit.session_id, "queued")
    bad = _violations(visit)["less_for_unused_card"] | {"analysisId": str(old_id)}
    _run_worker(records, FakeAi(bad))
    owner = str(records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    ))
    db = _Db(records.database_url)
    retry = run(db.repository.retry_report(analysis_id=str(old_id), account_id=owner))
    return visit, retry, db


def _report_worker(records: Records, ai: FakeAi):
    return create_speech_worker(
        jobs_for=lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=LEASE_SECONDS),
        audio_storage=FakeAudioStorage(),
        ai_server=ai.client(),
        open_connection=lambda: connect(records.database_url),
        lease_seconds=LEASE_SECONDS,
        report_generator=VisitReportGenerator(
            generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS
        ),
    )


def test_report_retry_expiring_within_the_lease_fails_without_sending(migrated_database_url):
    records = Records(migrated_database_url)
    visit, retry, db = _failed_retry(records)
    _set_transcript_left(records.execute, retry.analysis_id, LEASE_SECONDS - 60)
    ai = FakeAi(_report(visit, analysis_id=retry.analysis_id))

    # 가져갈 작업이 없다. 정리 단계에서 기한 안에 끝낼 수 없는 재요청을 끝낸다.
    assert run(_report_worker(records, ai).run_once()) is False

    assert ai.report_requests == []
    assert _job(records, UUID(retry.analysis_id)) == {
        "status": "failed",
        "error_code": "TRANSCRIPT_EXPIRED",
        "transcript_deleted": True,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED
    # 전사가 없으므로 다시 요청하면 기기 녹음을 다시 보내라고 안내한다.
    owner = str(records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    ))
    with pytest.raises(AppError) as error:
        run(db.repository.retry_report(analysis_id=retry.analysis_id, account_id=owner))
    assert error.value.error_code == "RECORDING_REQUIRED"


def test_report_retry_with_room_for_the_lease_still_completes(migrated_database_url):
    records = Records(migrated_database_url)
    visit, retry, _ = _failed_retry(records)
    _set_transcript_left(records.execute, retry.analysis_id, LEASE_SECONDS + 60)
    ai = FakeAi(_report(visit, analysis_id=retry.analysis_id))

    assert run(_report_worker(records, ai).run_once()) is True

    assert len(ai.report_requests) == 1
    assert _job(records, UUID(retry.analysis_id)) == {
        "status": "completed",
        "error_code": None,
        "transcript_deleted": True,
    }


def test_in_memory_claim_also_requires_the_lease_to_fit():
    jobs = InMemorySpeechAnalysisJobRepository()
    jobs.allow_session(account_id="synthetic-account", session_id="synthetic-session")
    analysis_id = str(uuid4())
    run(jobs.reserve(SpeechAnalysisJob(
        analysis_id=analysis_id, session_id="synthetic-session",
        status=SpeechAnalysisStatus.UPLOADING, participant_count=2,
        object_key=f"temporary/speech/{analysis_id}.wav",
        data_expires_at=datetime.now(UTC) + timedelta(days=1),
    )))
    run(jobs.mark_queued(analysis_id=analysis_id, size_bytes=100, sha256="a" * 64))
    run(jobs.claim_next(lease_seconds=LEASE_SECONDS))
    run(jobs.mark_stt_completed(analysis_id=analysis_id, transcript=TRANSCRIPT))
    run(jobs.mark_failed(analysis_id=analysis_id, error_code="AI_SERVER_TIMEOUT"))
    retry = run(jobs.retry_report(analysis_id=analysis_id, account_id="synthetic-account"))
    jobs._jobs[retry.analysis_id] = replace(
        retry, transcript_expires_at=datetime.now(UTC) + timedelta(seconds=LEASE_SECONDS - 60)
    )

    assert run(jobs.claim_next(lease_seconds=LEASE_SECONDS, include_reports=True)) is None
    claimed = run(jobs.claim_next(lease_seconds=LEASE_SECONDS - 120, include_reports=True))
    assert claimed.analysis_id == retry.analysis_id


# ── 변경 제안 호출 직전 확인 ───────────────────────────────


def _report_then(action):
    """리포트 호출을 처리한 뒤(응답 전) `action`을 실행하는 리포트 생성 함수."""

    def report(request):
        result = _ai_report(request)
        action()
        return result

    return report


@pytest.mark.parametrize("deleted", ["users", "profiles", "visit_sessions"])
def test_deletion_between_the_two_calls_stops_the_proposal_call(
    migrated_database_url, monkeypatch, deleted
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    )
    statements = {
        "users": ("DELETE FROM users WHERE user_id = %s", (user_id,)),
        "profiles": ("DELETE FROM profiles WHERE profile_id = %s", (visit.profile_id,)),
        "visit_sessions": (
            "DELETE FROM visit_sessions WHERE session_id = %s", (visit.session_id,)
        ),
    }
    calls = _connected(
        monkeypatch, report=_report_then(lambda: records.execute(*statements[deleted]))
    )

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert error.value.error_code == "WORKER_LEASE_EXPIRED"
    assert [call["kind"] for call in calls] == ["report"]
    assert records.scalar(
        "SELECT count(*) FROM speech_analysis_jobs WHERE analysis_id = %s", (ANALYSIS_ID,)
    ) == 0


def test_transcript_expiry_between_the_two_calls_stops_the_proposal_call(
    migrated_database_url, monkeypatch
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    calls = _connected(
        monkeypatch,
        report=_report_then(lambda: _set_transcript_left(records.execute, analysis_id, -1)),
    )
    worker = create_speech_worker(
        jobs_for=lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=LEASE_SECONDS),
        audio_storage=FakeAudioStorage(),
        ai_server=FakeAi().client(),
        open_connection=lambda: connect(records.database_url),
        lease_seconds=LEASE_SECONDS,
        report_generator=_connected_generator(),
    )

    assert run(worker.run_once()) is True

    assert [call["kind"] for call in calls] == ["report"]
    assert _job(records, analysis_id) == {
        "status": "failed",
        "error_code": "TRANSCRIPT_EXPIRED",
        "transcript_deleted": True,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED


@pytest.mark.parametrize("change", ["failed_by_cleanup", "lease_ended"])
def test_job_no_longer_generating_stops_the_proposal_call(
    migrated_database_url, monkeypatch, change
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = UUID(ANALYSIS_ID)
    statements = {
        # 임대 만료 정리가 먼저 실패로 끝낸 작업
        "failed_by_cleanup": (
            "UPDATE speech_analysis_jobs SET status = 'failed', "
            "error_code = 'WORKER_LEASE_EXPIRED', lease_expires_at = NULL WHERE analysis_id = %s",
            (analysis_id,),
        ),
        # 임대는 끝났지만 아직 아무도 정리하지 않은 작업
        "lease_ended": (
            "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second' "
            "WHERE analysis_id = %s",
            (analysis_id,),
        ),
    }
    calls = _connected(
        monkeypatch, report=_report_then(lambda: records.execute(*statements[change]))
    )

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert error.value.error_code == "WORKER_LEASE_EXPIRED"
    assert [call["kind"] for call in calls] == ["report"]
    assert _saved_rows(records, visit) == NOTHING_SAVED
