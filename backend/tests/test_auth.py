"""구글 소셜 로그인 (ADR-007) 검증.

ADR-007 의 검증 항목을 그대로 옮겼다. 실제 사용자 계정은 쓰지 않고 테스트에서 만든
키로 서명한 토큰만 쓴다.
"""

import asyncio
from typing import Any

import pytest
from fastapi import FastAPI

from app.api.deps import get_account_repository, get_google_verifier
from app.core.config import Settings, get_settings
from app.main import create_app
from app.services.accounts import InMemoryAccountRepository
from app.services.google_identity import GoogleIdTokenVerifier
from tests import google_tokens
from tests.support import request

CONSENT_VERSION = "2026-09-06"
ALL_GRANTED = {
    "serviceData": True,
    "sensitiveData": True,
    "pushNotification": True,
    "serviceImprovement": True,
}


class _Harness:
    def __init__(self, app: FastAPI, repository: InMemoryAccountRepository) -> None:
        self.app = app
        self.repository = repository

    def login(self, token: str) -> Any:
        return request(self.app, "POST", "/auth/google", json={"idToken": token})

    def consent(self, **payload: Any) -> Any:
        return request(self.app, "POST", "/auth/consent", json=payload)

    def me(self, access_token: str) -> Any:
        return request(
            self.app,
            "GET",
            "/auth/me",
            headers={"Authorization": f"Bearer {access_token}"},
        )

    def stored_account(self, social_id: str = "google-sub-0001") -> Any:
        return asyncio.run(
            self.repository.find_by_social_identity(
                provider="google", social_id=social_id
            )
        )


def _harness(
    *,
    audiences: tuple[str, ...] = (google_tokens.CLIENT_ID,),
    session_secret: str = "test-session-secret-value-32bytes-long",
    store_google_profile: bool = False,
    jwks_fails: bool = False,
) -> _Harness:
    async def fetcher() -> dict[str, Any]:
        if jwks_fails:
            raise RuntimeError("jwks unavailable")
        return google_tokens.jwks_document()

    settings = Settings(
        _env_file=None,
        session_secret=session_secret,
        consent_version=CONSENT_VERSION,
        store_google_profile=store_google_profile,
    )
    verifier = GoogleIdTokenVerifier(
        allowed_audiences=audiences,
        jwks_fetcher=fetcher,
        cache_seconds=3600,
    )
    repository = InMemoryAccountRepository()

    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_google_verifier] = lambda: verifier
    app.dependency_overrides[get_account_repository] = lambda: repository
    return _Harness(app, repository)


def _register(harness: _Harness, token: str | None = None) -> Any:
    login = harness.login(token or google_tokens.id_token())
    assert login.status_code == 200
    return harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents=ALL_GRANTED,
    )


def test_google_login_asks_for_consent_without_creating_account() -> None:
    harness = _harness()

    response = harness.login(google_tokens.id_token())

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "consentRequired"
    assert body["consentVersion"] == CONSENT_VERSION
    assert sorted(body["requiredConsents"]) == [
        "pushNotification",
        "sensitiveData",
        "serviceData",
    ]
    assert body["optionalConsents"] == ["serviceImprovement"]
    assert "accessToken" not in body
    assert harness.stored_account() is None


def test_account_is_created_when_required_consent_completes() -> None:
    harness = _harness()

    response = _register(harness)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "authenticated"
    assert body["tokenType"] == "Bearer"
    assert body["expiresIn"] == 3600
    account = body["account"]
    assert account["schemaVersion"] == 1
    assert account["authProvider"] == "google"
    assert account["consent"]["consentVersion"] == CONSENT_VERSION
    assert account["consent"]["serviceData"]["granted"] is True
    assert account["consent"]["serviceData"]["grantedAt"] is not None
    assert harness.stored_account() is not None


def test_same_google_account_does_not_create_a_second_account() -> None:
    harness = _harness()
    first = _register(harness).json()["account"]["accountId"]

    second = harness.login(google_tokens.id_token())

    assert second.status_code == 200
    body = second.json()
    assert body["status"] == "authenticated"
    assert body["account"]["accountId"] == first


