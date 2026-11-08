"""구글 소셜 로그인 (ADR-007) 검증.

ADR-007 의 검증 항목을 그대로 옮겼다. 실제 사용자 계정은 쓰지 않고 테스트에서 만든
키로 서명한 토큰만 쓴다.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
import pytest
from fastapi import FastAPI

from app.api.deps import (
    get_account_repository,
    get_google_verifier,
    get_session_revocations,
)
from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.main import create_app
from app.services.accounts import InMemoryAccountRepository
from app.services.google_identity import (
    UNKNOWN_KEY_REFRESH_SECONDS,
    GoogleIdTokenVerifier,
)
from app.services.session_revocations import InMemorySessionRevocationStore
from app.services.session_tokens import SessionClaims
from tests import google_tokens
from tests.support import request

SESSION_SECRET = "test-session-secret-value-32bytes-long"

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

    def logout(self, access_token: str) -> Any:
        return request(
            self.app,
            "POST",
            "/auth/logout",
            headers={"Authorization": f"Bearer {access_token}"},
        )

    def delete_me(self, access_token: str) -> Any:
        return request(
            self.app,
            "DELETE",
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
    session_secret: str = SESSION_SECRET,
    store_google_profile: bool = False,
    jwks_fails: bool = False,
    database_url: str | None = None,
) -> _Harness:
    """`database_url` 을 주면 메모리 대역 대신 그 DB 의 계정 저장소와 폐기 기록을 쓴다."""

    async def fetcher() -> dict[str, Any]:
        if jwks_fails:
            raise RuntimeError("jwks unavailable")
        return google_tokens.jwks_document()

    settings = Settings(
        _env_file=None,
        session_secret=session_secret,
        consent_version=CONSENT_VERSION,
        store_google_profile=store_google_profile,
        database_url=database_url,
    )
    verifier = GoogleIdTokenVerifier(
        allowed_audiences=audiences,
        jwks_fetcher=fetcher,
        cache_seconds=3600,
    )
    repository = InMemoryAccountRepository()
    revocations = InMemorySessionRevocationStore()

    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_google_verifier] = lambda: verifier
    if database_url is None:
        app.dependency_overrides[get_account_repository] = lambda: repository
        app.dependency_overrides[get_session_revocations] = lambda: revocations
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
    assert sorted(body["requiredConsents"]) == ["sensitiveData", "serviceData"]
    assert sorted(body["optionalConsents"]) == [
        "photoAnalysis",
        "pushNotification",
        "serviceImprovement",
    ]
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


def test_refusing_push_notification_consent_still_creates_an_account() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents={**ALL_GRANTED, "pushNotification": False},
    )

    assert response.status_code == 200
    push = response.json()["account"]["consent"]["pushNotification"]
    assert push == {"granted": False, "grantedAt": None}


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


def _counting_verifier(
    documents: list[dict[str, Any]],
    *,
    clock: dict[str, float] | None = None,
    delay: float = 0.0,
) -> tuple[GoogleIdTokenVerifier, dict[str, int]]:
    """호출마다 다음 JWKS 문서를 돌려주며 호출 횟수를 센다.

    키 교체처럼 문서가 요청마다 달라지는 상황과, 조회 횟수 자체(중복 refresh 여부)를
    같이 검증하기 위한 헬퍼다. `clock` 을 주면 검증기는 `clock["now"]` 를 현재 시각으로
    쓴다. `delay` 는 조회 한 번이 걸리는 시간이다.
    """
    calls = {"count": 0}
    queue = iter(documents)

    async def fetcher() -> dict[str, Any]:
        calls["count"] += 1
        if delay:
            await asyncio.sleep(delay)
        return next(queue)

    options: dict[str, Any] = {}
    if clock is not None:
        options["clock"] = lambda: clock["now"]
    verifier = GoogleIdTokenVerifier(
        allowed_audiences=(google_tokens.CLIENT_ID,),
        jwks_fetcher=fetcher,
        cache_seconds=3600,
        **options,
    )
    return verifier, calls


def _error_codes_of(results: list[Any]) -> list[str | None]:
    return [
        result.error_code if isinstance(result, AppError) else None
        for result in results
    ]


def test_cached_kid_does_not_trigger_a_refresh() -> None:
    verifier, calls = _counting_verifier([google_tokens.jwks_document()])
    token = google_tokens.id_token()

    asyncio.run(verifier.verify(token))
    asyncio.run(verifier.verify(token))

    assert calls["count"] == 1


def test_unknown_kid_refreshes_the_key_set_at_most_once() -> None:
    verifier, calls = _counting_verifier([google_tokens.jwks_document()])
    token = google_tokens.id_token(key_id="unknown-key-id")

    with pytest.raises(AppError) as excinfo:
        asyncio.run(verifier.verify(token))

    assert excinfo.value.error_code == "INVALID_ID_TOKEN"
    assert calls["count"] == 1


def test_key_found_after_a_single_refresh_verifies_normally() -> None:
    # 캐시를 kid 가 없는 문서(키 교체 이전 상태)로 미리 채워두면, 토큰의 kid 는
    # refresh 를 한 번 거쳐야 발견되는 상황이 된다. 모르는 kid 로 다시 받는 최소 간격이
    # 지난 뒤라면 키 교체를 따라간다.
    clock = {"now": 1000.0}
    verifier, calls = _counting_verifier(
        [google_tokens.stale_jwks_document(), google_tokens.jwks_document()],
        clock=clock,
    )
    asyncio.run(verifier._refresh())
    clock["now"] += UNKNOWN_KEY_REFRESH_SECONDS
    token = google_tokens.id_token()

    identity = asyncio.run(verifier.verify(token))

    assert identity.subject == "google-sub-0001"
    assert calls["count"] == 2


def test_concurrent_unknown_kids_share_a_single_refresh() -> None:
    # 서명하지 않은 토큰으로도 kid 는 마음대로 바꿀 수 있다. 동시에 몰려도 한 번만 받는다.
    verifier, calls = _counting_verifier(
        [google_tokens.jwks_document()] * 10, delay=0.02
    )
    tokens = [google_tokens.id_token(key_id=f"unknown-{index}") for index in range(10)]

    async def verify_all() -> list[Any]:
        return await asyncio.gather(
            *(verifier.verify(token) for token in tokens), return_exceptions=True
        )

    results = asyncio.run(verify_all())

    assert _error_codes_of(results) == ["INVALID_ID_TOKEN"] * 10
    assert calls["count"] == 1


def test_concurrent_logins_on_a_cold_cache_share_a_single_refresh() -> None:
    verifier, calls = _counting_verifier(
        [google_tokens.jwks_document()] * 5, delay=0.02
    )
    token = google_tokens.id_token()

    async def verify_all() -> list[Any]:
        return await asyncio.gather(*(verifier.verify(token) for _ in range(5)))

    identities = asyncio.run(verify_all())

    assert [identity.subject for identity in identities] == ["google-sub-0001"] * 5
    assert calls["count"] == 1


def test_unknown_kids_refresh_at_most_once_per_interval() -> None:
    clock = {"now": 1000.0}
    verifier, calls = _counting_verifier(
        [google_tokens.jwks_document()] * 3, clock=clock
    )
    asyncio.run(verifier.verify(google_tokens.id_token()))
    assert calls["count"] == 1

    def unknown(index: int) -> str | None:
        try:
            asyncio.run(verifier.verify(google_tokens.id_token(key_id=f"x-{index}")))
        except AppError as error:
            return error.error_code
        return None

    # 방금 받은 키 묶음에 없는 kid 는 간격 안에서 몇 번이 와도 다시 받지 않는다.
    within = [unknown(index) for index in range(20)]
    clock["now"] += UNKNOWN_KEY_REFRESH_SECONDS - 1
    within.append(unknown(20))
    assert within == ["INVALID_ID_TOKEN"] * 21
    assert calls["count"] == 1

    # 간격이 지나면 한 번만 다시 받고, 그 뒤 간격 안에서는 다시 받지 않는다.
    clock["now"] += 1
    after = [unknown(index) for index in range(21, 31)]
    assert after == ["INVALID_ID_TOKEN"] * 10
    assert calls["count"] == 2

    # 이미 알고 있는 kid 의 정상 토큰은 그동안에도 그대로 통과한다.
    assert asyncio.run(verifier.verify(google_tokens.id_token())).subject == (
        "google-sub-0001"
    )
    assert calls["count"] == 2


def test_failed_refresh_is_shared_and_not_retried_within_the_interval() -> None:
    clock = {"now": 1000.0}
    state = {"calls": 0, "failing": False}

    async def fetcher() -> dict[str, Any]:
        state["calls"] += 1
        if state["failing"]:
            await asyncio.sleep(0.02)
            raise RuntimeError("jwks unavailable")
        return google_tokens.jwks_document()

    verifier = GoogleIdTokenVerifier(
        allowed_audiences=(google_tokens.CLIENT_ID,),
        jwks_fetcher=fetcher,
        cache_seconds=3600,
        clock=lambda: clock["now"],
    )
    asyncio.run(verifier.verify(google_tokens.id_token()))
    # 이후 조회는 모두 실패한다. 캐시는 아직 유효하다.
    state["failing"] = True
    clock["now"] += UNKNOWN_KEY_REFRESH_SECONDS
    tokens = [google_tokens.id_token(key_id=f"x-{index}") for index in range(5)]

    async def verify_all() -> list[Any]:
        return await asyncio.gather(
            *(verifier.verify(token) for token in tokens), return_exceptions=True
        )

    concurrent = asyncio.run(verify_all())
    with pytest.raises(AppError) as again:
        asyncio.run(verifier.verify(google_tokens.id_token(key_id="x-again")))

    # 동시에 온 요청은 실패한 한 번의 조회 결과를 같이 받고, 간격 안에서는 다시 받지 않는다.
    assert _error_codes_of(concurrent) == ["IDENTITY_PROVIDER_UNAVAILABLE"] * 5
    assert again.value.error_code == "IDENTITY_PROVIDER_UNAVAILABLE"
    assert state["calls"] == 2
    # 캐시에 있는 kid 는 조회 실패와 상관없이 통과한다.
    assert asyncio.run(verifier.verify(google_tokens.id_token())).subject == (
        "google-sub-0001"
    )


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


def test_display_name_longer_than_fifty_characters_is_rejected() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.consent(
        registrationToken=login.json()["registrationToken"],
        consentVersion=CONSENT_VERSION,
        consents=ALL_GRANTED,
        displayName="가" * 51,
    )

    assert response.status_code == 422
    assert response.json()["errorCode"] == "INVALID_REQUEST"
    assert harness.stored_account() is None


def test_postgres_account_survives_the_whole_login_flow(
    migrated_database_url: str,
) -> None:
    harness = _harness(database_url=migrated_database_url)
    token = google_tokens.id_token(email="tester@example.com")

    registered = _register(harness, token).json()
    me = harness.me(registered["accessToken"])
    again = harness.login(token).json()
    deleted = harness.delete_me(registered["accessToken"])
    after = harness.login(token).json()

    account = registered["account"]
    assert account["email"] is None
    assert account["consent"]["serviceData"]["granted"] is True
    assert me.status_code == 200
    assert me.json() == account
    assert again["status"] == "authenticated"
    assert again["account"]["accountId"] == account["accountId"]
    assert deleted.status_code == 204
    assert after["status"] == "consentRequired"


def test_logged_out_session_stays_revoked_after_a_restart(
    migrated_database_url: str,
) -> None:
    harness = _harness(database_url=migrated_database_url)
    revoked = _register(harness).json()["accessToken"]
    kept = harness.login(google_tokens.id_token()).json()["accessToken"]
    assert harness.logout(revoked).status_code == 204

    # 서버를 다시 띄운 것처럼 앱과 의존성을 새로 만든다. 같은 DB 만 이어서 쓴다.
    restarted = _harness(database_url=migrated_database_url)
    after = restarted.me(revoked)

    assert after.status_code == 401
    assert after.json()["errorCode"] == "UNAUTHENTICATED"
    assert restarted.me(kept).status_code == 200


def test_responses_do_not_expose_the_google_subject() -> None:
    harness = _harness()
    token = google_tokens.id_token(subject="google-sub-0001")

    registered = _register(harness, token)

    assert "google-sub-0001" not in registered.text
    assert "socialId" not in registered.text
    assert "idToken" not in registered.text


def test_logout_revokes_the_session_before_it_expires() -> None:
    harness = _harness()
    session = _register(harness).json()["accessToken"]
    assert harness.me(session).status_code == 200

    response = harness.logout(session)

    assert response.status_code == 204
    assert response.content == b""
    after = harness.me(session)
    assert after.status_code == 401
    assert after.json()["errorCode"] == "UNAUTHENTICATED"


def test_logout_does_not_end_other_sessions() -> None:
    harness = _harness()
    first = _register(harness).json()["accessToken"]
    second = harness.login(google_tokens.id_token()).json()["accessToken"]

    assert harness.logout(first).status_code == 204

    assert harness.me(second).status_code == 200


def test_logout_without_a_live_session_is_rejected() -> None:
    harness = _harness()
    session = _register(harness).json()["accessToken"]
    assert harness.logout(session).status_code == 204

    missing = request(harness.app, "POST", "/auth/logout")
    again = harness.logout(session)

    assert missing.status_code == 401
    assert missing.json()["errorCode"] == "UNAUTHENTICATED"
    assert again.status_code == 401
    assert again.json()["errorCode"] == "UNAUTHENTICATED"


def test_registration_token_cannot_log_out() -> None:
    harness = _harness()
    login = harness.login(google_tokens.id_token())

    response = harness.logout(login.json()["registrationToken"])

    assert response.status_code == 401
    assert response.json()["errorCode"] == "UNAUTHENTICATED"


def test_session_without_a_token_id_is_rejected() -> None:
    # 폐기했는지 확인할 수 없는 세션은 받지 않는다.
    harness = _harness()
    account_id = _register(harness).json()["account"]["accountId"]
    issued_at = datetime.now(UTC)
    token = jwt.encode(
        {
            "sub": account_id,
            "typ": "session",
            "iss": Settings(_env_file=None).service_name,
            "iat": issued_at,
            "exp": issued_at + timedelta(hours=1),
        },
        SESSION_SECRET,
        algorithm="HS256",
    )

    response = harness.me(token)

    assert response.status_code == 401
    assert response.json()["errorCode"] == "UNAUTHENTICATED"


def test_deleting_the_account_removes_it_with_its_consents() -> None:
    harness = _harness()
    session = _register(harness).json()["accessToken"]

    response = harness.delete_me(session)

    assert response.status_code == 204
    assert response.content == b""
    assert harness.stored_account() is None
    after = harness.me(session)
    assert after.status_code == 401, "탈퇴에 쓴 세션도 함께 폐기한다"


def test_deleted_account_is_not_restored_by_logging_in_again() -> None:
    harness = _harness()
    session = _register(harness).json()["accessToken"]
    assert harness.delete_me(session).status_code == 204

    login = harness.login(google_tokens.id_token())

    assert login.status_code == 200
    body = login.json()
    assert body["status"] == "consentRequired", "지운 계정으로 바로 로그인되지 않는다"
    assert "accessToken" not in body
    assert harness.stored_account() is None


def test_other_sessions_of_a_deleted_account_find_no_account() -> None:
    harness = _harness()
    first = _register(harness).json()["accessToken"]
    second = harness.login(google_tokens.id_token()).json()["accessToken"]
    assert harness.delete_me(first).status_code == 204

    read = harness.me(second)
    delete_again = harness.delete_me(second)

    assert read.status_code == 404
    assert read.json()["errorCode"] == "ACCOUNT_NOT_FOUND"
    assert delete_again.status_code == 404
    assert delete_again.json()["errorCode"] == "ACCOUNT_NOT_FOUND"


def test_deleting_only_removes_the_requesting_account() -> None:
    harness = _harness()
    mine = _register(harness).json()["accessToken"]
    other = _register(
        harness, google_tokens.id_token(subject="google-sub-0002")
    ).json()["accessToken"]

    assert harness.delete_me(mine).status_code == 204

    assert harness.stored_account() is None
    assert harness.stored_account("google-sub-0002") is not None
    assert harness.me(other).status_code == 200


def test_deleting_without_a_session_is_rejected() -> None:
    harness = _harness()
    _register(harness)

    response = request(harness.app, "DELETE", "/auth/me")

    assert response.status_code == 401
    assert response.json()["errorCode"] == "UNAUTHENTICATED"
    assert harness.stored_account() is not None


def test_revocation_list_forgets_sessions_once_they_expire() -> None:
    now = datetime(2026, 10, 1, 9, tzinfo=UTC)
    clock = {"now": now}
    store = InMemorySessionRevocationStore(clock=lambda: clock["now"])

    asyncio.run(
        store.revoke(
            SessionClaims(
                account_id="acc-1",
                token_id="old",
                expires_at=now + timedelta(minutes=5),
            )
        )
    )
    assert asyncio.run(store.is_revoked("old")) is True

    clock["now"] = now + timedelta(minutes=10)
    asyncio.run(
        store.revoke(
            SessionClaims(
                account_id="acc-2",
                token_id="new",
                expires_at=clock["now"] + timedelta(hours=1),
            )
        )
    )

    # 만료된 세션은 서명 확인에서 이미 거절되므로 목록에 남기지 않는다.
    assert len(store) == 1
    assert asyncio.run(store.is_revoked("new")) is True
