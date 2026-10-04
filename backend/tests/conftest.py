"""실제 PostgreSQL이 필요한 테스트의 공통 fixture.

`SAEROK_TEST_DATABASE_URL`(관리자 권한으로 접속해 테스트 전용 DB를 만들고 지울 수
있는 연결 문자열)이 설정된 환경에서만 실행하고, 없으면 그 fixture를 쓰는 테스트를
건너뛴다. 테스트마다 임시 DB를 새로 만들고 끝나면 지우므로 `.env`의 작업용 DB는
건드리지 않는다.
"""

import os
import uuid
from pathlib import Path

import psycopg
import pytest
from alembic import command
from alembic.config import Config

from app.core.database import psycopg_dsn

BACKEND_DIR = Path(__file__).resolve().parent.parent
ADMIN_DATABASE_URL = os.environ.get("SAEROK_TEST_DATABASE_URL")


@pytest.fixture
def test_database_url():
    """빈 임시 DB의 SQLAlchemy 형식 연결 문자열."""
    if not ADMIN_DATABASE_URL:
        pytest.skip(
            "SAEROK_TEST_DATABASE_URL이 설정된 실제 PostgreSQL에서만 실행한다 "
            "(예: postgresql://postgres:postgres@localhost:5432/postgres)"
        )
    admin_dsn = psycopg_dsn(ADMIN_DATABASE_URL)
    db_name = f"saerok_test_{uuid.uuid4().hex[:12]}"

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


@pytest.fixture
def migrated_database_url(alembic_config, test_database_url):
    """최신 migration을 적용한 임시 DB의 연결 문자열."""
    command.upgrade(alembic_config, "head")
    return test_database_url
