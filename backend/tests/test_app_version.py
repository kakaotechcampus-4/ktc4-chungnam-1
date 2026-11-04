"""최소 지원 앱 버전보다 낮은 요청을 426 으로 거절하는지 확인한다.

앱은 요청마다 `X-App-Version-Code` 에 안드로이드 versionCode 를 싣는다. 값은 모두
합성 데이터다.
"""

from collections.abc import Iterator

import pytest
from fastapi import APIRouter, Depends, FastAPI

from app.api.deps import APP_VERSION_CODE_HEADER, require_supported_app_version
from app.core.config import Settings, get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import install_request_logging
from app.main import app as main_app
from tests.support import request


def _settings(minimum: int) -> Settings:
    return Settings(_env_file=None, min_android_version_code=minimum)


def _test_app(minimum: int) -> FastAPI:
    application = FastAPI()
    register_exception_handlers(application)
    install_request_logging(application)
    router = APIRouter(dependencies=[Depends(require_supported_app_version)])

    @router.get("/ping")
    async def ping() -> dict[str, str]:
        return {"status": "ok"}

    application.include_router(router)
    application.dependency_overrides[get_settings] = lambda: _settings(minimum)
    return application


def _ping(minimum: int, version_code: str | None):
    headers = {} if version_code is None else {APP_VERSION_CODE_HEADER: version_code}
    return request(_test_app(minimum), "GET", "/ping", headers=headers)


def test_rejects_app_below_minimum_with_common_error() -> None:
    response = _ping(5, "4")

    assert response.status_code == 426
    assert response.json() == {
        "schemaVersion": 1,
        "errorCode": "APP_UPDATE_REQUIRED",
        "message": "새 버전으로 업데이트해야 합니다.",
        "requestId": response.headers["X-Request-ID"],
        "retryable": False,
    }


@pytest.mark.parametrize("version_code", ["5", "6", "2100000000"])
def test_allows_app_at_or_above_minimum(version_code: str) -> None:
    assert _ping(5, version_code).status_code == 200


@pytest.mark.parametrize("version_code", [None, "", "abc", "4.1", "-1", " 4"])
def test_allows_request_without_readable_version(version_code: str | None) -> None:
    # 헤더를 싣기 전에 낸 앱 빌드와 점검 도구를 막지 않는다.
    assert _ping(5, version_code).status_code == 200


def test_ignores_non_ascii_digits() -> None:
    # HTTP 클라이언트로는 보낼 수 없는 값이라 의존성을 직접 부른다. `int("٤")` 는
    # 4 가 되지만 versionCode 로 읽지 않는다.
    require_supported_app_version(_settings(5), "٤")


def test_does_not_check_when_minimum_is_zero() -> None:
    assert _ping(0, "1").status_code == 200


def test_minimum_is_disabled_by_default() -> None:
    assert Settings(_env_file=None).min_android_version_code == 0


@pytest.fixture
def main_app_requiring_version_5() -> Iterator[FastAPI]:
    main_app.dependency_overrides[get_settings] = lambda: _settings(5)
    try:
        yield main_app
    finally:
        main_app.dependency_overrides.pop(get_settings, None)


def test_app_routes_reject_old_app_before_authentication(
    main_app_requiring_version_5: FastAPI,
) -> None:
    # 세션도 DB 도 없지만, 버전 확인이 먼저라 401 이나 503 이 아니라 426 이다.
    response = request(
        main_app_requiring_version_5,
        "GET",
        "/auth/me",
        headers={APP_VERSION_CODE_HEADER: "4"},
    )

    assert response.status_code == 426
    assert response.json()["errorCode"] == "APP_UPDATE_REQUIRED"


def test_login_rejects_old_app(main_app_requiring_version_5: FastAPI) -> None:
    response = request(
        main_app_requiring_version_5,
        "POST",
        "/auth/google",
        json={"idToken": "synthetic-token"},
        headers={APP_VERSION_CODE_HEADER: "4"},
    )

    assert response.status_code == 426


def test_health_answers_regardless_of_app_version(
    main_app_requiring_version_5: FastAPI,
) -> None:
    response = request(
        main_app_requiring_version_5,
        "GET",
        "/health/live",
        headers={APP_VERSION_CODE_HEADER: "1"},
    )

    assert response.status_code == 200
