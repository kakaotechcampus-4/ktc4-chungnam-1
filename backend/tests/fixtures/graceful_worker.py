"""Docker 종료 신호 검사 전용. DB, 네트워크, 실제 작업을 쓰지 않는다."""

import asyncio
from contextlib import asynccontextmanager

from app.workers.base import Worker, install_stop_handlers


class Queue:
    name = "synthetic_shutdown"
    unexpected_error_code = "SYNTHETIC_ERROR"

    async def expire_leases(self, connection):
        return 0

    async def claim(self, connection, *, lease_seconds):
        return "synthetic-job"

    async def fail(self, connection, job, *, error_code):
        raise RuntimeError(error_code)


@asynccontextmanager
async def no_connection():
    yield None


async def process(connection, job):
    print("SYNTHETIC_JOB_STARTED", flush=True)
    await asyncio.sleep(3)
    print("SYNTHETIC_JOB_FINISHED", flush=True)


async def main():
    worker = Worker(
        queue=Queue(), process=process, open_connection=no_connection, lease_seconds=10
    )
    install_stop_handlers(worker)
    await worker.run(poll_seconds=1)
    print("SYNTHETIC_WORKER_STOPPED", flush=True)


asyncio.run(main())
