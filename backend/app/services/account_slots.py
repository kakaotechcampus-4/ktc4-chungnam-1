"""계정별 동시 처리 수 제한(2026-11-09 PM 결정).

요청이 쓰는 DB 연결에 세션 수준 advisory lock 을 잡아, 같은 계정의 같은 작업이 동시에
몇 개 돌고 있는지 센다. 한도가 N 이면 칸(slot) N 개 중 비어 있는 하나를 잡는다.

트랜잭션을 열지 않으므로 그 안에서 실행하는 서비스의 문장은 지금처럼 바로 커밋된다.
계정 행을 잠그지 않아 처리 중에도 동의 변경이나 프로필 추가를 막지 않는다. 끝나면 풀고,
연결이 끊기거나 닫히면 PostgreSQL 이 푼다(API 연결은 요청마다 열고 닫는다).

잠금 키는 `작업 이름:계정 ID:칸 번호`의 64비트 해시다. 삭제 실행기의 advisory lock 은
32비트 키 두 개 형식이라 키 공간이 겹치지 않는다. 계정 ID 는 키를 만들 때만 쓰고 로그에
남기지 않는다.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
import logging

from app.core.database import DbConnection

logger = logging.getLogger("saerok.account_slots")


@asynccontextmanager
async def account_slot(
    connection: DbConnection, *, scope: str, account_id: str, limit: int
) -> AsyncIterator[bool]:
    """빈 칸을 잡았으면 `True`, 한도만큼 이미 처리 중이면 `False` 를 넘긴다.

    `False` 일 때는 아무것도 잡지 않았으므로 부르는 쪽이 거절만 하면 된다.
    """
    held = None
    for slot in range(limit):
        name = f"{scope}:{account_id}:{slot}"
        row = await (await connection.execute(
            "SELECT pg_try_advisory_lock(hashtextextended(%s, 0)) AS acquired", (name,),
        )).fetchone()
        if row["acquired"]:
            held = name
            break
    try:
        yield held is not None
    finally:
        if held is not None:
            try:
                await connection.execute(
                    "SELECT pg_advisory_unlock(hashtextextended(%s, 0))", (held,),
                )
            except Exception:
                # 연결이 이미 끊겼으면 PostgreSQL 이 잠금을 풀었다. 키와 예외 내용은 남기지 않는다.
                logger.warning("account_slot_release_failed")
