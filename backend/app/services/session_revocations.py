"""폐기한 세션 목록.

세션은 서명한 JWT 라서 발급한 뒤에는 서버가 따로 기억하지 않는다. 로그아웃과 탈퇴
뒤에도 만료 전까지 쓰이지 않게, 폐기한 세션의 `jti` 를 그 세션의 만료 시각까지만
남긴다. 만료가 지난 세션은 서명 확인에서 이미 거절되므로 더 남길 이유가 없다.

계정 식별자, 구글 `sub` 와 토큰 원문은 담지 않는다. `jti` 는 세션마다 새로 만든
무작위 값이다.
"""

import asyncio
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Protocol

from app.services.session_tokens import SessionClaims


class SessionRevocationStore(Protocol):
    async def revoke(self, session: SessionClaims) -> None: ...

    async def is_revoked(self, token_id: str) -> bool: ...


class InMemorySessionRevocationStore:
    """개발 검증 전용 폐기 목록.

    `InMemoryAccountRepository` 와 같이 프로세스 메모리에만 남는다. 서버를 다시
    시작하면 목록이 비므로, 그 전에 폐기한 세션은 만료(기본 1시간)까지 다시 통과한다.
    서버를 여러 개 띄우면 서로의 목록을 보지 못한다. 계정 저장소를 DB 에 연결할 때
    함께 옮긴다.
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
