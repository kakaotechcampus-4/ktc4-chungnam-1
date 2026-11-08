"""잘못된 토큰은 DB 연결을 열기 전에 거절한다.

인증이 필요한 모든 경로와 구글 로그인(1-1), 동의 제출(1-2)은 토큰의 형식, 서명, 만료와
종류(`typ`)를 먼저 확인하고, 통과한 요청만 DB 연결을 연다. `app.api.deps.connect` 를 열린
횟수만 세는 대역으로 바꿔 실제 DB 없이 확인한다. 대역은 열리는 순간 실패하므로, 통과한
요청은 500 이 되고 열린 횟수가 1 이 된다(대조군).
"""

import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response

from app.api import deps
from app.api.deps import get_google_verifier
from app.core.config import Settings, get_settings
from app.main import create_app
from app.services.google_identity import GoogleIdTokenVerifier
from app.services.session_tokens import TokenIssuer
from tests import google_tokens
from tests.support import run

SESSION_SECRET = "test-session-secret-value-32bytes-long"
# 대역 connect 에만 넘어가는 주소다. 실제로 접속하지 않는다.
UNUSED_DATABASE_URL = "postgresql://saerok@127.0.0.1:9/unused"
SERVICE_NAME = Settings(_env_file=None).service_name

ISSUER = TokenIssuer(
    secret=SESSION_SECRET,
    issuer=SERVICE_NAME,
    session_ttl_seconds=3600,
    registration_ttl_seconds=600,
)
FOREIGN_ISSUER = TokenIssuer(
    secret="another-session-secret-value-32bytes",
    issuer=SERVICE_NAME,
    session_ttl_seconds=3600,
    registration_ttl_seconds=600,
)


def _expired(token_type: str, **claims: Any) -> str:
    issued_at = datetime.now(UTC) - timedelta(hours=2)
    return jwt.encode(
        {
            "sub": "acc-expired",
            "typ": token_type,
            "iss": SERVICE_NAME,
            "iat": issued_at,
            "exp": issued_at + timedelta(hours=1),
            **claims,
        },
        SESSION_SECRET,
        algorithm="HS256",
    )


def _registration() -> str:
    return ISSUER.issue_registration(provider="google", social_id="google-sub-0001").value


BAD_SESSIONS: dict[str, str | None] = {
    "missing": None,
    "garbage": "not-a-jwt",
    "foreign-signature": FOREIGN_ISSUER.issue_session("acc-1").value,
    "expired": _expired("session", jti="expired-session"),
    "registration-token": _registration(),
}


@pytest.fixture
def connections(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    opened: list[str] = []

    @asynccontextmanager
    async def connect(database_url: str) -> AsyncIterator[Any]:
        opened.append(database_url)
        raise RuntimeError("DB 연결을 열었다")
        yield  # pragma: no cover

    monkeypatch.setattr(deps, "connect", connect)
    return opened


def _app(*, jwks_fails: bool = False) -> FastAPI:
    async def fetcher() -> dict[str, Any]:
        if jwks_fails:
            raise RuntimeError("jwks unavailable")
        return google_tokens.jwks_document()

    settings = Settings(
        _env_file=None,
        session_secret=SESSION_SECRET,
        database_url=UNUSED_DATABASE_URL,
    )
    verifier = GoogleIdTokenVerifier(
        allowed_audiences=(google_tokens.CLIENT_ID,),
        jwks_fetcher=fetcher,
        cache_seconds=3600,
    )
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_google_verifier] = lambda: verifier
    return app


def _authenticated_routes() -> list[tuple[str, str]]:
    # OpenAPI 에서 Bearer 인증을 요구하는 경로를 모두 고른다. 경로 변수는 아무 값으로 채운다.
    routes = []
    for path, operations in create_app().openapi()["paths"].items():
        for method, operation in operations.items():
            if {"HTTPBearer": []} in operation.get("security", []):
                routes.append((method.upper(), re.sub(r"\{[^}]+\}", "x", path)))
    return sorted(routes)


AUTHENTICATED_ROUTES = _authenticated_routes()


def _send_all(
    app: FastAPI, method: str, path: str, calls: list[dict[str, Any]]
) -> list[Response]:
    # 요청마다 이벤트 루프를 새로 만들지 않고 한 루프에서 보낸다. 이 PC의 Windows에서는
    # 루프를 만들 때 쓰는 socketpair가 드물게 멈추므로 루프 수를 줄인다.
    async def send() -> list[Response]:
        transport = ASGITransport(app=app, raise_app_exceptions=False)
        responses = []
        async with AsyncClient(
            transport=transport, base_url="http://testserver"
        ) as client:
            for call in calls:
                token = call.get("token")
                headers = None if token is None else {"Authorization": f"Bearer {token}"}
                responses.append(
                    await client.request(
                        method, path, json=call.get("json"), headers=headers
                    )
                )
        return responses

    return run(send())


def _send(
    app: FastAPI,
    method: str,
    path: str,
    *,
    token: str | None = None,
    json: dict[str, Any] | None = None,
) -> Response:
    return _send_all(app, method, path, [{"token": token, "json": json}])[0]


