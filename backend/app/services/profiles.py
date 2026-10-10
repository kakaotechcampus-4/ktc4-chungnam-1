"""피보호자 프로필(`profiles`).

이름, 성별, 생년월일은 서버에 저장하지만 AI 서버 요청에는 넣지 않는다. 프로필 입력
상태(`setupStatus`)는 저장하지 않고 계산한다. 2-5가 세부 정보 저장과 첫 카드 생성 작업을
한 트랜잭션에서 만들므로, 카드 생성 작업(`card_sets`)이 하나라도 있으면 `completed`, 없으면
`inProgress`다.

세부 정보 네 항목(`occupation`, `hometown`, `hobby`, `family`)은 2-5(작업 B)가 처음 쓰고
2-4가 고친다. 빈 문자열은 받지 않으며 DB CHECK(`length(btrim(x)) > 0`)도 막는다.

프로필을 지우면 `ON DELETE CASCADE`로 그 아래 기록이 모두 지워지고, 사진과 음성의 객체
키는 trigger가 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣는다. 대기열을 처리해
S3 원본을 실제로 지우는 코드는 아직 없다.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Literal
from uuid import UUID

from psycopg import sql

from app.core.database import DbConnection
from app.core.errors import AppError
from app.services import ownership
from app.services.life_facts import LifeFact, list_life_facts

# 계정당 프로필 수. 입력 중(`inProgress`)인 프로필도 센다. DB 제약이 없어 서버가 확인한다.
PROFILE_LIMIT = 3

SetupStatus = Literal["inProgress", "completed"]

# 2-4가 바꿀 수 있는 컬럼. 요청 필드 이름은 라우트가 이 이름으로 옮긴다.
UPDATABLE_COLUMNS: tuple[str, ...] = (
    "name",
    "gender",
    "birth_date",
    "condition_stage",
    "symptom_note",
    "occupation",
    "hometown",
    "hobby",
    "family",
)


@dataclass(frozen=True)
class ProfileSummary:
    profile_id: UUID
    name: str
    gender: str
    setup_status: SetupStatus


@dataclass(frozen=True)
class Profile:
    profile_id: UUID
    setup_status: SetupStatus
    name: str
    gender: str
    birth_date: date
    condition_stage: str
    symptom_note: str | None
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None
    life_facts: list[LifeFact]
    created_at: datetime


_SETUP_COMPLETED = (
    "EXISTS (SELECT 1 FROM card_sets c WHERE c.profile_id = p.profile_id) "
    "AS setup_completed"
)
_PROFILE_COLUMNS = (
    "p.profile_id, p.name, p.gender, p.birth_date, p.condition_stage, "
    "p.symptom_note, p.occupation, p.hometown, p.hobby, p.family, p.created_at"
)


async def list_profiles(
    connection: DbConnection, *, account_id: str
) -> list[ProfileSummary]:
    """계정의 프로필을 만든 순서대로 돌려준다(API 2-1). 입력 중인 프로필도 담는다."""
    cursor = await connection.execute(
        f"SELECT p.profile_id, p.name, p.gender, {_SETUP_COMPLETED} "
        "FROM profiles p WHERE p.user_id = %s "
        "ORDER BY p.created_at, p.profile_id",
        (UUID(account_id),),
    )
    return [
        ProfileSummary(
            profile_id=row["profile_id"],
            name=row["name"],
            gender=row["gender"],
            setup_status=_setup_status(row["setup_completed"]),
        )
        for row in await cursor.fetchall()
    ]


async def create_profile(
    connection: DbConnection,
    *,
    account_id: str,
    name: str,
    gender: str,
    birth_date: date,
    condition_stage: str,
    symptom_note: str | None,
) -> Profile:
    """기본 정보로 프로필을 만든다(API 2-2). 만든 프로필은 `inProgress`다."""
    user_id = UUID(account_id)
    async with connection.transaction():
        # 같은 계정의 동시 요청이 함께 세어 3개를 넘기지 않도록 계정 행을 잠근다.
        cursor = await connection.execute(
            "SELECT 1 FROM users WHERE user_id = %s FOR UPDATE", (user_id,)
        )
        if await cursor.fetchone() is None:
            # 세션 확인 뒤 같은 계정이 탈퇴한 경우다.
            raise AppError(
                status_code=404,
                error_code="ACCOUNT_NOT_FOUND",
                message="계정을 찾을 수 없습니다.",
            )
        cursor = await connection.execute(
            "SELECT count(*) AS n FROM profiles WHERE user_id = %s", (user_id,)
        )
        if (await cursor.fetchone())["n"] >= PROFILE_LIMIT:
            raise AppError(
                status_code=409,
                error_code="PROFILE_LIMIT_EXCEEDED",
                message=f"어르신은 {PROFILE_LIMIT}명까지 등록할 수 있습니다.",
            )
        cursor = await connection.execute(
            "INSERT INTO profiles "
            "(user_id, name, gender, birth_date, condition_stage, symptom_note) "
            "VALUES (%s, %s, %s, %s, %s, %s) RETURNING profile_id",
            (user_id, name, gender, birth_date, condition_stage, symptom_note),
        )
        profile_id = (await cursor.fetchone())["profile_id"]
    return await _read_profile(connection, profile_id)


async def get_profile(
    connection: DbConnection, profile_id: UUID, *, account_id: str
) -> Profile:
    """프로필과 생애 정보를 돌려준다(API 2-3)."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    return await _read_profile(connection, profile_id)


