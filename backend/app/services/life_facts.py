"""생애 정보(`life_facts`).

세부 정보 네 항목(`profiles`의 컬럼) 밖의 생애 정보다. 두 경로로 만든다. 보호자가
일대기에서 추가하거나(API 2-6), 보호자가 변경 제안의 생애 정보 제안을 승인하면(API 7-4,
작업 C) 그 제안을 출처로 만든다. 두 경로 모두 `create_life_fact`를 쓴다.

`title`은 100자 이하이며 `title`과 `content`는 비울 수 없다. 요청 검증이 먼저 막고,
DB CHECK(`length(btrim(x)) > 0`)도 막는다.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services import ownership


@dataclass(frozen=True)
class LifeFact:
    fact_id: UUID
    profile_id: UUID
    title: str
    content: str
    created_at: datetime


_COLUMNS = "fact_id, profile_id, title, content, created_at"


async def create_life_fact(
    connection: DbConnection,
    *,
    profile_id: UUID,
    title: str,
    content: str,
    source_proposal_id: UUID | None = None,
) -> LifeFact:
    """생애 정보 하나를 만든다.

    트랜잭션을 열지 않으므로 부르는 쪽의 트랜잭션에 함께 묶인다(7-4는 제안 정리와 같은
    트랜잭션에서 부른다). 소유 확인도 하지 않으므로 부르는 쪽이 `profile_id`를 먼저
    확인한다. `source_proposal_id`는 승인한 생애 정보 제안이며 응답에는 담지 않는다.
    """
    cursor = await connection.execute(
        "INSERT INTO life_facts (profile_id, title, content, source_proposal_id) "
        f"VALUES (%s, %s, %s, %s) RETURNING {_COLUMNS}",
        (profile_id, title, content, source_proposal_id),
    )
    return _to_life_fact(await cursor.fetchone())


async def list_life_facts(
    connection: DbConnection, *, profile_id: UUID
) -> list[LifeFact]:
    cursor = await connection.execute(
        f"SELECT {_COLUMNS} FROM life_facts WHERE profile_id = %s "
        "ORDER BY created_at, fact_id",
        (profile_id,),
    )
    return [_to_life_fact(row) for row in await cursor.fetchall()]


async def add_life_fact(
    connection: DbConnection,
    profile_id: UUID,
    *,
    account_id: str,
    title: str,
    content: str,
) -> LifeFact:
    """일대기에서 보호자가 생애 정보를 추가한다(API 2-6)."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    return await create_life_fact(
        connection, profile_id=profile_id, title=title, content=content
    )


async def update_life_fact(
    connection: DbConnection,
    fact_id: UUID,
    *,
    account_id: str,
    changes: Mapping[str, str],
) -> LifeFact:
    """보낸 필드(`title`, `content`)만 바꾼다(API 2-7). 바꿀 것이 없으면 그대로 돌려준다."""
    await ownership.require_owned(
        connection, ownership.LIFE_FACT, fact_id, account_id=account_id
    )
    title = changes.get("title")
    content = changes.get("content")
    cursor = await connection.execute(
        "UPDATE life_facts "
        "SET title = COALESCE(%s, title), content = COALESCE(%s, content) "
        f"WHERE fact_id = %s RETURNING {_COLUMNS}",
        (title, content, fact_id),
    )
    row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 같은 계정의 다른 요청이 프로필을 지운 경우다.
        raise AppError(
            status_code=404,
            error_code=ownership.LIFE_FACT.error_code,
            message=ownership.LIFE_FACT.message,
        )
    return _to_life_fact(row)


def _to_life_fact(row: Mapping[str, Any] | None) -> LifeFact:
    if row is None:
        raise RuntimeError("저장한 생애 정보를 다시 읽지 못했다")
    return LifeFact(**row)
