"""Alembic initial schema migration에 대한 통합 테스트.

프로젝트에 기존 DB/migration 테스트 컨벤션이 없어 새로 만든다. 실제
PostgreSQL이 필요하므로, `SAEROK_TEST_DATABASE_URL`(관리자 권한으로 접속해
테스트 전용 DB를 만들고 지울 수 있는 연결 문자열)이 설정된 환경에서만
실행하고, 없으면 건너뛴다(기존 테스트 스위트를 깨뜨리지 않기 위함).

실제 사용자 데이터는 쓰지 않는다. 아래 값은 모두 synthetic이다.
"""

import os
import uuid
from pathlib import Path

import psycopg
import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
from sqlalchemy.exc import IntegrityError

BACKEND_DIR = Path(__file__).resolve().parent.parent
ADMIN_DATABASE_URL = os.environ.get("SAEROK_TEST_DATABASE_URL")

pytestmark = pytest.mark.skipif(
    not ADMIN_DATABASE_URL,
    reason=(
        "SAEROK_TEST_DATABASE_URL이 설정된 실제 PostgreSQL에서만 실행한다 "
        "(예: postgresql://postgres:postgres@localhost:5432/postgres)"
    ),
)


def _psycopg_dsn(sqlalchemy_url: str) -> str:
    # psycopg.connect()는 'postgresql://' DSN을 받고, SQLAlchemy engine URL의
    # '+psycopg' driver 표기는 이해하지 못한다.
    return sqlalchemy_url.replace("postgresql+psycopg://", "postgresql://")


@pytest.fixture
def test_database_url():
    admin_dsn = _psycopg_dsn(ADMIN_DATABASE_URL)
    db_name = f"saerok_migration_test_{uuid.uuid4().hex[:12]}"

    with psycopg.connect(admin_dsn, autocommit=True) as conn:
        conn.execute(f'CREATE DATABASE "{db_name}"')

    base = admin_dsn.rsplit("/", 1)[0]
    database_url = f"{base}/{db_name}".replace(
        "postgresql://", "postgresql+psycopg://"
    )
    try:
        yield database_url
    finally:
        with psycopg.connect(admin_dsn, autocommit=True) as conn:
            conn.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE datname = %s AND pid <> pg_backend_pid()",
                (db_name,),
            )
            conn.execute(f'DROP DATABASE IF EXISTS "{db_name}"')


@pytest.fixture
def alembic_config(test_database_url):
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    config.set_main_option("sqlalchemy.url", test_database_url)
    return config


DOMAIN_TABLES = {
    "users",
    "account_consents",
    "profiles",
    "life_facts",
    "life_fact_collection_states",
    "profile_photo_tags",
    "visit_sessions",
    "session_consents",
    "speech_analysis_jobs",
    "card_generation_requests",
    "conversation_cards",
    "card_evidence_refs",
    "caregiver_evaluations",
    "card_reviews",
    "visit_reports",
    "report_card_summaries",
    "change_proposals",
    "proposal_changes",
}


def test_upgrade_creates_all_eighteen_tables(alembic_config, test_database_url):
    command.upgrade(alembic_config, "head")

    engine = sa.create_engine(test_database_url)
    try:
        inspector = sa.inspect(engine)
        table_names = set(inspector.get_table_names())
    finally:
        engine.dispose()

    assert DOMAIN_TABLES <= table_names
    assert len(DOMAIN_TABLES) == 18