def test_refusing_a_required_consent_does_not_create_an_account() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents={**ALL_GRANTED, "sensitiveData": False},
    )

    assert response.status_code == 422
    assert response.json()["errorCode"] == "REQUIRED_CONSENT_MISSING"
    assert harness.stored_account() is None


def test_refusing_the_optional_consent_still_creates_an_account() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents={**ALL_GRANTED, "serviceImprovement": False},
    )

    assert response.status_code == 200
    improvement = response.json()["account"]["consent"]["serviceImprovement"]
    assert improvement == {"granted": False, "grantedAt": None}


def test_consent_version_mismatch_is_rejected() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion="1999-01-01",
        consents=ALL_GRANTED,
    )

    assert response.status_code == 409
    assert response.json()["errorCode"] == "CONSENT_VERSION_MISMATCH"
    assert harness.stored_account() is None


@pytest.mark.parametrize(
    ("token", "error_code"),
    [
        (
            google_tokens.id_token(signing_key=google_tokens.FOREIGN_KEY),
            "INVALID_ID_TOKEN",
        ),
        (google_tokens.id_token(expires_in=-30), "ID_TOKEN_EXPIRED"),
        (
            google_tokens.id_token(audience="other-client-id"),
            "ID_TOKEN_AUDIENCE_MISMATCH",
        ),
        (
            google_tokens.id_token(issuer="https://accounts.example.com"),
            "ID_TOKEN_ISSUER_MISMATCH",
        ),
        ("not-a-jwt", "INVALID_ID_TOKEN"),
    ],
)
def test_unverifiable_tokens_are_rejected_without_creating_an_account(
    token: str, error_code: str
) -> None:
    harness = _harness()

    response = harness.login(token)

    assert response.status_code == 401
    assert response.json()["errorCode"] == error_code
    assert harness.stored_account() is None


def test_jwks_failure_never_passes_verification() -> None:
    harness = _harness(jwks_fails=True)

    response = harness.login(google_tokens.id_token())

    assert response.status_code == 503
    body = response.json()
    assert body["errorCode"] == "IDENTITY_PROVIDER_UNAVAILABLE"
    assert body["retryable"] is True
    assert harness.stored_account() is None


def test_login_is_refused_when_no_client_id_is_configured() -> None:
    harness = _harness(audiences=())

    response = harness.login(google_tokens.id_token())

    assert response.status_code == 503
    assert response.json()["errorCode"] == "AUTH_NOT_CONFIGURED"


def test_login_is_refused_when_the_session_secret_is_missing() -> None:
    harness = _harness(session_secret="")

    response = harness.login(google_tokens.id_token())

    assert response.status_code == 503
    assert response.json()["errorCode"] == "AUTH_NOT_CONFIGURED"


def test_session_token_returns_the_account() -> None:
    harness = _harness()
    registered = _register(harness).json()

    response = harness.me(registered["accessToken"])

    assert response.status_code == 200
    assert response.json() == registered["account"]


def test_registration_token_cannot_be_used_as_a_session() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.me(login.json()["registrationToken"])

    assert response.status_code == 401
    assert response.json()["errorCode"] == "UNAUTHENTICATED"


def test_missing_session_is_rejected() -> None:
    harness = _harness()

    response = request(harness.app, "GET", "/auth/me")

    assert response.status_code == 401
    assert response.json()["errorCode"] == "UNAUTHENTICATED"


def test_google_profile_fields_are_not_stored_by_default() -> None:
    harness = _harness()
    token = google_tokens.id_token(email="tester@example.com", name="구글 이름")

    login = harness.login(token)
    registered = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents=ALL_GRANTED,
        displayName="보호자 표시 이름",
    )

    account = registered.json()["account"]
    assert account["email"] is None
    assert account["displayName"] == "보호자 표시 이름"
    assert "tester@example.com" not in registered.text
    assert "구글 이름" not in registered.text


def test_responses_do_not_expose_the_google_subject() -> None:
    harness = _harness()
    token = google_tokens.id_token(subject="google-sub-0001")

    registered = _register(harness, token)

    assert "google-sub-0001" not in registered.text
    assert "socialId" not in registered.text
    assert "idToken" not in registered.text
