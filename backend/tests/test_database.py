"""DB 연결 의존성 검증."""

import pytest

from app.api.deps import get_db_connection
from app.core.config import Settings
from app.core.database import psycopg_dsn
from app.core.errors import AppError
from tests.support import run


def test_connection_is_refused_when_the_database_is_not_configured() -> None:
    settings = Settings(_env_file=None, database_url=None)

    async def scenario() -> AppError:
        with pytest.raises(AppError) as excinfo:
            await anext(get_db_connection(settings))
        return excinfo.value

    error = run(scenario())

    # 설정이 없으면 메모리 저장소 같은 대체 경로로 넘어가지 않고 명시적으로 거절한다.
    assert (error.status_code, error.error_code) == (503, "DATABASE_NOT_CONFIGURED")


def test_alembic_url_is_converted_for_psycopg() -> None:
    assert (
        psycopg_dsn("postgresql+psycopg://user:pw@localhost:5432/saerok")
        == "postgresql://user:pw@localhost:5432/saerok"
    )
