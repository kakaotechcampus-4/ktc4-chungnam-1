"""라우트가 쓰는 의존성.

검증기처럼 프로세스에 하나만 두는 것은 여기서 한 번 만들고, DB 연결은 요청마다 하나
열어 저장소에 넘긴다. 커밋은 이 의존성의 정리 단계가 아니라 서비스나 저장소 코드의
트랜잭션 블록에서 한다. 정리 단계는 응답을 보낸 뒤에 실행될 수 있어, 커밋이 실패해도
앱은 성공 응답을 받을 수 있기 때문이다. 테스트는 `dependency_overrides` 로 구글 JWKS
조회와 저장소를 바꿔 끼운다.
"""

from collections.abc import AsyncIterator
from functools import lru_cache
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings
from app.core.database import DbConnection, connect
from app.core.errors import AppError
from app.services.accounts import (
    Account,
    AccountRepository,
    AccountService,
    PostgresAccountRepository,
)
from app.services.google_identity import (
    GoogleIdTokenVerifier,
    fetch_google_jwks,
)
from app.services.image_storage import (
    ImageStorage,
    S3ImageStorage,
    UnconfiguredImageStorage,
)
from app.services.session_revocations import (
    InMemorySessionRevocationStore,
    SessionRevocationStore,
)
from app.services.session_tokens import SessionClaims, TokenIssuer

bearer_scheme = HTTPBearer(auto_error=False)

SettingsDep = Annotated[Settings, Depends(get_settings)]


async def get_db_connection(settings: SettingsDep) -> AsyncIterator[DbConnection]:
    if not settings.database_url:
        raise AppError(
            status_code=503,
            error_code="DATABASE_NOT_CONFIGURED",
            message="서버 저장소가 설정되지 않았습니다.",
        )
    async with connect(settings.database_url) as connection:
        yield connection


DbConnectionDep = Annotated[DbConnection, Depends(get_db_connection)]


def get_account_repository(
    settings: SettingsDep, connection: DbConnectionDep
) -> AccountRepository:
    return PostgresAccountRepository(
        connection, default_display_name=settings.default_display_name
    )


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


@lru_cache
def get_image_storage() -> ImageStorage:
    # S3 client를 요청마다 만들지 않도록 프로세스마다 하나만 둔다.
    settings = get_settings()
    if not settings.image_s3_bucket:
        return UnconfiguredImageStorage()
    return S3ImageStorage(
        bucket=settings.image_s3_bucket,
        region=settings.image_s3_region,
        prefix=settings.image_s3_prefix,
        presigned_ttl_seconds=settings.image_presigned_ttl_seconds,
        server_side_encryption=settings.image_s3_encryption,
    )


def get_token_issuer(settings: SettingsDep) -> TokenIssuer:
    return TokenIssuer(
        secret=settings.session_secret,
        issuer=settings.service_name,
        session_ttl_seconds=settings.session_ttl_seconds,
        registration_ttl_seconds=settings.registration_ttl_seconds,
    )


@lru_cache
def get_session_revocations() -> SessionRevocationStore:
    return InMemorySessionRevocationStore()


def _unauthenticated() -> AppError:
    return AppError(
        status_code=401,
        error_code="UNAUTHENTICATED",
        message="로그인이 필요합니다.",
    )


async def get_current_session(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ],
    issuer: Annotated[TokenIssuer, Depends(get_token_issuer)],
    revocations: Annotated[
        SessionRevocationStore, Depends(get_session_revocations)
    ],
) -> SessionClaims:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthenticated()
    session = issuer.read_session(credentials.credentials)
    # 로그아웃하거나 탈퇴한 세션이다. 만료 전이라도 받지 않는다.
    if await revocations.is_revoked(session.token_id):
        raise _unauthenticated()
    return session


async def get_current_account(
    session: Annotated[SessionClaims, Depends(get_current_session)],
    accounts: Annotated[AccountService, Depends(get_account_service)],
) -> Account:
    return await accounts.get(session.account_id)


AccountServiceDep = Annotated[AccountService, Depends(get_account_service)]
GoogleVerifierDep = Annotated[GoogleIdTokenVerifier, Depends(get_google_verifier)]
ImageStorageDep = Annotated[ImageStorage, Depends(get_image_storage)]
TokenIssuerDep = Annotated[TokenIssuer, Depends(get_token_issuer)]
SessionRevocationsDep = Annotated[
    SessionRevocationStore, Depends(get_session_revocations)
]
CurrentSessionDep = Annotated[SessionClaims, Depends(get_current_session)]
CurrentAccountDep = Annotated[Account, Depends(get_current_account)]
