"""비동기 파이프라인 worker의 공통 골격.

파이프라인마다 두 가지만 만든다.

- 대기열(`JobQueue`): 테이블별로 작업을 하나 임대해 가져오고, 실패를 기록하고, 임대가
  만료된 작업을 정리한다. 각 메서드는 짧은 트랜잭션 하나로 끝낸다.
- 처리 함수(`JobProcessor`): 가져온 작업 하나로 AI 서버를 호출하고 응답을 검증해 결과를
  저장한다. AI 서버 호출은 트랜잭션 밖에서 하고, 결과 저장만 트랜잭션으로 묶는다.

골격은 한 번 돌 때 임대 만료 정리 → 작업 가져오기 → 처리 순서로 실행한다. 처리 함수가
`AppError`를 내면 그 `error_code`로, 그 밖의 예외는 대기열의 기본 실패 코드로 작업을
실패시킨다. 자동 재시도는 하지 않는다.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from collections.abc import Awaitable, Callable
from contextlib import AbstractAsyncContextManager
from typing import Generic, Protocol, TypeVar

from app.core.config import Settings, get_settings
from app.core.database import DbConnection
from app.core.errors import AppError
from app.core.logging import configure_logging

JobT = TypeVar("JobT")

# 임대 시간 안에 끝나지 않은 작업의 실패 코드. worker가 멈췄거나 처리가 너무 오래 걸렸다.
LEASE_EXPIRED_ERROR = "WORKER_LEASE_EXPIRED"

logger = logging.getLogger("saerok.worker")


class JobQueue(Protocol[JobT]):
    name: str
    # 처리 함수가 `AppError`가 아닌 예외를 냈을 때 남기는 실패 코드.
    unexpected_error_code: str

    async def expire_leases(self, connection: DbConnection) -> int:
        """임대가 만료된 작업을 정리하고 정리한 수를 돌려준다."""
        ...

    async def claim(
        self, connection: DbConnection, *, lease_seconds: int
    ) -> JobT | None:
        """대기 중인 작업 하나를 임대해 돌려준다. 없으면 `None`이다."""
        ...

    async def fail(
        self, connection: DbConnection, job: JobT, *, error_code: str
    ) -> None: ...


JobProcessor = Callable[[DbConnection, JobT], Awaitable[None]]
OpenConnection = Callable[[], AbstractAsyncContextManager[DbConnection]]


class Worker(Generic[JobT]):
    def __init__(
        self,
        *,
        queue: JobQueue[JobT],
        process: JobProcessor[JobT],
        open_connection: OpenConnection,
        lease_seconds: int,
    ) -> None:
        self._queue = queue
        self._process = process
        self._open_connection = open_connection
        self._lease_seconds = lease_seconds

    async def run_once(self) -> bool:
        """작업을 하나 처리했으면 `True`, 대기 작업이 없었으면 `False`다."""
        async with self._open_connection() as connection:
            expired = await self._queue.expire_leases(connection)
            if expired:
                logger.warning(
                    "worker_leases_expired queue=%s count=%s", self._queue.name, expired
                )
            job = await self._queue.claim(connection, lease_seconds=self._lease_seconds)
            if job is None:
                return False
            try:
                await self._process(connection, job)
            except AppError as error:
                await self._queue.fail(connection, job, error_code=error.error_code)
            except Exception as error:
                # 예외 메시지에는 연결 문자열, 객체 키나 AI 응답이 섞일 수 있어 종류만 남긴다.
                logger.error(
                    "worker_job_failed queue=%s error_type=%s",
                    self._queue.name,
                    type(error).__name__,
                )
                await self._queue.fail(
                    connection, job, error_code=self._queue.unexpected_error_code
                )
            return True

    async def run(self, *, poll_seconds: float, once: bool = False) -> None:
        if once:
            processed = await self.run_once()
            logger.info(
                "worker_once_complete queue=%s processed=%s",
                self._queue.name,
                processed,
            )
            return
        logger.info("worker_started queue=%s", self._queue.name)
        while True:
            try:
                processed = await self.run_once()
            except Exception as error:
                logger.error(
                    "worker_loop_failed queue=%s error_type=%s",
                    self._queue.name,
                    type(error).__name__,
                )
                processed = False
            if not processed:
                await asyncio.sleep(poll_seconds)


def run_worker_main(
    *,
    description: str,
    create_worker: Callable[[Settings], Worker],
    poll_seconds: Callable[[Settings], float],
) -> None:
    """worker 실행 진입점. `--once`면 대기 작업을 최대 하나 처리하고 끝낸다."""
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--once",
        action="store_true",
        help="대기 중인 작업을 최대 하나 처리하고 종료합니다.",
    )
    args = parser.parse_args()

    async def main() -> None:
        settings = get_settings()
        configure_logging(settings.log_level)
        worker = create_worker(settings)
        await worker.run(poll_seconds=poll_seconds(settings), once=args.once)

    # psycopg 비동기 연결은 Windows 기본 루프(ProactorEventLoop)에서 동작하지 않는다.
    asyncio.run(main(), loop_factory=asyncio.SelectorEventLoop)
