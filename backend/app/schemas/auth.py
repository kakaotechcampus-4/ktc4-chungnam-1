from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field

from app.schemas.common import ApiModel


class GoogleLoginRequest(ApiModel):
    # 구글 ID 토큰. 검증에만 쓰고 검증이 끝나면 버린다. 저장하거나 로그에 남기지 않는다.
    id_token: str = Field(alias="idToken", min_length=1, max_length=8192)


class ConsentSubmission(ApiModel):
    service_data: bool = Field(alias="serviceData")
    sensitive_data: bool = Field(alias="sensitiveData")
    push_notification: bool = Field(alias="pushNotification")
    service_improvement: bool = Field(alias="serviceImprovement")


class ConsentRequest(ApiModel):
    registration_token: str = Field(alias="registrationToken", min_length=1)
    consent_version: str = Field(alias="consentVersion", min_length=1, max_length=20)
    consents: ConsentSubmission
    # 사용자가 입력한 표시 이름. 비우면 서버 기본값을 쓴다. 실명이 들어올 수 있으므로
    # 나중에 수정할 수 있어야 한다(data-contracts.md `Account`).
    display_name: str | None = Field(default=None, alias="displayName", max_length=100)


class ConsentItemResponse(ApiModel):
    granted: bool
    granted_at: datetime | None = Field(default=None, alias="grantedAt")


class AccountConsentResponse(ApiModel):
    consent_version: str = Field(alias="consentVersion")
    service_data: ConsentItemResponse = Field(alias="serviceData")
    sensitive_data: ConsentItemResponse = Field(alias="sensitiveData")
    service_improvement: ConsentItemResponse = Field(alias="serviceImprovement")
    push_notification: ConsentItemResponse = Field(alias="pushNotification")


class AccountResponse(ApiModel):
    """data-contracts.md 의 `Account`.

    구글 `sub` 와 ID 토큰은 계약에 포함하지 않으므로 이 응답에도 넣지 않는다.
    `email` 은 저장 범위가 확정되기 전까지 비어 있을 수 있다.
    """

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    account_id: str = Field(alias="accountId")
    auth_provider: Literal["google"] = Field(alias="authProvider")
    display_name: str = Field(alias="displayName")
    email: str | None = None
    consent: AccountConsentResponse
    created_at: datetime = Field(alias="createdAt")


class AuthenticatedResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    status: Literal["authenticated"] = "authenticated"
    access_token: str = Field(alias="accessToken")
    token_type: Literal["Bearer"] = Field(default="Bearer", alias="tokenType")
    expires_in: int = Field(alias="expiresIn")
    account: AccountResponse


class ConsentRequiredResponse(ApiModel):
    """구글 인증은 통과했지만 아직 계정이 없는 상태.

    이 응답을 받은 시점에는 계정이 만들어지지 않았다. 앱은 동의 화면을 띄우고
    `registrationToken` 과 함께 `POST /auth/consent` 를 호출한다.
    """

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    status: Literal["consentRequired"] = "consentRequired"
    registration_token: str = Field(alias="registrationToken")
    expires_in: int = Field(alias="expiresIn")
    consent_version: str = Field(alias="consentVersion")
    required_consents: list[str] = Field(alias="requiredConsents")
    optional_consents: list[str] = Field(alias="optionalConsents")


LoginResponse = Annotated[
    AuthenticatedResponse | ConsentRequiredResponse,
    Field(discriminator="status"),
]
