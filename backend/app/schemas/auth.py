from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field, StrictBool, model_validator

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
    # 나중에 수정할 수 있어야 한다(data-contracts.md `Account`). 길이는 API 1-2와
    # `users.display_name` 에 맞춘다.
    display_name: str | None = Field(default=None, alias="displayName", max_length=50)


class ConsentChangeRequest(ApiModel):
    """선택 동의 변경 (API 1-6). 보낸 항목만 바꾼다.

    동의는 명시적인 `true`/`false`만 받는다. `"yes"`나 `1`을 동의로 바꿔 읽지 않는다.
    """

    service_improvement: StrictBool | None = Field(
        default=None, alias="serviceImprovement"
    )
    push_notification: StrictBool | None = Field(
        default=None, alias="pushNotification"
    )
    # 필수 동의는 바꿀 수 없다. 형식 오류(`INVALID_REQUEST`)와 구분해
    # `REQUIRED_CONSENT_NOT_CHANGEABLE`로 알리려고 받기만 한다.
    service_data: bool | None = Field(
        default=None,
        alias="serviceData",
        description="바꿀 수 없다. 보내면 422 REQUIRED_CONSENT_NOT_CHANGEABLE",
    )
    sensitive_data: bool | None = Field(
        default=None,
        alias="sensitiveData",
        description="바꿀 수 없다. 보내면 422 REQUIRED_CONSENT_NOT_CHANGEABLE",
    )

    @model_validator(mode="after")
    def _optional_consents_are_not_null(self) -> "ConsentChangeRequest":
        for field in ("service_improvement", "push_notification"):
            if field in self.model_fields_set and getattr(self, field) is None:
                raise ValueError(f"{field}는 null일 수 없습니다.")
        return self

    def submitted(self) -> dict[str, bool | None]:
        """보낸 항목을 동의 이름(`serviceImprovement` 등)으로 돌려준다."""
        fields = type(self).model_fields
        return {
            fields[field].alias or field: getattr(self, field)
            for field in self.model_fields_set
        }


WithdrawalReason = Literal[
    "conditionChanged",
    "cardsNotHelpful",
    "infrequentVisits",
    "hardToUse",
    "recordingBurden",
    "other",
]


class WithdrawalRequest(ApiModel):
    """탈퇴 이유 (API 1-5). 고르지 않았으면 본문 없이 탈퇴한다.

    계정과 연결하지 않고 `withdrawal_feedback`에 저장한다. `otherText`는 보호자가 쓴
    글이므로 로그와 오류 메시지에 넣지 않는다.
    """

    # 탈퇴 화면의 이유 순서대로 보낸다.
    reasons: list[WithdrawalReason] = Field(min_length=1)
    other_text: str | None = Field(default=None, alias="otherText")

    @model_validator(mode="after")
    def _other_text_matches_reasons(self) -> "WithdrawalRequest":
        if len(set(self.reasons)) != len(self.reasons):
            raise ValueError("같은 탈퇴 이유를 두 번 보냈습니다.")
        if ("other" in self.reasons) != (self.other_text is not None):
            raise ValueError("otherText는 other를 고른 경우에만 보냅니다.")
        if self.other_text is not None and not self.other_text.strip():
            raise ValueError("otherText는 비울 수 없습니다.")
        return self


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
