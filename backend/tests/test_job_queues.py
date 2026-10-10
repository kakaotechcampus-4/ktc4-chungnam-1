"""카드 생성과 사진 분석 대기열 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

from uuid import uuid4

import psycopg
import pytest

from app.core.database import connect
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.photo_analysis_jobs import PhotoAnalysisQueue
from tests.support import run


async def _value(connection, query, params=()):
    cursor = await connection.execute(query, params)
    return next(iter((await cursor.fetchone()).values()))


async def _profile(connection):
    user_id = await _value(
        connection,
        "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id",
        (f"synthetic-sub-{uuid4().hex[:8]}",),
    )
    return await _value(
        connection,
        "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage) "
        "VALUES (%s, '합성 이름', 'male', '1940-01-01', 'unknown') RETURNING profile_id",
        (user_id,),
    )


async def _running_card_set(connection):
    return await _value(
        connection,
        "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
        "VALUES (%s, 'running', 'synthetic-model', 'card-v1') RETURNING set_id",
        (await _profile(connection),),
    )


async def _row(connection, query, params):
    cursor = await connection.execute(query, params)
    return await cursor.fetchone()


def test_card_generation_job_is_leased_once_and_failed_with_its_input(
    migrated_database_url,
):
    queue = CardGenerationQueue()

    async def scenario():
        async with connect(migrated_database_url) as connection:
            set_id = await _running_card_set(connection)
            job = await queue.claim(connection, lease_seconds=600)
            again = await queue.claim(connection, lease_seconds=600)
            leased = await _row(
                connection, "SELECT * FROM card_sets WHERE set_id = %s", (set_id,)
            )
            await queue.fail(
                connection,
                job,
                error_code="INVALID_AI_RESPONSE",
                generation_input={"ageRange": "80s"},
            )
            failed = await _row(
                connection, "SELECT * FROM card_sets WHERE set_id = %s", (set_id,)
            )
            return set_id, job, again, leased, failed

    set_id, job, again, leased, failed = run(scenario())

    assert (job.set_id, job.attempt_count) == (set_id, 1)
    assert again is None, "임대 중인 작업은 다른 worker가 가져가지 않는다"
    assert leased["lease_expires_at"] is not None
    assert (failed["status"], failed["error_code"]) == ("failed", "INVALID_AI_RESPONSE")
    assert failed["generation_log"] == {"input": {"ageRange": "80s"}}
    assert failed["lease_expires_at"] is None


def test_card_generation_job_whose_lease_expired_fails(migrated_database_url):
    queue = CardGenerationQueue()

    async def scenario():
        async with connect(migrated_database_url) as connection:
            set_id = await _running_card_set(connection)
            await queue.claim(connection, lease_seconds=600)
            await connection.execute(
                "UPDATE card_sets SET lease_expires_at = now() - interval '1 second'"
            )
            expired = await queue.expire_leases(connection)
            row = await _row(
                connection, "SELECT * FROM card_sets WHERE set_id = %s", (set_id,)
            )
            return expired, row

    expired, row = run(scenario())

    assert expired == 1
    assert (row["status"], row["error_code"]) == ("failed", "WORKER_LEASE_EXPIRED")
    assert row["generation_log"] == {"input": None}


def test_completed_card_set_cannot_keep_a_lease(migrated_database_url):
    async def scenario():
        async with connect(migrated_database_url) as connection:
            set_id = await _running_card_set(connection)
            await connection.execute(
                "UPDATE card_sets SET lease_expires_at = now() WHERE set_id = %s",
                (set_id,),
            )
            await connection.execute(
                "UPDATE card_sets SET status = 'completed', "
                "generation_log = '{\"input\": {}}' WHERE set_id = %s",
                (set_id,),
            )

    with pytest.raises(psycopg.errors.CheckViolation):
        run(scenario())


def test_only_profile_photos_are_leased_for_analysis(migrated_database_url):
    queue = PhotoAnalysisQueue()

    async def scenario():
        async with connect(migrated_database_url) as connection:
            profile_id = await _profile(connection)
            session_id = await _value(
                connection,
                "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
                (profile_id,),
            )
            # 면회 사진을 먼저 넣어도 분석 대상이 아니다.
            await connection.execute(
                "INSERT INTO photos (profile_id, session_id, s3_object_key) "
                "VALUES (%s, %s, 'synthetic/visit.jpg')",
                (profile_id, session_id),
            )
            photo_id = await _value(
                connection,
                "INSERT INTO photos (profile_id, s3_object_key) "
                "VALUES (%s, 'synthetic/profile.jpg') RETURNING photo_id",
                (profile_id,),
            )
            job = await queue.claim(connection, lease_seconds=600)
            again = await queue.claim(connection, lease_seconds=600)
            leased = await _row(
                connection, "SELECT * FROM photos WHERE photo_id = %s", (photo_id,)
            )
            await queue.fail(connection, job, error_code="AI_SERVER_TIMEOUT")
            failed = await _row(
                connection, "SELECT * FROM photos WHERE photo_id = %s", (photo_id,)
            )
            return photo_id, job, again, leased, failed

    photo_id, job, again, leased, failed = run(scenario())

    assert (job.photo_id, job.s3_object_key) == (photo_id, "synthetic/profile.jpg")
    assert again is None, "면회 사진과 임대 중인 사진은 가져가지 않는다"
    assert (leased["analysis_status"], leased["attempt_count"]) == ("processing", 1)
    assert leased["lease_expires_at"] is not None
    assert (failed["analysis_status"], failed["error_code"]) == (
        "failed",
        "AI_SERVER_TIMEOUT",
    )
    assert failed["lease_expires_at"] is None


def test_photo_analysis_whose_lease_expired_fails(migrated_database_url):
    queue = PhotoAnalysisQueue()

    async def scenario():
        async with connect(migrated_database_url) as connection:
            profile_id = await _profile(connection)
            photo_id = await _value(
                connection,
                "INSERT INTO photos (profile_id, s3_object_key) "
                "VALUES (%s, 'synthetic/profile.jpg') RETURNING photo_id",
                (profile_id,),
            )
            await queue.claim(connection, lease_seconds=600)
            await connection.execute(
                "UPDATE photos SET lease_expires_at = now() - interval '1 second'"
            )
            expired = await queue.expire_leases(connection)
            row = await _row(
                connection, "SELECT * FROM photos WHERE photo_id = %s", (photo_id,)
            )
            return expired, row

    expired, row = run(scenario())

    assert expired == 1
    assert (row["analysis_status"], row["error_code"]) == (
        "failed",
        "WORKER_LEASE_EXPIRED",
    )
