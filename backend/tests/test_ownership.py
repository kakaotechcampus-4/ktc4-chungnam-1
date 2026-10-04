"""자원 소유 확인 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from uuid import UUID, uuid4

import pytest

from app.core.database import connect
from app.core.errors import AppError
from app.services import ownership
from tests.support import run


async def _seed(connection, google_sub: str) -> dict[str, UUID]:
    """계정 하나와 그 아래 자원을 하나씩 만든다."""

    async def insert(query, params):
        cursor = await connection.execute(query, params)
        return next(iter((await cursor.fetchone()).values()))

    ids: dict[str, UUID] = {}
    ids["user"] = await insert(
        "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id", (google_sub,)
    )
    ids["profile"] = await insert(
        "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage) "
        "VALUES (%s, '합성 이름', 'male', '1940-01-01', 'unknown') "
        "RETURNING profile_id",
        (ids["user"],),
    )
    ids["fact"] = await insert(
        "INSERT INTO life_facts (profile_id, title, content) "
        "VALUES (%s, '합성 제목', '합성 내용') RETURNING fact_id",
        (ids["profile"],),
    )
    ids["set"] = await insert(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
        "VALUES (%s, 'running', 'synthetic-model', 'card-v1') RETURNING set_id",
        (ids["profile"],),
    )
    ids["session"] = await insert(
        "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
        (ids["profile"],),
    )
    ids["profile_photo"] = await insert(
        "INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, %s) "
        "RETURNING photo_id",
        (ids["profile"], f"synthetic/{uuid4().hex}.jpg"),
    )
    ids["visit_photo"] = await insert(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, %s) RETURNING photo_id",
        (ids["profile"], ids["session"], f"synthetic/{uuid4().hex}.jpg"),
    )
    ids["analysis"] = await insert(
        "INSERT INTO speech_analysis_jobs "
        "(analysis_id, session_id, status, participant_count, s3_object_key, "
        " lease_expires_at, data_expires_at) "
        "VALUES (%s, %s, 'uploading', 2, %s, now() + interval '1 hour', "
        " now() + interval '1 day') RETURNING analysis_id",
        (uuid4(), ids["session"], f"synthetic/{uuid4().hex}.wav"),
    )
    return ids


RESOURCES = [
    (ownership.PROFILE, "profile"),
    (ownership.LIFE_FACT, "fact"),
    (ownership.PROFILE_PHOTO, "profile_photo"),
    (ownership.CARD_SET, "set"),
    (ownership.VISIT_SESSION, "session"),
    (ownership.SPEECH_ANALYSIS, "analysis"),
]


def test_owner_gets_the_profile_of_each_resource(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            mine = await _seed(connection, "synthetic-sub-mine")
            found = [
                await ownership.require_owned(
                    connection, resource, mine[key], account_id=str(mine["user"])
                )
                for resource, key in RESOURCES
            ]
            return mine, found

    mine, found = run(scenario())

    assert found == [mine["profile"]] * len(RESOURCES)


@pytest.mark.parametrize(("resource", "key"), RESOURCES)
def test_other_or_missing_resources_get_the_same_404(
    migrated_database_url, resource, key
):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            mine = await _seed(connection, "synthetic-sub-mine")
            other = await _seed(connection, "synthetic-sub-other")
            errors = []
            for resource_id, account_id in (
                (other[key], str(mine["user"])),  # 다른 계정의 자원
                (uuid4(), str(mine["user"])),  # 없는 자원
                (mine[key], "not-a-uuid"),  # 읽을 수 없는 계정 ID
            ):
                with pytest.raises(AppError) as excinfo:
                    await ownership.require_owned(
                        connection, resource, resource_id, account_id=account_id
                    )
                errors.append(excinfo.value)
            return errors

    errors = run(scenario())

    assert {(e.status_code, e.error_code, e.message) for e in errors} == {
        (404, resource.error_code, resource.message)
    }


def test_visit_photo_is_not_a_profile_photo(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            mine = await _seed(connection, "synthetic-sub-mine")
            with pytest.raises(AppError) as excinfo:
                await ownership.require_owned(
                    connection,
                    ownership.PROFILE_PHOTO,
                    mine["visit_photo"],
                    account_id=str(mine["user"]),
                )
            return excinfo.value

    assert run(scenario()).error_code == "PROFILE_PHOTO_NOT_FOUND"
