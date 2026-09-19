"""자체 세션 토큰과 등록 토큰 발급.

ADR-007 은 세션의 형식과 수명, 갱신 방식을 BE 가 정하도록 남겨두었다. 현재 구현은
다음과 같으며 확정 시 ADR-007 에 추가한다.

- 형식: HS256 으로 서명한 JWT. 별도의 리프레시 토큰을 두지 않는다.
- 수명: `SAEROK_SESSION_TTL_SECONDS`(기본 1시간).
- 갱신: 앱이 `google_sign_in` 의 무음 로그인으로 새 ID 토큰을 받아
  `POST /auth/google` 을 다시 호출한다. 서버가 보관하는 갱신 자격증명은 없다.

등록 토큰은 구글 인증과 동의 제출 사이에서만 쓰는 짧은 수명의 토큰이다. 아직 계정이
없는 상태를 이어주기 위해 제공자 식별자를 담으므로, 세션 토큰과 `typ` 으로 구분해서
서로의 용도로 쓰이지 않게 한다. 저장하기로 한 항목만 담으며, 기본 설정에서는 제공자
식별자 외에 아무것도 담지 않는다.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt

from app.core.errors import AppError

_SESSION_TYPE = "session"
_REGISTRATION_TYPE = "registration"


@dataclass(frozen=True)
class IssuedToken:
    value: str
    expires_in: int


@dataclass(frozen=True)
class RegistrationClaims:
    provider: Literal["google"]
    social_id: str
    email: str | None = None
    name: str | None = None


class TokenIssuer:
    def __init__(
        self,
        *,
        secret: str,
        issuer: str,
        session_ttl_seconds: int,
        registration_ttl_seconds: int,
    ) -> None:
        self._secret = secret
        self._issuer = issuer
        self._session_ttl = session_ttl_seconds
        self._registration_ttl = registration_ttl_seconds

    def issue_session(self, account_id: str) -> IssuedToken:
        return self._issue(
            {"sub": account_id, "typ": _SESSION_TYPE},
            ttl_seconds=self._session_ttl,
        )

    def issue_registration(
        self,
        *,
        provider: str,
        social_id: str,
        email: str | None = None,
        name: str | None = None,
    ) -> IssuedToken:
        claims: dict[str, Any] = {
            "sub": social_id,
            "typ": _REGISTRATION_TYPE,
            "provider": provider,
        }
        # 저장하지 않기로 한 항목은 토큰에도 넣지 않는다. 호출하는 쪽이
        # `store_google_profile` 설정을 보고 넘길지 정한다.
        if email is not None:
            claims["email"] = email
        if name is not None:
            claims["name"] = name
        return self._issue(claims, ttl_seconds=self._registration_ttl)

    def read_session(self, token: str) -> str:
        payload = self._decode(
            token,
            expected_type=_SESSION_TYPE,
            expired_code="SESSION_EXPIRED",
            expired_message="세션이 만료되었습니다. 다시 로그인해 주세요.",
            invalid_code="UNAUTHENTICATED",
            invalid_message="로그인이 필요합니다.",
        )
        account_id = payload.get("sub")
        if not isinstance(account_id, str) or not account_id:
            raise self._error(401, "UNAUTHENTICATED", "로그인이 필요합니다.")
        return account_id

    def read_registration(self, token: str) -> RegistrationClaims:
        payload = self._decode(
            token,
            expected_type=_REGISTRATION_TYPE,
            expired_code="REGISTRATION_TOKEN_EXPIRED",
            expired_message="동의 진행 시간이 지났습니다. 다시 로그인해 주세요.",
            invalid_code="INVALID_REGISTRATION_TOKEN",
            invalid_message="유효하지 않은 등록 토큰입니다.",
        )
        social_id = payload.get("sub")
        provider = payload.get("provider")
        if not isinstance(social_id, str) or not social_id or provider != "google":
            raise self._error(
                401,
                "INVALID_REGISTRATION_TOKEN",
                "유효하지 않은 등록 토큰입니다.",
            )
        email = payload.get("email")
        name = payload.get("name")
        return RegistrationClaims(
            provider="google",
            social_id=social_id,
            email=email if isinstance(email, str) else None,
            name=name if isinstance(name, str) else None,
        )

    def _issue(self, claims: dict[str, Any], *, ttl_seconds: int) -> IssuedToken:
        self._require_secret()
        issued_at = datetime.now(UTC)
        payload = {
            **claims,
            "iss": self._issuer,
            "iat": issued_at,
            "exp": issued_at + timedelta(seconds=ttl_seconds),
        }
        return IssuedToken(
            value=jwt.encode(payload, self._secret, algorithm="HS256"),
            expires_in=ttl_seconds,
        )

    def _decode(
        self,
        token: str,
        *,
        expected_type: str,
        expired_code: str,
        expired_message: str,
        invalid_code: str,
        invalid_message: str,
    ) -> dict[str, Any]:
        self._require_secret()
        try:
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                issuer=self._issuer,
                options={"require": ["sub", "typ", "iss", "iat", "exp"]},
            )
        except jwt.ExpiredSignatureError:
            raise self._error(401, expired_code, expired_message) from None
        except jwt.PyJWTError:
            raise self._error(401, invalid_code, invalid_message) from None

        if payload.get("typ") != expected_type:
            # 등록 토큰으로 보호된 API 를 부르거나 그 반대로 쓰는 경로를 막는다.
            raise self._error(401, invalid_code, invalid_message)
        return payload

    def _require_secret(self) -> None:
        if not self._secret:
            raise AppError(
                status_code=503,
                error_code="AUTH_NOT_CONFIGURED",
                message="로그인 설정이 완료되지 않았습니다.",
            )

    @staticmethod
    def _error(status_code: int, error_code: str, message: str) -> AppError:
        return AppError(
            status_code=status_code, error_code=error_code, message=message
        )
