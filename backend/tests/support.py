import asyncio
from typing import Any

from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response


def request(
    application: FastAPI,
    method: str,
    path: str,
    *,
    json: dict[str, Any] | None = None,
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
            return await client.request(method, path, json=json, headers=headers)

    return asyncio.run(send())
