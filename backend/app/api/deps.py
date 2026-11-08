"""라우트가 쓰는 의존성.

검증기처럼 프로세스에 하나만 두는 것은 여기서 한 번 만들고, DB 연결은 요청마다 하나
열어 저장소에 넘긴다. 커밋은 이 의존성의 정리 단계가 아니라 서비스나 저장소 코드의
트랜잭션 블록에서 한다. 정리 단계는 응답을 보낸 뒤에 실행될 수 있어, 커밋이 실패해도
앱은 성공 응답을 받을 수 있기 때문이다. 테스트는 `dependency_overrides` 로 구글 JWKS
조회와 저장소를 바꿔 끼운다.
"""

import re
from collections.abc import AsyncIterator
from functools import lru_cache
from typing import Annotated

from fastapi import Depends, Header
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
from app.services.audio_storage import AudioStorage, S3AudioStorage
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
    PostgresSessionRevocationStore,
    SessionRevocationStore,
)
from app.services.session_tokens import SessionClaims, TokenIssuer
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import SpeechAnalysisSubmissionService

bearer_scheme = HTTPBearer(auto_error=False)

SettingsDep = Annotated[Settings, Depends(get_settings)]

APP_VERSION_CODE_HEADER = "X-App-Version-Code"
_VERSION_CODE_PATTERN = re.compile(r"[0-9]{1,10}")


def require_supported_app_version(
    settings: SettingsDep,
    version_code: Annotated[
        str | None,
        Header(
            alias=APP_VERSION_CODE_HEADER,
            description=(
                "앱의 안드로이드 versionCode. 최소 지원 버전보다 낮으면 426 "
                "APP_UPDATE_REQUIRED 로 거절한다. 없으면 검사하지 않는다."
            ),
        ),
    ] = None,
) -> None:
    """최소 지원 버전보다 낮은 앱의 요청을 426 으로 거절한다.

    헤더가 없거나 숫자가 아니면 통과시킨다. 헤더를 보내기 전에 낸 앱 빌드와 서버
    점검 도구의 요청을 막지 않기 위해서다. 인증보다 먼저 확인하므로 구버전 앱은
    로그인 전 요청에서도 업데이트가 필요하다는 응답을 받는다.
    """
    minimum = settings.min_android_version_code
    if minimum == 0 or version_code is None:
        return
    if not _VERSION_CODE_PATTERN.fullmatch(version_code):
        return
    if int(version_code) < minimum:
        raise AppError(
            status_code=426,
            error_code="APP_UPDATE_REQUIRED",
            message="새 버전으로 업데이트해야 합니다.",
        )


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
def _speech_audio_storage() -> S3AudioStorage | None:
    # S3 client를 요청마다 만들지 않도록 프로세스마다 하나만 둔다.
    settings = get_settings()
    if not settings.speech_audio_s3_bucket:
        return None
    return S3AudioStorage(
        bucket=settings.speech_audio_s3_bucket,
        region=settings.speech_audio_s3_region,
        presigned_ttl_seconds=settings.speech_audio_presigned_ttl_seconds,
        server_side_encryption=settings.speech_audio_s3_encryption,
    )


def get_speech_audio_storage() -> AudioStorage:
    storage = _speech_audio_storage()
    if storage is None:
        raise AppError(
            status_code=503,
            error_code="SPEECH_ANALYSIS_NOT_CONFIGURED",
            message="음성 분석 저장소가 설정되지 않았습니다.",
        )
    return storage


def get_speech_submission_service(
    settings: SettingsDep,
    audio_storage: Annotated[AudioStorage, Depends(get_speech_audio_storage)],
    # 같은 요청의 현재 계정 확인과 같은 연결을 쓴다(FastAPI가 요청 안에서 재사용).
    connection: DbConnectionDep,
) -> SpeechAnalysisSubmissionService:
    return SpeechAnalysisSubmissionService(
        jobs=PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=settings.speech_analysis_lease_seconds
        ),
        audio_storage=audio_storage,
        max_audio_bytes=settings.max_audio_bytes,
        retention_seconds=settings.speech_audio_retention_seconds,
        object_prefix=settings.speech_audio_s3_prefix,
    )


def get_session_revocations(connection: DbConnectionDep) -> SessionRevocationStore:
    # 폐기 기록은 DB에 둔다. 서버를 다시 띄워도 만료 전 폐기한 세션을 계속 거절한다.
    return PostgresSessionRevocationStore(connection)


def _unauthenticated() -> AppError:
    return AppError(
        status_code=401,
        error_code="UNAUTHENTICATED",
        message="로그인이 필요합니다.",
    )


def read_signed_session(
    credentials: HTTPAuthorizationCredentials | None, issuer: TokenIssuer
) -> SessionClaims:
    """Bearer 형식과 세션 토큰의 서명, 만료만 확인한다.

    폐기 여부는 DB를 봐야 하므로 여기서 확인하지 않는다. `get_current_session` 과
    업로드 경로에서 본문을 읽기 전에 확인하는 미들웨어(body_limits.py)가 같이 쓴다.
    """
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthenticated()
    return issuer.read_session(credentials.credentials)


async def get_current_session(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ],
    issuer: Annotated[TokenIssuer, Depends(get_token_issuer)],
    revocations: Annotated[
        SessionRevocationStore, Depends(get_session_revocations)
    ],
) -> SessionClaims:
    session = read_signed_session(credentials, issuer)
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
SpeechSubmissionDep = Annotated[
    SpeechAnalysisSubmissionService, Depends(get_speech_submission_service)
]
