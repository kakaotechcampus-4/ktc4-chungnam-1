"""worker 공통 골격 검증. DB 없이 가짜 대기열로 확인한다."""

import logging
from contextlib import asynccontextmanager

from app.core.errors import AppError
from app.workers.base import Worker
from tests.support import run


class FakeQueue:
    name = "synthetic"
    unexpected_error_code = "SYNTHETIC_FAILED"

    def __init__(self, jobs: list[str]) -> None:
        self.jobs = list(jobs)
        self.expired_calls = 0
        self.failed: list[tuple[str, str]] = []

    async def expire_leases(self, connection) -> int:
        self.expired_calls += 1
        return 0

    async def claim(self, connection, *, lease_seconds: int):
        assert lease_seconds == 300
        return self.jobs.pop(0) if self.jobs else None

    async def fail(self, connection, job, *, error_code: str) -> None:
        self.failed.append((job, error_code))


@asynccontextmanager
async def no_connection():
    yield None


def _worker(queue: FakeQueue, process) -> Worker:
    return Worker(
        queue=queue, process=process, open_connection=no_connection, lease_seconds=300
    )


def test_no_waiting_job_does_nothing_but_still_cleans_up_leases():
    queue = FakeQueue([])
    calls = []

    async def process(connection, job):
        calls.append(job)

    assert run(_worker(queue, process).run_once()) is False
    assert calls == []
    assert queue.expired_calls == 1


def test_processed_job_is_not_failed():
    queue = FakeQueue(["job-1"])
    processed = []

    async def process(connection, job):
        processed.append(job)

    assert run(_worker(queue, process).run_once()) is True
    assert processed == ["job-1"]
    assert queue.failed == []


def test_app_error_fails_the_job_with_its_code():
    queue = FakeQueue(["job-1"])

    async def process(connection, job):
        raise AppError(
            status_code=503,
            error_code="AI_SERVER_UNAVAILABLE",
            message="합성 실패",
            retryable=True,
        )

    assert run(_worker(queue, process).run_once()) is True
    assert queue.failed == [("job-1", "AI_SERVER_UNAVAILABLE")]


def test_unexpected_error_uses_the_queue_code_and_logs_only_the_type(caplog):
    queue = FakeQueue(["job-1"])

    async def process(connection, job):
        raise RuntimeError("synthetic-secret-detail")

    caplog.set_level(logging.ERROR, logger="saerok.worker")
    assert run(_worker(queue, process).run_once()) is True

    assert queue.failed == [("job-1", "SYNTHETIC_FAILED")]
    assert "RuntimeError" in caplog.text
    assert "synthetic-secret-detail" not in caplog.text
