"""`session_revocations` 에 폐기 기록을 남기는 저장소 검사.

실제 PostgreSQL 이 필요하다. 임시 DB fixture 와 실행 조건은 `conftest.py` 에 있다.
`jti` 와 계정 식별자는 모두 합성 값이다. 세션 폐기와 함께, 등록 토큰을 한 번만 쓰게
하는 `consume` 도 검사한다.
"""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest

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


REGISTRATION_EXPIRES_AT = NOW + timedelta(minutes=10)


def test_consumed_registration_token_is_refused_from_a_new_connection(
    migrated_database_url,
):
    async def scenario() -> tuple[bool, bool, bool]:
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            async with store.consume(
                "registration-jti", REGISTRATION_EXPIRES_AT
            ) as first:
                pass
        # 다른 연결은 다른 API 프로세스나 다시 띄운 서버와 같다.
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            async with store.consume(
                "registration-jti", REGISTRATION_EXPIRES_AT
            ) as again:
                pass
            async with store.consume("other-jti", REGISTRATION_EXPIRES_AT) as other:
                pass
        return first, again, other

    assert run(scenario()) == (True, False, True)


def test_consume_is_undone_when_the_block_fails(migrated_database_url):
    async def scenario() -> bool:
        async with connect(migrated_database_url) as connection:
            store = PostgresSessionRevocationStore(connection, clock=lambda: NOW)
            # 필수 동의 누락처럼 계정을 만들지 못한 제출이다.
            with pytest.raises(RuntimeError):
                async with store.consume(
                    "retry-jti", REGISTRATION_EXPIRES_AT
                ) as first:
                    assert first is True
                    raise RuntimeError("계정을 만들지 못함")
            async with store.consume(
                "retry-jti", REGISTRATION_EXPIRES_AT
            ) as again:
                return again

    assert run(scenario()) is True


def test_second_consume_of_the_same_token_waits_then_is_refused(
    migrated_database_url,
):
    async def scenario() -> tuple[bool, bool, bool]:
        async with (
            connect(migrated_database_url) as first_connection,
            connect(migrated_database_url) as second_connection,
        ):
            first_store = PostgresSessionRevocationStore(
                first_connection, clock=lambda: NOW
            )
            second_store = PostgresSessionRevocationStore(
                second_connection, clock=lambda: NOW
            )

            async def submit_again() -> bool:
                async with second_store.consume(
                    "same-registration-jti", REGISTRATION_EXPIRES_AT
                ) as fresh:
                    return fresh

            async with first_store.consume(
                "same-registration-jti", REGISTRATION_EXPIRES_AT
            ) as first:
                second = asyncio.create_task(submit_again())
                await asyncio.sleep(0.5)
                # 앞 제출의 트랜잭션이 끝나기 전에는 뒤 제출이 결과를 받지 않는다.
                waiting = not second.done()
            return first, waiting, await second

    assert run(scenario()) == (True, True, False)
