"""폐기한 세션 목록.

세션은 서명한 JWT 라서 발급한 뒤에는 서버가 따로 기억하지 않는다. 로그아웃과 탈퇴
뒤에도 만료 전까지 쓰이지 않게, 폐기한 세션의 `jti` 를 그 세션의 만료 시각까지만
남긴다. 만료가 지난 세션은 서명 확인에서 이미 거절되므로 더 남길 이유가 없다.

계정 식별자, 구글 `sub` 와 토큰 원문은 담지 않는다. `jti` 는 세션마다 새로 만든
무작위 값이다.

API 는 `PostgresSessionRevocationStore` 로 `session_revocations` 테이블에 남긴다.
서버를 다시 띄우거나 여러 개 띄워도 같은 목록을 본다.
"""

import asyncio
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Protocol

from app.core.database import DbConnection
from app.services.session_tokens import SessionClaims


class SessionRevocationStore(Protocol):
    async def revoke(self, session: SessionClaims) -> None: ...

    async def is_revoked(self, token_id: str) -> bool: ...


class PostgresSessionRevocationStore:
    """`session_revocations` 에 폐기한 세션을 남긴다.

    만료 비교는 세션 서명 확인과 같은 앱 시각으로 한다. 만료가 지난 행은 다음 폐기 때
    지운다. 그 전까지 남아 있어도 `is_revoked` 는 만료 시각을 보고 무시한다.
    """

    def __init__(
        self,
        connection: DbConnection,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._connection = connection
        self._clock = clock or (lambda: datetime.now(UTC))

    async def revoke(self, session: SessionClaims) -> None:
        async with self._connection.transaction():
            await self._connection.execute(
                "DELETE FROM session_revocations WHERE expires_at <= %s",
                (self._clock(),),
            )
            # 같은 세션으로 로그아웃을 두 번 보내도 오류 없이 폐기 상태를 유지한다.
            await self._connection.execute(
                "INSERT INTO session_revocations (token_id, expires_at) "
                "VALUES (%s, %s) "
                "ON CONFLICT (token_id) DO UPDATE SET expires_at = "
                "GREATEST(session_revocations.expires_at, EXCLUDED.expires_at)",
                (session.token_id, session.expires_at),
            )

    async def is_revoked(self, token_id: str) -> bool:
        cursor = await self._connection.execute(
            "SELECT 1 FROM session_revocations "
            "WHERE token_id = %s AND expires_at > %s",
            (token_id, self._clock()),
        )
        return await cursor.fetchone() is not None


class InMemorySessionRevocationStore:
    """DB 없이 인증 경로를 검사하는 테스트용 폐기 목록.

    `InMemoryAccountRepository` 와 같이 프로세스 메모리에만 남는다. 서버를 다시
    시작하면 목록이 비고, 서버를 여러 개 띄우면 서로의 목록을 보지 못하므로 API 에서
    쓰지 않는다.
    """

    def __init__(self, *, clock: Callable[[], datetime] | None = None) -> None:
        self._expires_at: dict[str, datetime] = {}
        self._clock = clock or (lambda: datetime.now(UTC))
        self._lock = asyncio.Lock()

    async def revoke(self, session: SessionClaims) -> None:
        async with self._lock:
            self._prune()
            self._expires_at[session.token_id] = session.expires_at

    async def is_revoked(self, token_id: str) -> bool:
        expires_at = self._expires_at.get(token_id)
        return expires_at is not None and expires_at > self._clock()

    def __len__(self) -> int:
        return len(self._expires_at)

    def _prune(self) -> None:
        now = self._clock()
        expired = [key for key, at in self._expires_at.items() if at <= now]
        for key in expired:
            del self._expires_at[key]