def test_authenticated_routes_are_found() -> None:
    assert ("GET", "/auth/me") in AUTHENTICATED_ROUTES
    assert ("POST", "/api/v1/visit-sessions/x/speech-analyses") in AUTHENTICATED_ROUTES
    assert ("POST", "/auth/google") not in AUTHENTICATED_ROUTES
    assert len(AUTHENTICATED_ROUTES) > 20


@pytest.mark.parametrize(("method", "path"), AUTHENTICATED_ROUTES)
def test_bad_session_is_rejected_before_opening_a_db_connection(
    method: str, path: str, connections: list[str]
) -> None:
    sent = _send_all(
        _app(), method, path, [{"token": token} for token in BAD_SESSIONS.values()]
    )
    responses = dict(zip(BAD_SESSIONS, sent, strict=True))

    statuses = {name: response.status_code for name, response in responses.items()}
    assert statuses == {name: 401 for name in BAD_SESSIONS}
    assert responses["expired"].json()["errorCode"] == "SESSION_EXPIRED"
    assert connections == []


def test_valid_session_opens_the_db_connection(connections: list[str]) -> None:
    # 대조군. 서명이 맞는 세션은 폐기 여부를 보려고 DB 연결을 연다.
    session = ISSUER.issue_session("acc-1").value

    response = _send(_app(), "GET", "/auth/me", token=session)

    assert response.status_code == 500
    assert connections == [UNUSED_DATABASE_URL]


BAD_ID_TOKENS = {
    "unknown-kid": (google_tokens.id_token(key_id="unknown-key-id"), "INVALID_ID_TOKEN"),
    "foreign-signature": (
        google_tokens.id_token(signing_key=google_tokens.FOREIGN_KEY),
        "INVALID_ID_TOKEN",
    ),
    "expired": (google_tokens.id_token(expires_in=-30), "ID_TOKEN_EXPIRED"),
    "audience": (
        google_tokens.id_token(audience="other-client-id"),
        "ID_TOKEN_AUDIENCE_MISMATCH",
    ),
    "garbage": ("not-a-jwt", "INVALID_ID_TOKEN"),
}


@pytest.mark.parametrize(
    ("token", "error_code"), BAD_ID_TOKENS.values(), ids=BAD_ID_TOKENS.keys()
)
def test_bad_google_token_is_rejected_before_opening_a_db_connection(
    token: str, error_code: str, connections: list[str]
) -> None:
    response = _send(_app(), "POST", "/auth/google", json={"idToken": token})

    assert response.status_code == 401
    assert response.json()["errorCode"] == error_code
    assert connections == []


def test_jwks_failure_does_not_open_a_db_connection(connections: list[str]) -> None:
    response = _send(
        _app(jwks_fails=True),
        "POST",
        "/auth/google",
        json={"idToken": google_tokens.id_token()},
    )

    assert response.status_code == 503
    assert response.json()["errorCode"] == "IDENTITY_PROVIDER_UNAVAILABLE"
    assert connections == []


def test_valid_google_token_opens_the_db_connection(connections: list[str]) -> None:
    # 대조군. 검증을 통과한 토큰만 계정을 찾으려고 DB 연결을 연다.
    response = _send(
        _app(), "POST", "/auth/google", json={"idToken": google_tokens.id_token()}
    )

    assert response.status_code == 500
    assert connections == [UNUSED_DATABASE_URL]


def _consent(registration_token: str) -> dict[str, Any]:
    return {
        "registrationToken": registration_token,
        "consentVersion": Settings(_env_file=None).consent_version,
        "consents": {
            "serviceData": True,
            "sensitiveData": True,
            "pushNotification": False,
            "serviceImprovement": False,
        },
    }


BAD_REGISTRATION_TOKENS = {
    "garbage": ("not-a-jwt", "INVALID_REGISTRATION_TOKEN"),
    "foreign-signature": (
        FOREIGN_ISSUER.issue_registration(
            provider="google", social_id="google-sub-0001"
        ).value,
        "INVALID_REGISTRATION_TOKEN",
    ),
    "session-token": (ISSUER.issue_session("acc-1").value, "INVALID_REGISTRATION_TOKEN"),
    "expired": (
        _expired("registration", provider="google"),
        "REGISTRATION_TOKEN_EXPIRED",
    ),
}


@pytest.mark.parametrize(
    ("token", "error_code"),
    BAD_REGISTRATION_TOKENS.values(),
    ids=BAD_REGISTRATION_TOKENS.keys(),
)
def test_bad_registration_token_is_rejected_before_opening_a_db_connection(
    token: str, error_code: str, connections: list[str]
) -> None:
    response = _send(_app(), "POST", "/auth/consent", json=_consent(token))

    assert response.status_code == 401
    assert response.json()["errorCode"] == error_code
    assert connections == []


def test_valid_registration_token_opens_the_db_connection(
    connections: list[str],
) -> None:
    # 대조군. 등록 토큰이 맞으면 계정을 찾으려고 DB 연결을 연다.
    response = _send(_app(), "POST", "/auth/consent", json=_consent(_registration()))

    assert response.status_code == 500
    assert connections == [UNUSED_DATABASE_URL]
