"""계정별 동시 처리 칸(`account_slot`) 검증. 임시 DB에서 연결 여러 개로 확인한다."""

import pytest

from app.core.database import connect
from app.services.account_slots import account_slot
from tests.support import run

ACCOUNT = "00000000-0000-0000-0000-0000000000b1"
OTHER = "00000000-0000-0000-0000-0000000000b2"


def test_slot_is_released_on_the_same_connection_even_after_an_error(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as holder, connect(migrated_database_url) as other:
            with pytest.raises(RuntimeError):
                async with account_slot(holder, scope="synthetic", account_id=ACCOUNT, limit=1) as held:
                    assert held
                    async with account_slot(other, scope="synthetic", account_id=ACCOUNT, limit=1) as busy:
                        assert not busy
                    raise RuntimeError("합성 실패")
            # 앞 연결이 열려 있어도 칸이 비었다. 연결을 닫을 때까지 기다리지 않는다.
            async with account_slot(other, scope="synthetic", account_id=ACCOUNT, limit=1) as again:
                assert again
            rows = await (await holder.execute(
                "SELECT count(*) AS n FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
            )).fetchone()
            assert rows["n"] == 0

    run(scenario())


def test_slots_are_counted_per_account_and_scope(migrated_database_url):
    async def scenario():
        async with (
            connect(migrated_database_url) as first,
            connect(migrated_database_url) as second,
            connect(migrated_database_url) as third,
        ):
            async with (
                account_slot(first, scope="synthetic", account_id=ACCOUNT, limit=2) as one,
                account_slot(second, scope="synthetic", account_id=ACCOUNT, limit=2) as two,
            ):
                async with account_slot(third, scope="synthetic", account_id=ACCOUNT, limit=2) as full:
                    assert (one, two, full) == (True, True, False)
                async with account_slot(third, scope="synthetic", account_id=OTHER, limit=2) as other_account:
                    assert other_account
                async with account_slot(third, scope="other-work", account_id=ACCOUNT, limit=2) as other_scope:
                    assert other_scope

    run(scenario())
