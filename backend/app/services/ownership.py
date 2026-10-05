"""자원의 소유 계정 확인.

API 명세의 공통 규칙에 따라 다른 계정의 자원은 존재 여부를 드러내지 않고 404로
거절한다. 없는 자원과 다른 계정의 자원은 같은 오류 코드와 메시지를 받는다. 모든
자원은 프로필을 거쳐 계정에 이어지므로, 확인에 성공하면 그 자원의 `profile_id` 를
돌려준다.

라우트는 경로의 ID를 `UUID` 로 받는다. 형식이 틀린 ID는 FastAPI가 먼저
`INVALID_REQUEST`(422)로 거절한다.
"""

from dataclasses import dataclass
from typing import LiteralString
from uuid import UUID

from app.core.database import DbConnection
from app.core.errors import AppError


@dataclass(frozen=True)
class OwnedResource:
    error_code: str
    message: str
    # 자원 ID와 계정 ID를 차례로 받아, 그 계정의 자원이면 `profile_id` 한 행을 돌려준다.
    query: LiteralString


PROFILE = OwnedResource(
    error_code="PROFILE_NOT_FOUND",
    message="프로필을 찾을 수 없습니다.",
    query="SELECT profile_id FROM profiles WHERE profile_id = %s AND user_id = %s",
)

LIFE_FACT = OwnedResource(
    error_code="LIFE_FACT_NOT_FOUND",
    message="생애 정보를 찾을 수 없습니다.",
    query=(
        "SELECT f.profile_id FROM life_facts f "
        "JOIN profiles p ON p.profile_id = f.profile_id "
        "WHERE f.fact_id = %s AND p.user_id = %s"
    ),
)

# 면회 사진도 같은 테이블에 있으므로 회차에 묶이지 않은 사진만 프로필 사진이다.
PROFILE_PHOTO = OwnedResource(
    error_code="PROFILE_PHOTO_NOT_FOUND",
    message="프로필 사진을 찾을 수 없습니다.",
    query=(
        "SELECT ph.profile_id FROM photos ph "
        "JOIN profiles p ON p.profile_id = ph.profile_id "
        "WHERE ph.photo_id = %s AND ph.session_id IS NULL AND p.user_id = %s"
    ),
)

CARD_SET = OwnedResource(
    error_code="CARD_GENERATION_NOT_FOUND",
    message="카드 생성 작업을 찾을 수 없습니다.",
    query=(
        "SELECT cs.profile_id FROM card_sets cs "
        "JOIN profiles p ON p.profile_id = cs.profile_id "
        "WHERE cs.set_id = %s AND p.user_id = %s"
    ),
)

VISIT_SESSION = OwnedResource(
    error_code="VISIT_SESSION_NOT_FOUND",
    message="면회 기록을 찾을 수 없습니다.",
    query=(
        "SELECT v.profile_id FROM visit_sessions v "
        "JOIN profiles p ON p.profile_id = v.profile_id "
        "WHERE v.session_id = %s AND p.user_id = %s"
    ),
)

SPEECH_ANALYSIS = OwnedResource(
    error_code="SPEECH_ANALYSIS_NOT_FOUND",
    message="음성 분석 작업을 찾을 수 없습니다.",
    query=(
        "SELECT v.profile_id FROM speech_analysis_jobs j "
        "JOIN visit_sessions v ON v.session_id = j.session_id "
        "JOIN profiles p ON p.profile_id = v.profile_id "
        "WHERE j.analysis_id = %s AND p.user_id = %s"
    ),
)


async def require_owned(
    connection: DbConnection,
    resource: OwnedResource,
    resource_id: UUID,
    *,
    account_id: str,
) -> UUID:
    """`account_id` 계정의 자원이면 그 `profile_id` 를, 아니면 404를 낸다."""
    try:
        owner_id = UUID(account_id)
    except ValueError:
        raise _not_found(resource) from None
    cursor = await connection.execute(resource.query, (resource_id, owner_id))
    row = await cursor.fetchone()
    if row is None:
        raise _not_found(resource)
    return row["profile_id"]


def _not_found(resource: OwnedResource) -> AppError:
    return AppError(
        status_code=404,
        error_code=resource.error_code,
        message=resource.message,
    )
