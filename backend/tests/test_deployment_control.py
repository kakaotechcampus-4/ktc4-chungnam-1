"""합성 PostgreSQL에서 배포 중 접수와 실제 처리 구간을 검사한다."""
import asyncio
from uuid import uuid4

import pytest
from alembic import command
from sqlalchemy.exc import ProgrammingError

from app.core.database import connect
from app.core.errors import AppError
from app.ops.deployment_control import run as control
from app.services import deployment_control as gate
from app.services.card_sets import start_card_generation
from app.workers.base import Worker
from tests.card_fixtures import query
from tests.support import run
from tests.test_short_speech_transcription import harness, submit
from tests.test_speech_job_repository import _Db, _job, _generating


def test_default_status_is_read_only_and_admissions_open(migrated_database_url):
    before = query(migrated_database_url, "SELECT * FROM deployment_control")
    status = run(control(migrated_database_url))
    assert status["readOnly"] and not status["admissionsPaused"]
    assert not status["workerClaimsPaused"] and not status["analysisDrained"]
    assert not any(status["counts"].values())
    assert query(migrated_database_url, "SELECT * FROM deployment_control") == before


def test_state_changes_require_confirmation_and_pause_order(migrated_database_url):
    with pytest.raises(ValueError, match="EXPLICIT_CONFIRMATION_REQUIRED"):
        run(control(migrated_database_url, "pause-all"))
    with pytest.raises(ValueError, match="PAUSE_ADMISSIONS_FIRST"):
        run(control(migrated_database_url, "pause-workers", confirm=True))
    assert run(control(migrated_database_url, "pause-admissions", confirm=True))["admissionsPaused"]
    assert run(control(migrated_database_url, "pause-workers", confirm=True))["analysisDrained"]
    status = run(control(migrated_database_url, "resume-workers", confirm=True))
    assert status["admissionsPaused"] and not status["workerClaimsPaused"]
    assert not run(control(migrated_database_url, "resume-all", confirm=True))["admissionsPaused"]


def test_paused_recording_and_retry_do_not_create_jobs(migrated_database_url):
    db = _Db(migrated_database_url)
    owner, session = db.seed_session()
    failed = _generating(db, session)
    run(db.repository.mark_failed(analysis_id=failed.analysis_id, error_code="REPORT_GENERATION_FAILED"))
    before = db.execute("SELECT * FROM speech_analysis_jobs")
    run(control(migrated_database_url, "pause-all", confirm=True))
    for call in (db.repository.reserve(_job(session)),
                 db.repository.retry_report(analysis_id=failed.analysis_id, account_id=owner)):
        with pytest.raises(AppError) as error:
            run(call)
        assert error.value.status_code == 503
        assert error.value.error_code == "SERVICE_MAINTENANCE"
        assert error.value.retryable is True
    assert db.execute("SELECT * FROM speech_analysis_jobs") == before


def test_paused_short_transcription_returns_contract_without_external_calls(migrated_database_url):
    run(control(migrated_database_url, "pause-all", confirm=True))
    app, storage, ai = harness(migrated_database_url)
    response = submit(app)
    assert response.status_code == 503
    assert response.json()["errorCode"] == "SERVICE_MAINTENANCE"
    assert response.json()["retryable"] is True
    assert storage.objects == {} and storage.deleted == [] and ai.payloads == []


def test_card_admission_guard_runs_before_insert(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            await gate.set_control(connection, "pause-all")
            with pytest.raises(AppError) as error:
                await start_card_generation(connection, uuid4(), model="synthetic", prompt_version=2, start_timeout_seconds=60)
            assert error.value.error_code == "SERVICE_MAINTENANCE"
    run(scenario())
    assert query(migrated_database_url, "SELECT count(*) n FROM card_sets") == [{"n": 0}]


@pytest.mark.parametrize("raise_error", [False, True])
def test_short_transcription_activity_survives_pause_and_is_released(migrated_database_url, raise_error):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            try:
                async with gate.short_speech_admission(connection):
                    state = await control(migrated_database_url, "pause-all", confirm=True)
                    assert state["counts"]["short_speech_executions"] == 1
                    assert not state["analysisDrained"]
                    if raise_error:
                        raise ValueError("synthetic")
            except ValueError:
                assert raise_error
            assert (await control(migrated_database_url))["analysisDrained"]
    run(scenario())


def test_pause_waits_for_inflight_admission_commit(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            async with connection.transaction():
                await gate.assert_admission_open(connection)
                pause = asyncio.create_task(control(migrated_database_url, "pause-all", confirm=True))
                await asyncio.sleep(.1)
                assert not pause.done()
            assert (await asyncio.wait_for(pause, 2))["admissionsPaused"]
            async with connection.transaction():
                with pytest.raises(AppError):
                    await gate.assert_admission_open(connection)
    run(scenario())


@pytest.mark.parametrize("failure", [None, "app", "unexpected", "cancel"])
def test_worker_finishes_current_job_but_does_not_claim_next(migrated_database_url, failure):
    async def scenario():
        started, finish = asyncio.Event(), asyncio.Event()
        claims, failed = [], []
        class Queue:
            name, unexpected_error_code = "synthetic", "SYNTHETIC_FAILED"
            async def expire_leases(self, connection):
                return 0
            async def claim(self, connection, **kwargs):
                claims.append(1)
                return "job"
            async def fail(self, connection, job, *, error_code):
                failed.append(error_code)
        async def process(connection, job):
            started.set()
            await finish.wait()
            if failure == "app":
                raise AppError(status_code=503, error_code="TEST_ERROR", message="합성 오류")
            if failure == "unexpected":
                raise RuntimeError("synthetic")
        worker = Worker(queue=Queue(), process=process,
                        open_connection=lambda: connect(migrated_database_url),
                        lease_seconds=60, control_deployment=True)
        task = asyncio.create_task(worker.run_once())
        await asyncio.wait_for(started.wait(), 2)
        state = await control(migrated_database_url, "pause-all", confirm=True)
        assert state["counts"]["worker_executions"] == 1
        assert not state["analysisDrained"]
        assert not task.done()
        if failure == "cancel":
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
        else:
            finish.set()
            assert await task is True
        assert await worker.run_once() is False
        assert claims == [1]
        assert failed == ({"app": ["TEST_ERROR"], "unexpected": ["SYNTHETIC_FAILED"]}.get(failure, []))
        assert (await control(migrated_database_url))["analysisDrained"]
    run(scenario())


def test_empty_claim_and_claim_exception_do_not_leave_activity(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            async def empty():
                return None
            async def broken():
                raise RuntimeError("synthetic")
            assert await gate.claim_job(connection, empty) is None
            with pytest.raises(RuntimeError, match="synthetic"):
                await gate.claim_job(connection, broken)
            assert (await gate.snapshot(connection))["counts"]["worker_executions"] == 0
    run(scenario())


def test_migration_downgrade_does_not_silently_reopen_paused_service(migrated_database_url, alembic_config):
    run(control(migrated_database_url, "pause-all", confirm=True))
    with pytest.raises(ProgrammingError, match="Resume deployment control"):
        command.downgrade(alembic_config, "e84b1c6da032")
    assert run(control(migrated_database_url))["admissionsPaused"]
    run(control(migrated_database_url, "resume-all", confirm=True))
    command.downgrade(alembic_config, "e84b1c6da032")
    command.upgrade(alembic_config, "head")
    assert not run(control(migrated_database_url))["admissionsPaused"]
