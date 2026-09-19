"""라우트가 쓰는 의존성.

저장소와 검증기를 여기서 한 번만 만들고 주입한다. 테스트는 `dependency_overrides` 로
구글 JWKS 조회와 저장소를 바꿔 끼운다.
"""

from functools import lru_cache
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.services.accounts import (
    Account,
    AccountRepository,
    AccountService,
    InMemoryAccountRepository,
)
from app.services.google_identity import (
    GoogleIdTokenVerifier,
    fetch_google_jwks,
)
from app.services.session_tokens import TokenIssuer

bearer_scheme = HTTPBearer(auto_error=False)

SettingsDep = Annotated[Settings, Depends(get_settings)]


@lru_cache
def get_account_repository() -> AccountRepository:
    return InMemoryAccountRepository()


def get_account_service(
    settings: SettingsDep,
    repository: Annotated[AccountRepository, Depends(get_account_repository)],
) -> AccountService:
    return AccountService(
        repository,
        consent_version=settings.consent_version,
        store_google_profile=settings.store_google_profile,
        default_display_name=settings.default_display_name,
    )


@lru_cache
def get_google_verifier() -> GoogleIdTokenVerifier:
    # JWKS 캐시를 유지해야 하므로 검증기는 프로세스마다 하나만 만든다.
    settings = get_settings()

    async def fetcher() -> dict:
        return await fetch_google_jwks(settings.google_jwks_url)

    return GoogleIdTokenVerifier(
        allowed_audiences=settings.google_client_ids,
        jwks_fetcher=fetcher,
        cache_seconds=settings.google_jwks_cache_seconds,
    )


def get_token_issuer(settings: SettingsDep) -> TokenIssuer:
    return TokenIssuer(
        secret=settings.session_secret,
        issuer=settings.service_name,
        session_ttl_seconds=settings.session_ttl_seconds,
        registration_ttl_seconds=settings.registration_ttl_seconds,
    )


async def get_current_account(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ],
    issuer: Annotated[TokenIssuer, Depends(get_token_issuer)],
    accounts: Annotated[AccountService, Depends(get_account_service)],
) -> Account:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppError(
            status_code=401,
            error_code="UNAUTHENTICATED",
            message="로그인이 필요합니다.",
        )
    account_id = issuer.read_session(credentials.credentials)
    return await accounts.get(account_id)


AccountServiceDep = Annotated[AccountService, Depends(get_account_service)]
GoogleVerifierDep = Annotated[GoogleIdTokenVerifier, Depends(get_google_verifier)]
TokenIssuerDep = Annotated[TokenIssuer, Depends(get_token_issuer)]
CurrentAccountDep = Annotated[Account, Depends(get_current_account)]
