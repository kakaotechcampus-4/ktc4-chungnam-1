"""생성 스레드가 재전송하기 전에 worker 이벤트 루프에서 업무 조건을 재확인한다."""
import asyncio
from collections.abc import Awaitable, Callable


def retry_guard(check: Callable[[], Awaitable[None]]) -> Callable[[float], None]:
    loop = asyncio.get_running_loop()

    def guard(remaining: float) -> None:
        future = asyncio.run_coroutine_threadsafe(check(), loop)
        try:
            future.result(timeout=max(0.0, remaining))
        except BaseException:
            future.cancel()
            raise

    return guard
