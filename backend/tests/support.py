import asyncio
from collections.abc import Coroutine
from typing import Any, TypeVar

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response

T = TypeVar("T")


def run(coroutine: Coroutine[Any, Any, T]) -> T:
    # psycopg 비동기 연결은 Windows 기본 루프(ProactorEventLoop)에서 동작하지 않는다.
    return asyncio.run(coroutine, loop_factory=asyncio.SelectorEventLoop)


def request(
    application: FastAPI,
    method: str,
    path: str,
    *,
    json: dict[str, Any] | None = None,
    data: dict[str, Any] | None = None,
    files: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    raise_app_exceptions: bool = True,
) -> Response:
    async def send() -> Response:
        transport = ASGITransport(
            app=application, raise_app_exceptions=raise_app_exceptions
        )
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            return await client.request(
                method,
                path,
                json=json,
                data=data,
                files=files,
                headers=headers,
            )

    return run(send())
