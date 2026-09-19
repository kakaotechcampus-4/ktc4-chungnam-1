"""구글 ID 토큰 검증.

ADR-007 에 따라 Firebase Auth 를 쓰지 않고, 앱이 `google_sign_in` 으로 받은 ID 토큰을
백엔드가 구글 공개키(JWKS)로 직접 검증한다. 서명, `aud`, `iss` 와 만료를 모두 확인하며
어느 하나라도 확인할 수 없으면 거부한다. 검증을 건너뛰고 통과시키는 경로는 없다.

ID 토큰과 토큰에서 읽은 값은 로그와 오류 메시지에 남기지 않는다.
"""

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from time import monotonic
from typing import Any

import httpx
import jwt

from app.core.config import GOOGLE_ISSUERS
from app.core.errors import AppError

logger = logging.getLogger("saerok.auth")

JwksFetcher = Callable[[], Awaitable[dict[str, Any]]]

_REQUIRED_CLAIMS = ["iss", "aud", "exp", "iat", "sub"]


@dataclass(frozen=True)
class GoogleIdentity:
    """검증을 마친 ID 토큰에서 꺼낸 값.

    `subject` 는 구글 계정의 `sub` 이며 `(provider, social_id)` 의 식별자로만 쓴다.
    `email` 과 `name` 은 저장 범위가 확정되지 않았으므로 호출하는 쪽에서
    `store_google_profile` 설정에 따라 쓸지 버릴지 결정한다.
    """

    subject: str
    email: str | None
    name: str | None


def _unavailable() -> AppError:
    return AppError(
        status_code=503,
        error_code="IDENTITY_PROVIDER_UNAVAILABLE",
        message="구글 인증 서버를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.",
        retryable=True,
    )


def _invalid(error_code: str, message: str) -> AppError:
    return AppError(status_code=401, error_code=error_code, message=message)


async def fetch_google_jwks(url: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(url)
        response.raise_for_status()
        return response.json()


class GoogleIdTokenVerifier:
    def __init__(
        self,
        *,
        allowed_audiences: tuple[str, ...],
        jwks_fetcher: JwksFetcher,
        cache_seconds: int,
    ) -> None:
        self._allowed_audiences = allowed_audiences
        self._fetch = jwks_fetcher
        self._cache_seconds = cache_seconds
        self._lock = asyncio.Lock()
        self._key_set: jwt.PyJWKSet | None = None
        self._fetched_at: float = 0.0

    async def verify(self, id_token: str) -> GoogleIdentity:
        if not self._allowed_audiences:
            # 허용할 클라이언트 ID 를 모르면 `aud` 를 확인할 수 없다. 확인하지 못한
            # 토큰을 통과시키지 않고 설정 오류로 거부한다.
            raise AppError(
                status_code=503,
                error_code="AUTH_NOT_CONFIGURED",
                message="로그인 설정이 완료되지 않았습니다.",
            )

        try:
            key_id = jwt.get_unverified_header(id_token).get("kid")
        except jwt.PyJWTError:
            raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.") from None
        if not isinstance(key_id, str):
            raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.")

        signing_key = await self._signing_key(key_id)
        payload = self._decode(id_token, signing_key)

        subject = payload.get("sub")
        if not isinstance(subject, str) or not subject:
            raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.")

        email = payload.get("email")
        name = payload.get("name")
        return GoogleIdentity(
            subject=subject,
            email=email if isinstance(email, str) else None,
            name=name if isinstance(name, str) else None,
        )

    def _decode(self, id_token: str, signing_key: jwt.PyJWK) -> dict[str, Any]:
        try:
            payload = jwt.decode(
                id_token,
                key=signing_key.key,
                algorithms=["RS256"],
                audience=list(self._allowed_audiences),
                # `iss` 는 허용 값이 두 개라 아래에서 직접 비교한다.
                options={"verify_iss": False, "require": _REQUIRED_CLAIMS},
            )
        except jwt.ExpiredSignatureError:
            raise _invalid("ID_TOKEN_EXPIRED", "만료된 구글 토큰입니다.") from None
        except jwt.InvalidAudienceError:
            raise _invalid(
                "ID_TOKEN_AUDIENCE_MISMATCH",
                "이 앱에서 발급되지 않은 구글 토큰입니다.",
            ) from None
        except jwt.PyJWTError:
            raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.") from None

        if payload.get("iss") not in GOOGLE_ISSUERS:
            raise _invalid(
                "ID_TOKEN_ISSUER_MISMATCH",
                "구글이 발급한 토큰이 아닙니다.",
            )
        return payload

    async def _signing_key(self, key_id: str) -> jwt.PyJWK:
        # `_key_set_for` 는 캐시에 `key_id` 가 없으면 이미 한 번 `_refresh` 한다.
        # 여기서 다시 `_refresh` 하면 같은 요청에서 JWKS 를 두 번 조회하게 되므로
        # 추가 조회 없이 그 결과로만 판단하고, 그래도 없으면 통과시키지 않고 거부한다.
        key_set = await self._key_set_for(key_id)
        for key in key_set.keys:
            if key.key_id == key_id:
                return key
        raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.")

    async def _key_set_for(self, key_id: str) -> jwt.PyJWKSet:
        cached = self._key_set
        if cached is not None and monotonic() - self._fetched_at < self._cache_seconds:
            if any(key.key_id == key_id for key in cached.keys):
                return cached
        return await self._refresh()

    async def _refresh(self) -> jwt.PyJWKSet:
        async with self._lock:
            try:
                document = await self._fetch()
                key_set = jwt.PyJWKSet.from_dict(document)
            except AppError:
                raise
            except Exception:
                # 조회 실패를 검증 성공으로 바꾸지 않는다. 호출하는 쪽에는 재시도
                # 가능한 503 으로만 알린다.
                logger.warning("google_jwks_fetch_failed")
                raise _unavailable() from None

            self._key_set = key_set
            self._fetched_at = monotonic()
            return key_set
