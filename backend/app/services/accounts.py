"""계정과 동의 이력.

ADR-007 에 따라 구글 인증에 성공한 것만으로는 계정을 만들지 않는다. 필수 동의가 모두
완료될 때 계정과 동의 이력을 함께 만든다. 사용자 식별자는 `(provider, social_id)` 이고
내부 기본키는 별도의 `account_id` 다.
"""

import asyncio
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal, Protocol
from uuid import uuid4

from app.core.errors import AppError

# 거부하면 계정을 만들지 않는 동의 항목 (data-contracts.md `Account`).
REQUIRED_CONSENTS: tuple[str, ...] = (
    "serviceData",
    "sensitiveData",
    "pushNotification",
)
# 거부해도 계정을 만드는 선택 동의 항목.
OPTIONAL_CONSENTS: tuple[str, ...] = ("serviceImprovement",)


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


class InMemoryAccountRepository:
    """개발 검증 전용 저장소.

    프로세스 메모리에만 남으므로 서버를 다시 시작하면 계정이 사라진다. 실제 저장은
    `backend/database/init.sql` 의 `users` 와 `account_consents` 를 쓰는 구현으로
    바꾼다. 저장 항목이 ADR-007 에서 확정되지 않아 아직 연결하지 않았다.
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
