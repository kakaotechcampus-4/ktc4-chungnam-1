import logging
import sys
import traceback

from fastapi import FastAPI
from pydantic import BaseModel

from app.core.errors import AppError, register_exception_handlers
from app.core.logging import (
    SafeJsonFormatter,
    _format_traceback_without_message,
    install_request_logging,
)
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


def _boom_records(caplog, application: FastAPI, path: str) -> tuple[dict, list]:
    caplog.set_level(logging.INFO, logger="saerok.http")
    response = request(application, "GET", path, raise_app_exceptions=False)
    records = [record for record in caplog.records if record.name == "saerok.http"]
    return response, records


def test_unhandled_exception_correlates_body_header_and_log(caplog) -> None:
    # 경로값과 쿼리값을 그대로 exception 메시지에 넣는 "최악의 경우"를
    # 가정한다. 그래도 로그에 노출되지 않아야 한다.
    application = _test_app()

    @application.get("/boom/{item_id}")
    async def boom(item_id: str, token: str) -> None:
        raise RuntimeError(f"synthetic failure for {item_id} with token {token}")

    response, records = _boom_records(
        caplog,
        application,
        "/boom/sensitive-path-value?token=sensitive-query-value",
    )

    assert response.status_code == 500
    body = response.json()
    assert body["errorCode"] == "INTERNAL_SERVER_ERROR"
    assert body["retryable"] is True
    request_id = body["requestId"]
    assert request_id
    assert response.headers["X-Request-ID"] == request_id

    # 500 하나당 exception 로그(server_exception) 1건과 완료 로그
    # (request_completed) 1건, 총 2건만 남아야 하며 traceback이 중복
    # 기록되지 않는다.
    assert len(records) == 2
    exception_record, completed_record = records
    assert exception_record.msg == "server_exception"
    assert completed_record.msg == "request_completed"

    exception_formatted = SafeJsonFormatter().format(exception_record)
    completed_formatted = SafeJsonFormatter().format(completed_record)

    for formatted in (exception_formatted, completed_formatted):
        assert f'"request_id": "{request_id}"' in formatted
        assert "sensitive-path-value" not in formatted
        assert "sensitive-query-value" not in formatted

    assert '"status_code": 500' in completed_formatted
    assert '"route": "/boom/{item_id}"' in completed_formatted
    assert '"exception_type": "RuntimeError"' in exception_formatted
    assert "Traceback (most recent call last):" in exception_formatted
    assert "logging.py" in exception_formatted


def test_unhandled_exception_does_not_log_request_body(caplog) -> None:
    # request body는 어디에서도 직접 읽지 않지만, endpoint가 body 값을
    # exception 메시지에 그대로 넣는 최악의 경우까지 가정해 검증한다.
    application = _test_app()

    class BoomBody(BaseModel):
        secret: str

    @application.post("/boom-body")
    async def boom_body(payload: BoomBody) -> None:
        raise RuntimeError(f"synthetic failure with body value {payload.secret}")

    caplog.set_level(logging.INFO, logger="saerok.http")
    response = request(
        application,
        "POST",
        "/boom-body",
        json={"secret": "SYNTHETIC_BODY_SECRET_12345"},
        raise_app_exceptions=False,
    )

    assert response.status_code == 500
    records = [record for record in caplog.records if record.name == "saerok.http"]
    assert len(records) == 2
    for record in records:
        assert "SYNTHETIC_BODY_SECRET_12345" not in SafeJsonFormatter().format(record)


def test_exception_message_is_stripped_from_traceback_but_type_and_frames_remain() -> (
    None
):
    # Test 6: 표준 traceback은 예외 메시지를 마지막 줄에 그대로 포함하므로,
    # 메시지에 민감한 값이 들어가면 표준 traceback을 그대로 기록해선 안 된다.
    # 이 트레이드오프를 확인 후 예외 메시지를 제거하고 타입과 스택 프레임만
    # 남기기로 결정했다. 이 테스트는 그 결정을 고정한다.
    # 소스 코드 줄 자체에 비밀 문자열을 적어두면 traceback의 소스 라인 표시로
    # 인해 (메시지와 무관하게) 그대로 드러난다. 그 효과를 배제하기 위해
    # 변수를 거쳐 예외 메시지를 만든다.
    secret_holder = "SYNTHETIC_EXCEPTION_MESSAGE_SECRET"
    try:
        raise ValueError(secret_holder)
    except ValueError:
        exc_info = sys.exc_info()
        raw_traceback = "".join(traceback.format_exception(*exc_info))
        sanitized_traceback = _format_traceback_without_message(exc_info)

    assert "SYNTHETIC_EXCEPTION_MESSAGE_SECRET" in raw_traceback
    assert "SYNTHETIC_EXCEPTION_MESSAGE_SECRET" not in sanitized_traceback
    assert "ValueError" in sanitized_traceback
    assert "test_errors.py" in sanitized_traceback


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
