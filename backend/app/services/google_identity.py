"""구글 ID 토큰 검증.

ADR-007 에 따라 Firebase Auth 를 쓰지 않고, 앱이 `google_sign_in` 으로 받은 ID 토큰을
백엔드가 구글 공개키(JWKS)로 직접 검증한다. 서명, `aud`, `iss` 와 만료를 모두 확인하며
어느 하나라도 확인할 수 없으면 거부한다. 검증을 건너뛰고 통과시키는 경로는 없다.

토큰 머리의 `kid` 는 서명을 확인하기 전에 읽으므로 로그인하지 않은 누구나 마음대로 정할 수
있다. 그래서 JWKS 를 다시 받는 횟수를 다음처럼 묶는다.

- 동시에 들어온 요청이 모두 다시 받아야 하면 한 요청만 받고 나머지는 그 결과(실패 포함)를 같이 쓴다.
- 캐시가 아직 유효한데 그 안에 없는 `kid` 가 오면, 마지막 조회(성공과 실패 모두) 뒤
  `UNKNOWN_KEY_REFRESH_SECONDS` 가 지났을 때만 다시 받는다. 그 안에서는 받지 않고 거부한다. 마지막
  조회가 실패였으면 503, 성공이었으면 401 이다. 키 교체로 새 `kid` 가 오면 간격이 지난 뒤 한 번 다시
  받아 찾는다. 마지막 조회 뒤 간격 안에 처음 보는 새 키의 토큰이 오면 그 사이에는 거부된다.

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

# 캐시에 없는 `kid` 때문에 JWKS 를 다시 받는 최소 간격(초).
UNKNOWN_KEY_REFRESH_SECONDS = 60.0


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
        unknown_key_refresh_seconds: float = UNKNOWN_KEY_REFRESH_SECONDS,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        self._allowed_audiences = allowed_audiences
        self._fetch = jwks_fetcher
        self._cache_seconds = cache_seconds
        self._unknown_key_refresh_seconds = unknown_key_refresh_seconds
        self._clock = clock
        self._lock = asyncio.Lock()
        self._key_set: jwt.PyJWKSet | None = None
        # 마지막으로 받아 오는 데 성공한 시각. 캐시 유효 기간의 기준이다.
        self._fetched_at: float = 0.0
        # 마지막으로 받아 오기를 끝낸 시각과 그 결과. 성공과 실패를 모두 센다.
        self._attempted_at: float | None = None
        self._attempt_failed = False
        # 받아 오기를 끝낼 때마다 1씩 는다. 잠금을 기다리는 동안 다른 요청이 받아 왔는지 본다.
        self._attempts = 0

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
        # `_key_set_for` 는 캐시에 `key_id` 가 없으면 필요할 때 이미 한 번 `_refresh` 한다.
        # 여기서 다시 `_refresh` 하면 같은 요청에서 JWKS 를 두 번 조회하게 되므로
        # 추가 조회 없이 그 결과로만 판단하고, 그래도 없으면 통과시키지 않고 거부한다.
        key_set = await self._key_set_for(key_id)
        for key in key_set.keys:
            if key.key_id == key_id:
                return key
        raise _invalid("INVALID_ID_TOKEN", "유효하지 않은 구글 토큰입니다.")

    async def _key_set_for(self, key_id: str) -> jwt.PyJWKSet:
        now = self._clock()
        cached = self._key_set
        if cached is not None and now - self._fetched_at < self._cache_seconds:
            if any(key.key_id == key_id for key in cached.keys):
                return cached
            if self._attempted_recently(now):
                # 방금 받아 본 JWKS 에도 없는 `kid` 다. 간격 안에서는 다시 받지 않는다.
                if self._attempt_failed:
                    raise _unavailable()
                return cached
        return await self._refresh()

    def _attempted_recently(self, now: float) -> bool:
        return (
            self._attempted_at is not None
            and now - self._attempted_at < self._unknown_key_refresh_seconds
        )

    async def _refresh(self) -> jwt.PyJWKSet:
        attempts = self._attempts
        async with self._lock:
            if self._attempts != attempts:
                # 잠금을 기다리는 동안 다른 요청이 받아 왔다. 다시 받지 않고 그 결과를 쓴다.
                if self._attempt_failed or self._key_set is None:
                    raise _unavailable()
                return self._key_set
            try:
                document = await self._fetch()
                key_set = jwt.PyJWKSet.from_dict(document)
            except AppError:
                self._finish_attempt(failed=True)
                raise
            except Exception:
                # 조회 실패를 검증 성공으로 바꾸지 않는다. 호출하는 쪽에는 재시도
                # 가능한 503 으로만 알린다.
                self._finish_attempt(failed=True)
                logger.warning("google_jwks_fetch_failed")
                raise _unavailable() from None

            self._key_set = key_set
            self._fetched_at = self._clock()
            self._finish_attempt(failed=False)
            return key_set

    def _finish_attempt(self, *, failed: bool) -> None:
        self._attempts += 1
        self._attempted_at = self._clock()
        self._attempt_failed = failed
