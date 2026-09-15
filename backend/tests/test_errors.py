import logging

from fastapi import FastAPI
from pydantic import BaseModel

from app.core.errors import AppError, register_exception_handlers
from app.core.logging import SafeJsonFormatter, install_request_logging
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


def test_unhandled_exception_correlates_body_header_and_log(caplog) -> None:
    application = _test_app()

    @application.get("/boom/{item_id}")
    async def boom(item_id: str) -> None:
        raise RuntimeError(f"synthetic failure for {item_id} and sensitive-body-value")

    caplog.set_level(logging.INFO, logger="saerok.http")
    response = request(
        application,
        "GET",
        "/boom/sensitive-path-value?token=sensitive-query-value",
        raise_app_exceptions=False,
    )

    assert response.status_code == 500
    body = response.json()
    assert body["errorCode"] == "INTERNAL_SERVER_ERROR"
    assert body["retryable"] is True
    request_id = body["requestId"]
    assert request_id
    assert response.headers["X-Request-ID"] == request_id

    records = [record for record in caplog.records if record.name == "saerok.http"]
    assert len(records) == 1

    formatted = SafeJsonFormatter().format(records[0])
    assert f'"request_id": "{request_id}"' in formatted
    assert '"status_code": 500' in formatted
    assert '"route": "/boom/{item_id}"' in formatted
    assert "sensitive-path-value" not in formatted
    assert "sensitive-query-value" not in formatted
    assert "synthetic failure" not in formatted


def test_unhandled_exception_preserves_caller_supplied_request_id() -> None:
    application = _test_app()

    @application.get("/boom")
    async def boom() -> None:
        raise RuntimeError("synthetic failure")

    response = request(
        application,
        "GET",
        "/boom",
        headers={"X-Request-ID": "caller-supplied-id"},
        raise_app_exceptions=False,
    )

    assert response.status_code == 500
    assert response.json()["requestId"] == "caller-supplied-id"
    assert response.headers["X-Request-ID"] == "caller-supplied-id"


def test_unhandled_exception_ignores_disallowed_request_id_format() -> None:
    application = _test_app()

    @application.get("/boom")
    async def boom() -> None:
        raise RuntimeError("synthetic failure")

    response = request(
        application,
        "GET",
        "/boom",
        headers={"X-Request-ID": "not a valid id!"},
        raise_app_exceptions=False,
    )

    assert response.status_code == 500
    generated_id = response.json()["requestId"]
    assert generated_id != "not a valid id!"
    assert response.headers["X-Request-ID"] == generated_id


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
