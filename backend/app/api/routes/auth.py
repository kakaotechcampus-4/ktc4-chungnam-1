"""구글 소셜 로그인 (ADR-007).

흐름은 두 단계다.

1. `POST /auth/google` — 앱이 받은 구글 ID 토큰을 검증한다. 이미 계정이 있으면 바로
   세션을 발급하고, 없으면 계정을 만들지 않은 채 동의가 필요하다고 알린다.
2. `POST /auth/consent` — 필수 동의가 모두 완료되면 계정과 동의 이력을 함께 만들고
   세션을 발급한다. 필수 동의를 거부하면 계정을 만들지 않는다.

앱을 다시 실행할 때는 저장한 세션으로 `GET /auth/me` 를 호출해 두 단계를 건너뛴다.
"""

import logging

from fastapi import APIRouter

from app.api.deps import (
    AccountServiceDep,
    CurrentAccountDep,
    GoogleVerifierDep,
    SettingsDep,
    TokenIssuerDep,
)
from app.schemas.auth import (
    AccountConsentResponse,
    AccountResponse,
    AuthenticatedResponse,
    ConsentItemResponse,
    ConsentRequest,
    ConsentRequiredResponse,
    GoogleLoginRequest,
    LoginResponse,
)
from app.services.accounts import (
    OPTIONAL_CONSENTS,
    REQUIRED_CONSENTS,
    Account,
)
from app.schemas.common import ErrorResponse
from app.services.session_tokens import TokenIssuer

logger = logging.getLogger("saerok.auth")

router = APIRouter(prefix="/auth", tags=["auth"])


def _errors(*statuses: int) -> dict[int | str, dict[str, object]]:
    """오류 응답도 공통 `ErrorResponse` 형태임을 OpenAPI 에 적는다.

    FastAPI 기본값은 422 를 자체 형식으로 적어두므로 여기서 덮어쓴다. 앱은 이 문서만
    보고 오류 처리를 만들 수 있어야 한다.
    """
    descriptions = {
        401: "인증 실패",
        404: "계정 없음",
        409: "동의 버전 불일치",
        422: "요청 형식 오류 또는 필수 동의 누락",
        503: "로그인 설정 미완료 또는 구글 인증 서버 확인 실패",
    }
    return {
        status: {"model": ErrorResponse, "description": descriptions[status]}
        for status in statuses
    }


def _to_account_response(account: Account) -> AccountResponse:
    consents = {
        name: ConsentItemResponse(
            granted=record.granted, granted_at=record.granted_at
        )
        for name, record in account.consents.items()
    }
    empty = ConsentItemResponse(granted=False, granted_at=None)
    return AccountResponse(
        account_id=account.account_id,
        auth_provider="google",
        display_name=account.display_name,
        email=account.email,
        consent=AccountConsentResponse(
            consent_version=account.consent_version,
            service_data=consents.get("serviceData", empty),
            sensitive_data=consents.get("sensitiveData", empty),
            service_improvement=consents.get("serviceImprovement", empty),
            push_notification=consents.get("pushNotification", empty),
        ),
        created_at=account.created_at,
    )


def _authenticated(account: Account, issuer: TokenIssuer) -> AuthenticatedResponse:
    session = issuer.issue_session(account.account_id)
    return AuthenticatedResponse(
        access_token=session.value,
        expires_in=session.expires_in,
        account=_to_account_response(account),
    )


@router.post(
    "/google",
    response_model=LoginResponse,
    responses=_errors(401, 422, 503),
)
async def google_login(
    payload: GoogleLoginRequest,
    verifier: GoogleVerifierDep,
    accounts: AccountServiceDep,
    issuer: TokenIssuerDep,
    settings: SettingsDep,
) -> AuthenticatedResponse | ConsentRequiredResponse:
    identity = await verifier.verify(payload.id_token)

    account = await accounts.find(provider="google", social_id=identity.subject)
    if account is not None:
        logger.info("google_login_completed", extra={"new_account": False})
        return _authenticated(account, issuer)

    # 계정을 아직 만들지 않는다. 필수 동의가 끝나야 만든다(ADR-007).
    registration = issuer.issue_registration(
        provider="google",
        social_id=identity.subject,
        email=identity.email if settings.store_google_profile else None,
        name=identity.name if settings.store_google_profile else None,
    )
    logger.info("google_login_consent_required")
    return ConsentRequiredResponse(
        registration_token=registration.value,
        expires_in=registration.expires_in,
        consent_version=settings.consent_version,
        required_consents=list(REQUIRED_CONSENTS),
        optional_consents=list(OPTIONAL_CONSENTS),
    )


@router.post(
    "/consent",
    response_model=AuthenticatedResponse,
    responses=_errors(401, 409, 422, 503),
)
async def submit_consent(
    payload: ConsentRequest,
    accounts: AccountServiceDep,
    issuer: TokenIssuerDep,
) -> AuthenticatedResponse:
    claims = issuer.read_registration(payload.registration_token)

    existing = await accounts.find(
        provider=claims.provider, social_id=claims.social_id
    )
    if existing is not None:
        # 같은 등록 토큰으로 다시 제출한 경우다. 계정을 덧만들지 않고 세션만 준다.
        return _authenticated(existing, issuer)

    account = await accounts.register(
        provider=claims.provider,
        social_id=claims.social_id,
        consent_version=payload.consent_version,
        submitted_consents=payload.consents.model_dump(by_alias=True),
        display_name=payload.display_name,
        google_email=claims.email,
        google_name=claims.name,
    )
    logger.info("account_created", extra={"auth_provider": "google"})
    return _authenticated(account, issuer)


@router.get(
    "/me",
    response_model=AccountResponse,
    responses=_errors(401, 404, 503),
)
async def read_current_account(account: CurrentAccountDep) -> AccountResponse:
    return _to_account_response(account)
