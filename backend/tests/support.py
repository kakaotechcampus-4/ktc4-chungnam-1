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
) -> Response:
    async def send() -> Response:
        transport = ASGITransport(app=application)
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            return await client.request(method, path, json=json)

    return asyncio.run(send())
