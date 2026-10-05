"""계정과 동의 이력.

ADR-007 에 따라 구글 인증에 성공한 것만으로는 계정을 만들지 않는다. 필수 동의가 모두
완료될 때 계정과 동의 이력을 함께 만든다. 사용자 식별자는 `(provider, social_id)` 이고
내부 기본키는 별도의 `account_id` 다.
"""

import asyncio
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Literal, Protocol
from uuid import UUID, uuid4

from app.core.database import DbConnection
from app.core.errors import AppError

# 거부하면 계정을 만들지 않는 동의 항목 (data-contracts.md `Account`).
REQUIRED_CONSENTS: tuple[str, ...] = (
    "serviceData",
    "sensitiveData",
)
# 거부해도 계정을 만드는 선택 동의 항목.
OPTIONAL_CONSENTS: tuple[str, ...] = ("serviceImprovement", "pushNotification")


@dataclass(frozen=True)
class ConsentRecord:
    granted: bool
    granted_at: datetime | None


@dataclass(frozen=True)
class Account:
    account_id: str
    provider: Literal["google"]
    # 구글 `sub`. 계정을 찾는 데만 쓰고 API 응답과 로그에는 넣지 않는다.
    social_id: str
    display_name: str
    email: str | None
    consent_version: str
    consents: Mapping[str, ConsentRecord]
    created_at: datetime


class AccountRepository(Protocol):
    async def find_by_social_identity(
        self, *, provider: str, social_id: str
    ) -> Account | None: ...

    async def get(self, account_id: str) -> Account | None: ...

    async def create(self, account: Account) -> Account:
        """계정을 저장한다.

        같은 `(provider, social_id)` 가 이미 있으면 새로 만들지 않고 기존 계정을
        돌려준다.
        """
        ...

    async def delete(self, account_id: str) -> bool:
        """계정과 동의 이력을 함께 지운다. 지울 계정이 없었으면 `False` 다."""
        ...


class InMemoryAccountRepository:
    """테스트 전용 저장소.

    프로세스 메모리에만 남으므로 서버를 다시 시작하면 계정이 사라진다. 서버는
    `PostgresAccountRepository` 를 쓴다.
    """

    def __init__(self) -> None:
        self._by_id: dict[str, Account] = {}
        self._by_social: dict[tuple[str, str], str] = {}
        self._lock = asyncio.Lock()

    async def find_by_social_identity(
        self, *, provider: str, social_id: str
    ) -> Account | None:
        account_id = self._by_social.get((provider, social_id))
        return self._by_id.get(account_id) if account_id else None

    async def get(self, account_id: str) -> Account | None:
        return self._by_id.get(account_id)

    async def create(self, account: Account) -> Account:
        async with self._lock:
            key = (account.provider, account.social_id)
            existing_id = self._by_social.get(key)
            if existing_id is not None:
                return self._by_id[existing_id]
            self._by_id[account.account_id] = account
            self._by_social[key] = account.account_id
            return account

    async def delete(self, account_id: str) -> bool:
        async with self._lock:
            # 동의 이력은 `Account` 안에 있으므로 계정과 함께 사라진다.
            account = self._by_id.pop(account_id, None)
            if account is None:
                return False
            self._by_social.pop((account.provider, account.social_id), None)
            return True


# Account.consents 의 이름과 consent_records 의 컬럼.
_CONSENT_COLUMNS: dict[str, str] = {
    "serviceData": "service_data",
    "sensitiveData": "sensitive_data",
    "serviceImprovement": "service_improvement",
    "pushNotification": "push_notification",
}


