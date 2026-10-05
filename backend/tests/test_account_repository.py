"""PostgreSQL 계정 저장소 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.core.database import connect
from app.services.accounts import Account, ConsentRecord, PostgresAccountRepository
from tests.support import run

SIGNED_UP_AT = datetime(2026, 8, 21, 2, 40, tzinfo=UTC)


def _account(
    *, social_id: str = "synthetic-sub-0001", email: str | None = None
) -> Account:
    return Account(
        account_id=str(uuid4()),
        provider="google",
        social_id=social_id,
        display_name="합성 보호자",
        email=email,
        consent_version="2026-09-06",
        consents={
            "serviceData": ConsentRecord(granted=True, granted_at=SIGNED_UP_AT),
            "sensitiveData": ConsentRecord(granted=True, granted_at=SIGNED_UP_AT),
            "serviceImprovement": ConsentRecord(granted=False, granted_at=None),
            "pushNotification": ConsentRecord(granted=True, granted_at=SIGNED_UP_AT),
        },
        created_at=SIGNED_UP_AT,
    )


def _repository(connection) -> PostgresAccountRepository:
    return PostgresAccountRepository(connection, default_display_name="보호자")


def test_created_account_is_read_back_without_email(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            created = await repository.create(_account(email="tester@example.com"))
            found = await repository.find_by_social_identity(
                provider="google", social_id="synthetic-sub-0001"
            )
            by_id = await repository.get(created.account_id)
            return created, found, by_id

    created, found, by_id = run(scenario())

    assert created == found == by_id
    # 스키마에 이메일 컬럼이 없으므로 저장하지 않는다.
    assert created.email is None
    assert created.display_name == "합성 보호자"
    assert created.consent_version == "2026-09-06"
    assert created.consents["serviceData"] == ConsentRecord(True, SIGNED_UP_AT)
    assert created.consents["serviceImprovement"] == ConsentRecord(False, None)
    assert created.created_at == SIGNED_UP_AT


def test_same_google_account_is_not_created_twice(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            first = await repository.create(_account())
            second = await repository.create(_account())
            cursor = await connection.execute("SELECT count(*) AS n FROM users")
            users = (await cursor.fetchone())["n"]
            cursor = await connection.execute(
                "SELECT count(*) AS n FROM consent_records"
            )
            records = (await cursor.fetchone())["n"]
            return first, second, users, records

    first, second, users, records = run(scenario())

    assert second.account_id == first.account_id
    assert (users, records) == (1, 1)


def test_current_consent_follows_the_latest_history(migrated_database_url):
    changed_at = SIGNED_UP_AT + timedelta(days=1)
    regranted_at = SIGNED_UP_AT + timedelta(days=2)

    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            account = await repository.create(_account())
            # 선택 동의를 두 번 바꾼 이력. 알림은 끈 뒤 다시 켜고, 서비스 개선은 켠다.
            for push, improvement, recorded_at in (
                (False, True, changed_at),
                (True, True, regranted_at),
            ):
                await connection.execute(
                    "INSERT INTO consent_records "
                    "(user_id, terms_version, service_data, sensitive_data, "
                    " service_improvement, push_notification, recorded_at) "
                    "VALUES (%s, '2026-09-06', true, true, %s, %s, %s)",
                    (account.account_id, improvement, push, recorded_at),
                )
            return await repository.get(account.account_id)

    account = run(scenario())

    consents = account.consents
    assert consents["serviceData"] == ConsentRecord(True, SIGNED_UP_AT)
    assert consents["serviceImprovement"] == ConsentRecord(True, changed_at)
    # 거부에서 동의로 바뀐 가장 최근 시각이다.
    assert consents["pushNotification"] == ConsentRecord(True, regranted_at)


def test_empty_display_name_uses_the_default(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            account = await repository.create(_account())
            await connection.execute(
                "UPDATE users SET display_name = NULL WHERE user_id = %s",
                (account.account_id,),
            )
            return await repository.get(account.account_id)

    assert run(scenario()).display_name == "보호자"


def test_unknown_or_malformed_ids_find_nothing(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            return (
                await repository.get(str(uuid4())),
                await repository.get("not-a-uuid"),
                await repository.find_by_social_identity(
                    provider="google", social_id="missing"
                ),
                await repository.delete("not-a-uuid"),
            )

    assert run(scenario()) == (None, None, None, False)


def test_deleting_an_account_removes_its_records_and_queues_photos(
    migrated_database_url,
):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            repository = _repository(connection)
            account = await repository.create(_account())
            cursor = await connection.execute(
                "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage) "
                "VALUES (%s, '합성 이름', 'female', '1943-03-12', 'unknown') "
                "RETURNING profile_id",
                (account.account_id,),
            )
            profile_id = (await cursor.fetchone())["profile_id"]
            await connection.execute(
                "INSERT INTO photos (profile_id, s3_object_key) "
                "VALUES (%s, 'synthetic/photos/0001.jpg')",
                (profile_id,),
            )

            deleted = await repository.delete(account.account_id)
            deleted_again = await repository.delete(account.account_id)
            remaining = {}
            for table in ("users", "consent_records", "profiles", "photos"):
                cursor = await connection.execute(
                    f"SELECT count(*) AS n FROM {table}"
                )
                remaining[table] = (await cursor.fetchone())["n"]
            cursor = await connection.execute(
                "SELECT s3_object_key FROM storage_deletion_request_queue"
            )
            queued = [row["s3_object_key"] for row in await cursor.fetchall()]
            return deleted, deleted_again, remaining, queued

    deleted, deleted_again, remaining, queued = run(scenario())

    assert (deleted, deleted_again) == (True, False)
    assert set(remaining.values()) == {0}
    assert queued == ["synthetic/photos/0001.jpg"]