def test_upgrade_produces_working_constraints_and_uuid_default(
    alembic_config, test_database_url
):
    command.upgrade(alembic_config, "head")

    engine = sa.create_engine(test_database_url)
    try:
        with engine.begin() as conn:
            # UUID 기본값 동작 확인 (synthetic data)
            user_id = conn.execute(
                sa.text(
                    "INSERT INTO users (provider, social_id, nickname) "
                    "VALUES ('google', 'synthetic-sub-001', 'Synthetic Caregiver') "
                    "RETURNING user_id"
                )
            ).scalar_one()
            assert user_id is not None

            # partial index/JSONB가 있는 conversation_cards까지 FK 체인을 타고
            # 정상 삽입되는지 확인 (synthetic data)
            profile_id = conn.execute(
                sa.text(
                    "INSERT INTO profiles (user_id, age_range, condition_stage) "
                    "VALUES (:user_id, '80s', 'unknown') RETURNING profile_id"
                ),
                {"user_id": user_id},
            ).scalar_one()
            request_id = conn.execute(
                sa.text(
                    "INSERT INTO card_generation_requests (profile_id, generation_status) "
                    "VALUES (:profile_id, 'completed') RETURNING request_id"
                ),
                {"profile_id": profile_id},
            ).scalar_one()
            follow_ups = conn.execute(
                sa.text(
                    "INSERT INTO conversation_cards "
                    "(request_id, topic_key, topic_title, topic_description, "
                    " primary_question, display_order) "
                    "VALUES (:request_id, 'synthetic-topic', 'Synthetic Topic', "
                    " 'synthetic description', 'synthetic question?', 1) "
                    "RETURNING follow_up_questions"
                ),
                {"request_id": request_id},
            ).scalar_one()
            assert follow_ups == []

            session_id = conn.execute(
                sa.text(
                    "INSERT INTO visit_sessions "
                    "(profile_id, session_status, recording_authorization_granted, "
                    " recording_authorization_granted_at, started_at, ended_at) "
                    "VALUES (:profile_id, 'ended', true, now(), now(), now()) "
                    "RETURNING session_id"
                ),
                {"profile_id": profile_id},
            ).scalar_one()
            analysis_id = uuid.uuid4()
            conn.execute(
                sa.text(
                    "INSERT INTO speech_analysis_jobs "
                    "(analysis_id, session_id, status, participant_count, "
                    " s3_object_key, data_expires_at) "
                    "VALUES (:analysis_id, :session_id, 'uploading', 2, "
                    " 'temporary/speech/synthetic.wav', now() + interval '1 day')"
                ),
                {"analysis_id": analysis_id, "session_id": session_id},
            )
            queued = conn.execute(
                sa.text(
                    "UPDATE speech_analysis_jobs SET status = 'queued', "
                    "size_bytes = 3200, sha256 = :sha256 "
                    "WHERE analysis_id = :analysis_id RETURNING status"
                ),
                {"analysis_id": analysis_id, "sha256": "a" * 64},
            ).scalar_one()
            assert queued == "queued"

        # 허용되지 않는 값은 CHECK constraint로 거부되어야 한다.
        with pytest.raises(IntegrityError):
            with engine.begin() as conn:
                conn.execute(
                    sa.text(
                        "INSERT INTO users (provider, social_id, nickname) "
                        "VALUES ('facebook', 'synthetic-sub-002', 'Synthetic User 2')"
                    )
                )

        # 존재하지 않는 참조는 FK violation으로 거부되어야 한다.
        with pytest.raises(IntegrityError):
            with engine.begin() as conn:
                conn.execute(
                    sa.text(
                        "INSERT INTO profiles (user_id, age_range, condition_stage) "
                        "VALUES ('00000000-0000-0000-0000-000000000000', '80s', 'unknown')"
                    )
                )
    finally:
        engine.dispose()


def test_downgrade_removes_all_tables_then_upgrade_recreates_them(
    alembic_config, test_database_url
):
    command.upgrade(alembic_config, "head")
    command.downgrade(alembic_config, "base")

    engine = sa.create_engine(test_database_url)
    try:
        inspector = sa.inspect(engine)
        assert set(inspector.get_table_names()) - {"alembic_version"} == set()
    finally:
        engine.dispose()

    command.upgrade(alembic_config, "head")

    engine2 = sa.create_engine(test_database_url)
    try:
        inspector = sa.inspect(engine2)
        table_names = set(inspector.get_table_names())
    finally:
        engine2.dispose()

    assert DOMAIN_TABLES <= table_names
