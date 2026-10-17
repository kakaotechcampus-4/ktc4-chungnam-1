"""migration을 기준으로 init.sql과 env.py가 어긋나지 않는지 검사한다.

- `init.sql`은 빈 개발 DB를 한 번에 세우는 bootstrap 스크립트이고 스키마의 기준은
  Alembic migration이다. 두 벌을 손으로 맞추므로, 각각 별도의 임시 DB에 적용한 뒤
  카탈로그에서 읽은 구조를 비교한다.
- `alembic/env.py`는 `alembic.ini`의 주소가 기본 예시(placeholder)일 때만 설정의
  `SAEROK_DATABASE_URL`을 쓴다. 테스트가 넘긴 주소를 덮어쓰면 downgrade가 작업용 DB에
  실행되므로 두 분기를 각각 고정한다.

실제 PostgreSQL이 필요하다. 임시 DB fixture와 실행 조건은 `conftest.py`에 있다. 공용 DB나
`.env`의 작업용 DB에는 연결하지 않는다.
"""

from pathlib import Path

import psycopg
import pytest
from alembic import command
from alembic.config import Config

from app.core.config import get_settings
from app.core.database import psycopg_dsn
from tests.conftest import BACKEND_DIR, make_alembic_config

INIT_SQL = BACKEND_DIR / "database" / "init.sql"
ALEMBIC_INI = BACKEND_DIR / "alembic.ini"

# 열 순서는 비교하지 않는다. migration의 `ADD COLUMN`은 열을 끝에 붙이지만 init.sql은
# 읽기 쉬운 자리에 두며, 코드는 열 이름으로만 읽고 쓴다.
CATALOG_QUERIES = {
    "columns": """
        SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
               a.attnotnull, pg_get_expr(d.adbin, d.adrelid), a.attidentity,
               a.attgenerated
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
           AND a.attnum > 0 AND NOT a.attisdropped
           AND c.relname <> 'alembic_version'
    """,
    # 이름 없이 만든 CHECK도 이름까지 비교한다. 이후 migration이 이름으로 지우므로
    # init.sql로 만든 DB에서 이름이 다르면 그 migration이 실패한다.
    "constraints": """
        SELECT c.relname, con.conname, con.contype, pg_get_constraintdef(con.oid)
          FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname <> 'alembic_version'
    """,
    "indexes": """
        SELECT tablename, indexname, indexdef
          FROM pg_indexes
         WHERE schemaname = 'public' AND tablename <> 'alembic_version'
    """,
    "views": """
        SELECT viewname, definition FROM pg_views WHERE schemaname = 'public'
    """,
    # pgcrypto가 public에 만든 함수는 확장 목록에서 비교한다.
    "functions": """
        SELECT p.proname, pg_get_functiondef(p.oid)
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND NOT EXISTS (
               SELECT 1 FROM pg_depend d
                WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
                  AND d.deptype = 'e')
    """,
    "triggers": """
        SELECT c.relname, t.tgname, pg_get_triggerdef(t.oid)
          FROM pg_trigger t
          JOIN pg_class c ON c.oid = t.tgrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND NOT t.tgisinternal
    """,
    "extensions": "SELECT extname FROM pg_extension",
}


def _schema_snapshot(database_url: str) -> dict[str, set[tuple]]:
    with psycopg.connect(psycopg_dsn(database_url)) as conn:
        return {
            name: set(conn.execute(sql).fetchall())
            for name, sql in CATALOG_QUERIES.items()
        }


def _has_alembic_version(database_url: str) -> bool:
    with psycopg.connect(psycopg_dsn(database_url)) as conn:
        return conn.execute(
            "SELECT to_regclass('public.alembic_version') IS NOT NULL"
        ).fetchone()[0]


def test_init_sql_matches_migrations(create_test_database):
    from_migrations = create_test_database()
    from_init_sql = create_test_database()

    command.upgrade(make_alembic_config(from_migrations), "head")
    with psycopg.connect(psycopg_dsn(from_init_sql)) as conn:
        conn.execute(INIT_SQL.read_text(encoding="utf-8"))

    expected = _schema_snapshot(from_migrations)
    actual = _schema_snapshot(from_init_sql)

    differences = {
        name: {
            "migration에만": sorted(expected[name] - actual[name], key=repr),
            "init.sql에만": sorted(actual[name] - expected[name], key=repr),
        }
        for name in CATALOG_QUERIES
        if expected[name] != actual[name]
    }
    # 실패하면 migration을 기준으로 init.sql을 고친다.
    assert differences == {}
    # 비교할 대상이 실제로 읽혔는지 확인한다. 쿼리가 비면 위 비교는 항상 통과한다.
    assert all(expected[name] for name in CATALOG_QUERIES)


@pytest.fixture
def fresh_settings(monkeypatch):
    """env.py가 읽는 설정을 이 테스트의 환경 변수로 다시 만든다."""
    get_settings.cache_clear()
    yield monkeypatch
    monkeypatch.undo()
    get_settings.cache_clear()


def test_env_keeps_database_url_given_by_caller(create_test_database, fresh_settings):
    given = create_test_database()
    configured = create_test_database()
    fresh_settings.setenv("SAEROK_DATABASE_URL", configured)

    command.upgrade(make_alembic_config(given), "head")

    # 실패 메시지에 임시 DB 주소가 찍히지 않게 결과만 비교한다.
    given_migrated = _has_alembic_version(given)
    configured_migrated = _has_alembic_version(configured)
    assert given_migrated is True
    assert configured_migrated is False


def test_env_uses_configured_url_only_for_placeholder(
    create_test_database, fresh_settings
):
    configured = create_test_database()
    fresh_settings.setenv("SAEROK_DATABASE_URL", configured)
    # 주소를 넘기지 않으면 alembic.ini의 기본 예시 주소가 남는다.
    config = Config(str(ALEMBIC_INI))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))

    command.upgrade(config, "head")

    configured_migrated = _has_alembic_version(configured)
    assert configured_migrated is True


def test_alembic_ini_keeps_placeholder_url():
    # 실제 주소를 alembic.ini에 적으면 위 분기와 상관없이 그 DB에 실행된다.
    text = Path(ALEMBIC_INI).read_text(encoding="utf-8")
    assert "sqlalchemy.url = driver://user:pass@localhost/dbname" in text