async def update_profile(
    connection: DbConnection,
    profile_id: UUID,
    *,
    account_id: str,
    changes: Mapping[str, Any],
) -> Profile:
    """보낸 필드만 바꾼다(API 2-4). 세부 정보 네 항목은 `None`이면 지운다.

    `changes`의 키는 `UPDATABLE_COLUMNS`의 컬럼 이름이다. 바꿀 것이 없으면 그대로
    돌려준다.
    """
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    unknown = set(changes) - set(UPDATABLE_COLUMNS)
    if unknown:
        raise ValueError(f"바꿀 수 없는 프로필 컬럼: {sorted(unknown)}")
    if changes:
        assignments = sql.SQL(", ").join(
            sql.SQL("{} = %s").format(sql.Identifier(column)) for column in changes
        )
        cursor = await connection.execute(
            sql.SQL("UPDATE profiles SET {} WHERE profile_id = %s").format(
                assignments
            ),
            (*changes.values(), profile_id),
        )
        if cursor.rowcount == 0:
            raise _profile_not_found()
    return await _read_profile(connection, profile_id)


async def delete_profile(
    connection: DbConnection, profile_id: UUID, *, account_id: str
) -> None:
    """프로필 하나와 그 아래의 모든 기록을 지운다(API 2-8). 계정과 다른 프로필은 남는다."""
    await ownership.require_owned(
        connection, ownership.PROFILE, profile_id, account_id=account_id
    )
    cursor = await connection.execute(
        "DELETE FROM profiles WHERE profile_id = %s", (profile_id,)
    )
    if cursor.rowcount == 0:
        raise _profile_not_found()


async def _read_profile(connection: DbConnection, profile_id: UUID) -> Profile:
    cursor = await connection.execute(
        f"SELECT {_PROFILE_COLUMNS}, {_SETUP_COMPLETED} "
        "FROM profiles p WHERE p.profile_id = %s",
        (profile_id,),
    )
    row = await cursor.fetchone()
    if row is None:
        # 소유 확인 뒤 같은 계정의 다른 요청이 프로필을 지운 경우다.
        raise _profile_not_found()
    setup_completed = row.pop("setup_completed")
    return Profile(
        **row,
        setup_status=_setup_status(setup_completed),
        life_facts=await list_life_facts(connection, profile_id=profile_id),
    )


def _setup_status(setup_completed: bool) -> SetupStatus:
    return "completed" if setup_completed else "inProgress"


def _profile_not_found() -> AppError:
    return AppError(
        status_code=404,
        error_code=ownership.PROFILE.error_code,
        message=ownership.PROFILE.message,
    )
