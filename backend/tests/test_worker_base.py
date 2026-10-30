"""worker 공통 골격 검증. DB 없이 가짜 대기열로 확인한다."""

import asyncio
import logging
import signal
from contextlib import asynccontextmanager

from app.core.errors import AppError
from app.workers.base import Worker, install_stop_handlers
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


async def _never_called(connection, job):
    raise AssertionError("종료 요청 뒤에는 작업을 가져가지 않아야 한다")


def test_stop_request_finishes_the_current_job_and_takes_no_more():
    queue = FakeQueue(["job-1", "job-2"])
    processed = []

    async def process(connection, job):
        # 처리 중에 종료 신호가 온 상황
        worker.request_stop()
        await asyncio.sleep(0)
        processed.append(job)

    worker = _worker(queue, process)
    run(asyncio.wait_for(worker.run(poll_seconds=60), timeout=5))

    assert processed == ["job-1"]
    assert queue.jobs == ["job-2"]
    assert queue.failed == []


def test_stop_request_during_lease_cleanup_claims_nothing():
    queue = FakeQueue(["job-1"])
    worker = _worker(queue, _never_called)
    cleanup = queue.expire_leases

    async def cleanup_then_stop(connection):
        worker.request_stop()
        return await cleanup(connection)

    queue.expire_leases = cleanup_then_stop

    assert run(worker.run_once()) is False
    assert queue.jobs == ["job-1"]


def test_stop_request_wakes_an_idle_worker_without_waiting_for_the_poll():
    queue = FakeQueue([])
    worker = _worker(queue, _never_called)

    async def scenario():
        asyncio.get_running_loop().call_later(0.05, worker.request_stop)
        await asyncio.wait_for(worker.run(poll_seconds=60), timeout=5)

    run(scenario())
    assert queue.expired_calls == 1


def test_first_signal_stops_the_worker_and_the_second_is_left_to_the_default():
    queue = FakeQueue([])
    worker = _worker(queue, _never_called)
    previous = {signum: signal.getsignal(signum) for signum in (signal.SIGTERM, signal.SIGINT)}

    async def scenario():
        install_stop_handlers(worker)
        asyncio.get_running_loop().call_later(0.05, signal.raise_signal, signal.SIGINT)
        await asyncio.wait_for(worker.run(poll_seconds=60), timeout=5)

    try:
        run(scenario())
        # 받은 신호만 기본 동작으로 돌아가고, 받지 않은 SIGTERM은 그대로 처리기가 받는다.
        assert signal.getsignal(signal.SIGINT) is signal.default_int_handler
        assert callable(signal.getsignal(signal.SIGTERM))
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
