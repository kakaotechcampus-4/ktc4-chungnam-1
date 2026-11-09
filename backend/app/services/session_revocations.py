"""폐기한 세션과 이미 쓴 등록 토큰 목록.

세션은 서명한 JWT 라서 발급한 뒤에는 서버가 따로 기억하지 않는다. 로그아웃과 탈퇴
뒤에도 만료 전까지 쓰이지 않게, 폐기한 세션의 `jti` 를 그 세션의 만료 시각까지만
남긴다. 만료가 지난 세션은 서명 확인에서 이미 거절되므로 더 남길 이유가 없다.

등록 토큰도 같은 목록으로 한 번만 쓰게 한다. 동의 제출(API 1-2)이 등록 토큰을 쓰면
그 `jti` 를 토큰 만료 시각까지 남기고, 같은 토큰을 다시 보내면 거절한다. `jti` 는
토큰마다 새로 만든 무작위 값이라 세션과 등록 토큰이 같은 키를 쓰지 않는다.

계정 식별자, 구글 `sub` 와 토큰 원문은 담지 않는다.

API 는 `PostgresSessionRevocationStore` 로 `session_revocations` 테이블에 남긴다.
서버를 다시 띄우거나 여러 개 띄워도 같은 목록을 본다.
"""

import asyncio
from collections.abc import AsyncIterator, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from datetime import UTC, datetime
from typing import Protocol

from app.core.database import DbConnection
from app.services.session_tokens import SessionClaims


class SessionRevocationStore(Protocol):
    async def revoke(self, session: SessionClaims) -> None: ...

    async def is_revoked(self, token_id: str) -> bool: ...

    def consume(
        self, token_id: str, expires_at: datetime
    ) -> AbstractAsyncContextManager[bool]:
        """등록 토큰을 쓴 것으로 남긴다. 처음 쓰면 `True`, 이미 썼으면 `False` 를 준다.

        블록 안에서 예외가 나면 남긴 기록을 되돌려, 필수 동의 누락처럼 계정을 만들지
        못한 제출은 같은 토큰으로 다시 할 수 있다.
        """
        ...


class PostgresSessionRevocationStore:
    """`session_revocations` 에 폐기한 세션과 쓴 등록 토큰을 남긴다.

    만료 비교는 세션 서명 확인과 같은 앱 시각으로 한다. 만료가 지난 행은 다음 폐기나
    등록 토큰 사용 때 지운다. 그 전까지 남아 있어도 `is_revoked` 는 만료 시각을 보고
    무시한다.
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

    @asynccontextmanager
    async def consume(
        self, token_id: str, expires_at: datetime
    ) -> AsyncIterator[bool]:
        """`jti` 를 넣는 트랜잭션 안에서 블록을 실행한다.

        API 는 계정 저장소와 같은 요청 연결을 쓰므로, 블록 안의 계정 생성은 이 트랜잭션의
        savepoint 가 되고 함께 커밋되거나 되돌려진다. 같은 토큰을 동시에 보내면 뒤 요청은
        앞 트랜잭션이 끝날 때까지 기다린 뒤, 앞이 커밋했으면 `False` 를 받는다.
        """
        # 만료가 지난 행은 트랜잭션 밖에서 먼저 지워 계정 생성 동안 잡는 잠금을 줄인다.
        await self._connection.execute(
            "DELETE FROM session_revocations WHERE expires_at <= %s",
            (self._clock(),),
        )
        async with self._connection.transaction():
            cursor = await self._connection.execute(
                "INSERT INTO session_revocations (token_id, expires_at) "
                "VALUES (%s, %s) ON CONFLICT (token_id) DO NOTHING "
                "RETURNING token_id",
                (token_id, expires_at),
            )
            yield await cursor.fetchone() is not None


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

    @asynccontextmanager
    async def consume(
        self, token_id: str, expires_at: datetime
    ) -> AsyncIterator[bool]:
        # PostgreSQL 의 행 잠금처럼 같은 토큰의 다른 제출은 이 블록이 끝날 때까지 기다린다.
        async with self._lock:
            self._prune()
            if token_id in self._expires_at:
                yield False
                return
            self._expires_at[token_id] = expires_at
            try:
                yield True
            except BaseException:
                del self._expires_at[token_id]
                raise

    def __len__(self) -> int:
        return len(self._expires_at)

    def _prune(self) -> None:
        now = self._clock()
        expired = [key for key, at in self._expires_at.items() if at <= now]
        for key in expired:
            del self._expires_at[key]