class PostgresAccountRepository:
    """`users` 와 `consent_records` 에 계정과 동의 이력을 저장한다.

    동의는 바뀔 때마다 이력 행을 더하고 현재 동의는 가장 최근 이력이다. 스키마에
    이메일 컬럼이 없으므로 이메일은 저장하지 않으며 `Account.email` 은 항상 `None`
    이다. 계정을 지우면 DB 의 CASCADE 로 동의 이력, 프로필과 그 아래 기록이 함께
    지워지고, 사진과 음성 원본의 객체 키는 trigger 가 S3 삭제 대기열에 넣는다.
    """

    def __init__(
        self, connection: DbConnection, *, default_display_name: str
    ) -> None:
        self._connection = connection
        # 표시 이름을 비워 둔 계정(`display_name IS NULL`)에 쓴다.
        self._default_display_name = default_display_name

    async def find_by_social_identity(
        self, *, provider: str, social_id: str
    ) -> Account | None:
        if provider != "google":
            return None
        cursor = await self._connection.execute(
            "SELECT user_id, google_sub, display_name, created_at "
            "FROM users WHERE google_sub = %s",
            (social_id,),
        )
        return await self._to_account(await cursor.fetchone())

    async def get(self, account_id: str) -> Account | None:
        user_id = _parse_uuid(account_id)
        if user_id is None:
            return None
        cursor = await self._connection.execute(
            "SELECT user_id, google_sub, display_name, created_at "
            "FROM users WHERE user_id = %s",
            (user_id,),
        )
        return await self._to_account(await cursor.fetchone())

    async def create(self, account: Account) -> Account:
        # 계정과 첫 동의 이력은 함께 만들어야 한다. 같은 구글 계정이 이미 있으면
        # 아무것도 만들지 않고 기존 계정을 돌려준다.
        async with self._connection.transaction():
            cursor = await self._connection.execute(
                "INSERT INTO users (user_id, google_sub, display_name, created_at) "
                "VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (google_sub) DO NOTHING RETURNING user_id",
                (
                    UUID(account.account_id),
                    account.social_id,
                    account.display_name,
                    account.created_at,
                ),
            )
            if await cursor.fetchone() is not None:
                await self._connection.execute(
                    "INSERT INTO consent_records "
                    "(user_id, terms_version, service_data, sensitive_data, "
                    " service_improvement, push_notification, recorded_at) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (
                        UUID(account.account_id),
                        account.consent_version,
                        *(
                            account.consents[name].granted
                            for name in _CONSENT_COLUMNS
                        ),
                        account.created_at,
                    ),
                )
        # 저장한 값으로 다시 읽어, 저장하지 않는 이메일 등이 응답에 섞이지 않게 한다.
        stored = await self.find_by_social_identity(
            provider=account.provider, social_id=account.social_id
        )
        if stored is None:
            raise RuntimeError("만든 계정을 다시 읽지 못했다")
        return stored

    async def delete(self, account_id: str) -> bool:
        user_id = _parse_uuid(account_id)
        if user_id is None:
            return False
        cursor = await self._connection.execute(
            "DELETE FROM users WHERE user_id = %s", (user_id,)
        )
        return cursor.rowcount > 0

    async def _to_account(self, user: dict[str, Any] | None) -> Account | None:
        if user is None:
            return None
        cursor = await self._connection.execute(
            "SELECT terms_version, service_data, sensitive_data, "
            "       service_improvement, push_notification, recorded_at "
            "FROM consent_records WHERE user_id = %s "
            "ORDER BY recorded_at, record_id",
            (user["user_id"],),
        )
        history = await cursor.fetchall()
        if not history:
            # 계정과 첫 동의 이력은 한 트랜잭션에서 만든다. 이력이 없으면 데이터가
            # 깨진 것이므로 동의하지 않은 것으로 꾸며 내지 않는다.
            raise RuntimeError("동의 이력이 없는 계정이다")
        return Account(
            account_id=str(user["user_id"]),
            provider="google",
            social_id=user["google_sub"],
            display_name=user["display_name"] or self._default_display_name,
            email=None,
            consent_version=history[-1]["terms_version"],
            consents=_current_consents(history),
            created_at=user["created_at"],
        )


