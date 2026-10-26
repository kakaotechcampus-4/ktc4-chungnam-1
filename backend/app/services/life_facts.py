"""생애 정보(`life_facts`).

세부 정보 네 항목(`profiles`의 컬럼) 밖의 생애 정보다. 두 경로로 만든다. 보호자가
일대기에서 추가하거나(API 2-6), 보호자가 변경 제안의 생애 정보 제안을 승인하면(API 7-4,
작업 C) 그 제안을 출처로 만든다. 두 경로 모두 `create_life_fact`를 쓴다. 보호자는 일대기에서
고치고(2-7) 지운다(2-9).

`title`은 100자 이하이며 `title`과 `content`는 비울 수 없다. 요청 검증이 먼저 막고,
DB CHECK(`length(btrim(x)) > 0`)도 막는다.

일대기의 분류(`story_category`)와 기본 그림 번호(`image_number`, 1~5)도 저장한다. 그림 파일은
앱에 있다. 필드 이름은 임시다(작업 D 문서 미정 D1, D2).
"""

import secrets
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services import card_sets, ownership


@dataclass(frozen=True)
class LifeFact:
    fact_id: UUID
    profile_id: UUID
    title: str
    content: str
    created_at: datetime
    story_category: str
    image_number: int


_COLUMNS = "fact_id, profile_id, title, content, created_at, story_category, image_number"
# 분류마다 있는 기본 그림 수. 앱의 `lifeStoryImageCount`, DB CHECK와 같다.
IMAGE_COUNT = 5
# 2-7이 고칠 수 있는 열. `SET` 절의 열 이름은 이 목록에서만 고른다.
_UPDATABLE = ("title", "content", "story_category", "image_number")
# 카드 생성(`card_sets.build_context`)에 쓰는 열. 분류와 그림 번호는 쓰지 않는다.
_CARD_INPUT = ("title", "content")


async def create_life_fact(
    connection: DbConnection,
    *,
    profile_id: UUID,
    title: str,
    content: str,
    source_proposal_id: UUID | None = None,
    story_category: str = "other",
    image_number: int | None = None,
) -> LifeFact:
    """생애 정보 하나를 만든다.

    트랜잭션을 열지 않으므로 부르는 쪽의 트랜잭션에 함께 묶인다(7-4는 제안 정리와 같은
    트랜잭션에서 부른다). 소유 확인도 하지 않으므로 부르는 쪽이 `profile_id`를 먼저
    확인한다. `source_proposal_id`는 승인한 생애 정보 제안이며 응답에는 담지 않는다.

    7-4는 분류와 그림 번호를 보내지 않으므로 기본값을 쓴다. 분류는 `other`(기타)이고 그림
    번호는 1~5 중 하나를 고른다(작업 D 문서 미정 D2, D5).
    """
    if image_number is None:
        image_number = secrets.randbelow(IMAGE_COUNT) + 1
    cursor = await connection.execute(
        "INSERT INTO life_facts "
        "(profile_id, title, content, source_proposal_id, story_category, image_number) "
        f"VALUES (%s, %s, %s, %s, %s, %s) RETURNING {_COLUMNS}",
        (profile_id, title, content, source_proposal_id, story_category, image_number),
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
    story_category: str,
    image_number: int,
) -> LifeFact:
    """일대기에서 보호자가 생애 정보를 추가한다(API 2-6)."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    return await create_life_fact(
        connection,
        profile_id=profile_id,
        title=title,
        content=content,
        story_category=story_category,
        image_number=image_number,
    )


async def update_life_fact(
    connection: DbConnection,
    fact_id: UUID,
    *,
    account_id: str,
    changes: Mapping[str, Any],
    start_timeout_seconds: int,
) -> LifeFact:
    """보낸 필드만 바꾼다(API 2-7). 바꿀 것이 없으면 그대로 돌려준다.

    `changes`의 키는 열 이름(`title`, `content`, `story_category`, `image_number`)이다.
    `created_at`은 바꾸지 않으므로 고쳐도 일대기 목차 순서가 그대로다. 제목이나 내용이
    바뀌면 아직 면회에 안 쓴 카드 묶음은 면회에 쓸 수 없게 된다(`card_sets.mark_stale`).
    """
    await ownership.require_owned(
        connection, ownership.LIFE_FACT, fact_id, account_id=account_id
    )
    columns = [column for column in _UPDATABLE if column in changes]
    if not columns:
        cursor = await connection.execute(
            f"SELECT {_COLUMNS} FROM life_facts WHERE fact_id = %s", (fact_id,)
        )
        row = await cursor.fetchone()
        if row is None:
            # 소유 확인 뒤 같은 계정의 다른 요청이 이야기나 프로필을 지운 경우다.
            raise _not_found()
        return _to_life_fact(row)
    assignments = ", ".join(f"{column} = %s" for column in columns)
    async with connection.transaction():
        before = await _lock(connection, fact_id)
        if any(
            column in changes and changes[column] != before[column] for column in _CARD_INPUT
        ):
            await card_sets.mark_stale(
                connection, before["profile_id"], start_timeout_seconds=start_timeout_seconds
            )
        cursor = await connection.execute(
            f"UPDATE life_facts SET {assignments} WHERE fact_id = %s RETURNING {_COLUMNS}",
            (*(changes[column] for column in columns), fact_id),
        )
        return _to_life_fact(await cursor.fetchone())


async def delete_life_fact(
    connection: DbConnection,
    fact_id: UUID,
    *,
    account_id: str,
    start_timeout_seconds: int,
) -> None:
    """일대기에서 보호자가 생애 정보를 지운다(API 2-9).

    행만 지운다. 다음 카드 생성(4-1)의 입력에서 빠지고, 이미 만든 카드와 주제는 기록으로
    남는다. 아직 면회에 안 쓴 카드 묶음은 면회에 쓸 수 없게 된다(`card_sets.mark_stale`).
    출처 제안(`life_fact_proposals`)은 지우지 않는다.
    """
    await ownership.require_owned(
        connection, ownership.LIFE_FACT, fact_id, account_id=account_id
    )
    async with connection.transaction():
        before = await _lock(connection, fact_id)
        await card_sets.mark_stale(
            connection, before["profile_id"], start_timeout_seconds=start_timeout_seconds
        )
        await connection.execute("DELETE FROM life_facts WHERE fact_id = %s", (fact_id,))


async def _lock(connection: DbConnection, fact_id: UUID) -> Mapping[str, Any]:
    """이야기가 속한 프로필과 이야기 행을 차례로 잠그고 이야기를 읽는다. 트랜잭션 안에서 부른다.

    2-8(프로필 삭제), 4-1, 5-1처럼 프로필을 먼저 잠근다. 이야기를 먼저 잠그면 2-8과 서로
    기다리다 멈출 수 있다.
    """
    cursor = await connection.execute(
        "SELECT profile_id FROM life_facts WHERE fact_id = %s", (fact_id,)
    )
    row = await cursor.fetchone()
    if row is not None:
        await card_sets.lock_profile(connection, row["profile_id"])
        cursor = await connection.execute(
            "SELECT profile_id, title, content FROM life_facts WHERE fact_id = %s FOR UPDATE",
            (fact_id,),
        )
        row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 같은 계정의 다른 요청이 이야기나 프로필을 지운 경우다.
        raise _not_found()
    return row


def _not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code=ownership.LIFE_FACT.error_code,
        message=ownership.LIFE_FACT.message,
    )


def _to_life_fact(row: Mapping[str, Any] | None) -> LifeFact:
    if row is None:
        raise RuntimeError("저장한 생애 정보를 다시 읽지 못했다")
    return LifeFact(**row)
