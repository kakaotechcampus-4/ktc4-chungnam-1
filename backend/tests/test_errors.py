from fastapi import FastAPI
from pydantic import BaseModel

from app.core.errors import AppError, register_exception_handlers
from app.core.logging import install_request_logging
from tests.support import request


def _test_app() -> FastAPI:
    application = FastAPI()
    register_exception_handlers(application)
    install_request_logging(application)
    return application


def test_unknown_route_uses_common_error_response() -> None:
    response = request(_test_app(), "GET", "/missing")

    assert response.status_code == 404
    assert response.json() == {
        "schemaVersion": 1,
        "errorCode": "NOT_FOUND",
        "message": "요청한 경로를 찾을 수 없습니다.",
        "requestId": response.headers["X-Request-ID"],
        "retryable": False,
    }


def test_app_error_does_not_expose_internal_details() -> None:
    application = _test_app()

    @application.get("/failure")
    async def failure() -> None:
        raise AppError(
            status_code=503,
            error_code="SERVICE_UNAVAILABLE",
            message="처리 서비스를 사용할 수 없습니다.",
            retryable=True,
        )

    response = request(application, "GET", "/failure")

    assert response.status_code == 503
    assert response.json()["errorCode"] == "SERVICE_UNAVAILABLE"
    assert response.json()["retryable"] is True


def test_validation_error_does_not_echo_input() -> None:
    application = _test_app()

    class Input(BaseModel):
        count: int

    @application.post("/validate")
    async def validate(body: Input) -> None:
        del body

    response = request(
        application,
        "POST",
        "/validate",
        json={"count": "sensitive-test-value"},
    )

    assert response.status_code == 422
    assert response.json()["errorCode"] == "INVALID_REQUEST"
    assert "sensitive-test-value" not in response.text
