"""PostgreSQL 연결.

저장소는 연결을 직접 열지 않고 바깥에서 받은 연결을 쓴다. API는
`app.api.deps.get_db_connection`이 요청마다 연결을 하나 열어 넘긴다. 연결은
autocommit이므로, 여러 문장을 한 번에 반영해야 하면 서비스나 저장소 코드에서
`async with connection.transaction():` 블록으로 묶는다. 바깥 블록 안에서 다시 열면
savepoint가 된다.

psycopg 비동기 연결은 Windows 기본 이벤트 루프(ProactorEventLoop)에서 동작하지
않는다. Windows에서는 SelectorEventLoop로 실행한다. `scripts/run_backend.sh`는
`--reload`로 실행해 SelectorEventLoop를 쓴다.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from psycopg import AsyncConnection
from psycopg.rows import DictRow, dict_row

DbConnection = AsyncConnection[DictRow]


def psycopg_dsn(database_url: str) -> str:
    # SAEROK_DATABASE_URL은 Alembic(SQLAlchemy) 형식이라 psycopg가 모르는
    # driver 표기를 뗀다.
    return database_url.replace("postgresql+psycopg://", "postgresql://", 1)


@asynccontextmanager
async def connect(database_url: str) -> AsyncIterator[DbConnection]:
    connection = await AsyncConnection.connect(
        psycopg_dsn(database_url), autocommit=True, row_factory=dict_row
    )
    async with connection:
        yield connection