def _current_consents(
    history: Sequence[Mapping[str, Any]],
) -> dict[str, ConsentRecord]:
    """가장 최근 이력으로 현재 동의를 만든다.

    `granted_at` 은 동의 중인 항목이면 거부에서 동의로 바뀐 가장 최근 이력의 시각이고,
    처음부터 동의했으면 첫 이력(가입)의 시각이다. 거부 중이면 `None` 이다.
    """
    consents: dict[str, ConsentRecord] = {}
    for name, column in _CONSENT_COLUMNS.items():
        granted_since: datetime | None = None
        for record in history:
            if not record[column]:
                granted_since = None
            elif granted_since is None:
                granted_since = record["recorded_at"]
        consents[name] = ConsentRecord(
            granted=granted_since is not None, granted_at=granted_since
        )
    return consents


def _parse_uuid(value: str) -> UUID | None:
    try:
        return UUID(value)
    except ValueError:
        return None


class AccountService:
    def __init__(
        self,
        repository: AccountRepository,
        *,
        consent_version: str,
        store_google_profile: bool,
        default_display_name: str,
    ) -> None:
        self._repository = repository
        self._consent_version = consent_version
        self._store_google_profile = store_google_profile
        self._default_display_name = default_display_name

    async def find(self, *, provider: str, social_id: str) -> Account | None:
        return await self._repository.find_by_social_identity(
            provider=provider, social_id=social_id
        )

    async def get(self, account_id: str) -> Account:
        account = await self._repository.get(account_id)
        if account is None:
            raise AppError(
                status_code=404,
                error_code="ACCOUNT_NOT_FOUND",
                message="계정을 찾을 수 없습니다.",
            )
        return account

    async def delete(self, account_id: str) -> None:
        """회원 탈퇴. 계정과 동의 이력, 프로필과 그 아래의 모든 기록을 지운다.

        DB 저장소에서는 CASCADE 로 함께 지워지고 사진과 음성 원본은 S3 삭제 대기열에
        들어간다(API 1-5). 탈퇴 이유 저장은 아직 구현하지 않았다.
        """
        if not await self._repository.delete(account_id):
            raise AppError(
                status_code=404,
                error_code="ACCOUNT_NOT_FOUND",
                message="계정을 찾을 수 없습니다.",
            )

    async def register(
        self,
        *,
        provider: Literal["google"],
        social_id: str,
        consent_version: str,
        submitted_consents: Mapping[str, bool],
        display_name: str | None,
        google_email: str | None,
        google_name: str | None,
    ) -> Account:
        if consent_version != self._consent_version:
            raise AppError(
                status_code=409,
                error_code="CONSENT_VERSION_MISMATCH",
                message="동의 항목이 변경되었습니다. 다시 확인해 주세요.",
            )

        missing = [
            name
            for name in REQUIRED_CONSENTS
            if not submitted_consents.get(name, False)
        ]
        if missing:
            # 필수 동의를 거부하면 계정을 만들지 않는다. 어떤 항목이 빠졌는지는
            # 계정 정보가 아니므로 응답에 그대로 담아도 된다.
            raise AppError(
                status_code=422,
                error_code="REQUIRED_CONSENT_MISSING",
                message=f"필수 동의 항목에 동의해야 가입할 수 있습니다: {', '.join(missing)}",
            )

        granted_at = datetime.now(UTC)
        consents = {
            name: ConsentRecord(
                granted=submitted_consents.get(name, False),
                granted_at=granted_at if submitted_consents.get(name, False) else None,
            )
            for name in (*REQUIRED_CONSENTS, *OPTIONAL_CONSENTS)
        }

        account = Account(
            account_id=str(uuid4()),
            provider=provider,
            social_id=social_id,
            display_name=self._resolve_display_name(display_name, google_name),
            email=google_email if self._store_google_profile else None,
            consent_version=consent_version,
            consents=consents,
            created_at=granted_at,
        )
        return await self._repository.create(account)

    def _resolve_display_name(
        self, submitted: str | None, google_name: str | None
    ) -> str:
        if submitted and submitted.strip():
            return submitted.strip()
        if self._store_google_profile and google_name and google_name.strip():
            return google_name.strip()
        return self._default_display_name
