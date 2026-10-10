"""DB 테스트는 TOPIC_REC_TEST_DATABASE_URL이 가리키는 빈 개발 DB에 backend/database/init.sql(PR #84 스키마)을
적용하고 합성 데이터를 넣는다. init.sql은 테이블을 모두 지우고 다시 만들므로 테스트 전용 DB만 가리킨다."""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
import pytest

from card_generation.tests.unit.seed import Seeded, seed

INIT_SQL = Path(__file__).resolve().parents[4] / "backend/database/init.sql"
DB_ENV = "TOPIC_REC_TEST_DATABASE_URL"


@pytest.fixture(scope="session")
def db_url() -> str:
    url = os.environ.get(DB_ENV)
    if not url:
        pytest.skip(f"{DB_ENV}가 없어 DB 테스트를 건너뜀")
    return url


@pytest.fixture(scope="session")
def seeded(db_url: str) -> Seeded:
    with psycopg.connect(db_url, autocommit=True) as conn:
        conn.execute(INIT_SQL.read_text())
    with psycopg.connect(db_url) as conn:
        data = seed(conn)
        conn.commit()
    return data


@pytest.fixture
def store(db_url: str, seeded: Seeded):
    from card_generation._steps.research.store import ProfileStore
    from card_generation._versions import LATEST
    from simulation.backends.context import build_context

    with psycopg.connect(db_url) as conn:
        return ProfileStore(build_context(conn, seeded.profile_a), LATEST.decay)
