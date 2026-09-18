from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# 구글이 ID 토큰의 `iss` 에 넣는 두 가지 값. 둘 다 같은 발급자를 뜻한다.
GOOGLE_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="SAEROK_",
        extra="ignore",
    )

    environment: Literal["development", "test", "production"] = "development"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = (
        "INFO"
    )
    service_name: str = "saerok-backend"
    service_version: str = "0.1.0"

    # 구글 ID 토큰의 `aud` 로 허용할 클라이언트 ID 목록. 쉼표로 구분한다.
    # `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 그 웹 클라이언트 ID가
    # 되므로, FE 가 어떤 값을 쓰는지 확인한 뒤 채운다. 비어 있으면 로그인을 거부한다.
    google_client_ids: tuple[str, ...] = ()
    google_jwks_url: str = GOOGLE_JWKS_URL
    google_jwks_cache_seconds: int = Field(default=3600, ge=60)

    # 자체 세션 토큰 서명 키. 비어 있으면 인증 경로 전체가 503 으로 거부된다.
    # HS256 서명에 쓰므로 32바이트 미만은 설정 단계에서 막는다(RFC 7518 3.2).
    session_secret: str = ""
    session_ttl_seconds: int = Field(default=3600, ge=60)
    # 구글 인증과 동의 제출 사이에만 쓰는 임시 등록 토큰의 수명.
    registration_ttl_seconds: int = Field(default=600, ge=60)

    # 동의 화면이 제시하는 약관 버전. 계약의 `consentVersion` 과 같은 값이다.
    consent_version: str = "2026-09-06"

    # ADR-007 의 PM 제안(이메일과 구글 계정 이름을 저장하지 않음)을 기본값으로 둔다.
    # 저장 범위가 확정되면 이 값을 바꾸고 ADR-007 과 법률 문서를 함께 갱신한다.
    store_google_profile: bool = False
    # 구글 계정 이름을 저장하지 않을 때 쓰는 기본 표시 이름.
    default_display_name: str = "보호자"

    @field_validator("session_secret")
    @classmethod
    def _reject_short_secret(cls, value: str) -> str:
        if value and len(value.encode("utf-8")) < 32:
            raise ValueError("session_secret 은 32바이트 이상이어야 한다")
        return value

    @field_validator("google_client_ids", mode="before")
    @classmethod
    def _split_client_ids(cls, value: object) -> object:
        if isinstance(value, str):
            return tuple(part.strip() for part in value.split(",") if part.strip())
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
