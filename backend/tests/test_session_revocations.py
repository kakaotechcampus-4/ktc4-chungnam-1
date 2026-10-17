"""`session_revocations` 에 폐기 기록을 남기는 저장소 검사.

실제 PostgreSQL 이 필요하다. 임시 DB fixture 와 실행 조건은 `conftest.py` 에 있다.
`jti` 와 계정 식별자는 모두 합성 값이다.
"""

from datetime import UTC, datetime, timedelta

from app.core.database import connect
from app.services.session_revocations import PostgresSessionRevocationStore
from app.services.session_tokens import SessionClaims
from tests.support import run

NOW = datetime(2026, 10, 17, 9, tzinfo=UTC)


def _claims(token_id: str, expires_at: datetime) -> SessionClaims:
    return SessionClaims(
        account_id="synthetic-account", token_id=token_id, expires_at=expires_at
    )


def test_revocation_is_visible_from_a_new_connection(migrated_database_url):
    async def scenario() -> tuple[bool, bool]:
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            await store.revoke(_claims("revoked-jti", NOW + timedelta(hours=1)))
        # 다른 연결은 다른 API 프로세스나 다시 띄운 서버와 같다.
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            return (
                await store.is_revoked("revoked-jti"),
                await store.is_revoked("other-jti"),
            )

    revoked, other = run(scenario())

    assert revoked is True
    assert other is False


def test_expired_revocations_are_ignored_then_removed(migrated_database_url):
    clock = {"now": NOW}

    async def scenario() -> tuple[bool, bool, list[str]]:
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(
                connection, clock=lambda: clock["now"]
            )
            await store.revoke(_claims("old-jti", NOW + timedelta(minutes=5)))
            before = await store.is_revoked("old-jti")

            clock["now"] = NOW + timedelta(minutes=10)
            after = await store.is_revoked("old-jti")
            await store.revoke(_claims("new-jti", clock["now"] + timedelta(hours=1)))
            cursor = await connection.execute(
                "SELECT token_id FROM session_revocations ORDER BY token_id"
            )
            rows = [row["token_id"] for row in await cursor.fetchall()]
            return before, after, rows

    before, after, rows = run(scenario())

    assert before is True
    # 만료된 세션은 서명 확인에서 이미 거절되므로 폐기 기록을 남기지 않는다.
    assert after is False
    assert rows == ["new-jti"]


def test_revoking_the_same_session_twice_keeps_it_revoked(migrated_database_url):
    async def scenario() -> tuple[bool, int]:
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            claims = _claims("same-jti", NOW + timedelta(hours=1))
            await store.revoke(claims)
            await store.revoke(claims)
            cursor = await connection.execute(
                "SELECT count(*) AS n FROM session_revocations"
            )
            return await store.is_revoked("same-jti"), (await cursor.fetchone())["n"]

    revoked, count = run(scenario())

    assert revoked is True
    assert count == 1
