import json
import logging
import re
import traceback
from datetime import UTC, datetime
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request, Response

from app.core.errors import unhandled_error_handler

_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_STANDARD_LOG_FIELDS = frozenset(
    logging.LogRecord("", 0, "", 0, "", (), None).__dict__
)


def _format_traceback_without_message(
    exc_info: tuple[type[BaseException], BaseException, object],
) -> str:
    # 예외 메시지(`str(exc)`)는 애플리케이션 코드가 요청 관련 값을 문자열로
    # 넣었을 경우 그대로 로그에 노출될 수 있다. 발생 위치를 알 수 있는 스택
    # 프레임(파일, 라인, 함수, 코드 라인)만 남기고 마지막 "타입: 메시지" 줄은
    # 타입 이름만 남긴다.
    exc_type, exc_value, exc_tb = exc_info
    frames = "".join(traceback.format_tb(exc_tb))
    type_name = getattr(exc_type, "__name__", None) or type(exc_value).__name__
    return f"Traceback (most recent call last):\n{frames}{type_name}\n"


class SafeJsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "event": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in _STANDARD_LOG_FIELDS and key not in {"message", "asctime"}:
                payload[key] = value
        if record.exc_info:
            payload["traceback"] = _format_traceback_without_message(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging(log_level: str) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(SafeJsonFormatter())

    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(log_level)

    # Uvicorn 기본 접근 로그는 원래 경로와 쿼리 문자열을 출력한다. 애플리케이션의
    # 경로 템플릿 기반 로그만 남겨 사용자 입력이 로그에 포함될 가능성을 줄인다.
    logging.getLogger("uvicorn.access").disabled = True
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


def _request_id(request: Request) -> str:
    candidate = request.headers.get("X-Request-ID", "")
    if _REQUEST_ID_PATTERN.fullmatch(candidate):
        return candidate
    return uuid4().hex


def install_request_logging(application: FastAPI) -> None:
    logger = logging.getLogger("saerok.http")

    @application.middleware("http")
    async def request_logging(request: Request, call_next) -> Response:
        request_id = _request_id(request)
        request.state.request_id = request_id
        started_at = perf_counter()

        try:
            response = await call_next(request)
        except Exception as exc:
            # FastAPI가 등록한 일반 예외 처리기는 ServerErrorMiddleware로 옮겨져
            # 이 미들웨어보다 바깥쪽에서 실행된다. call_next가 예외를 그대로
            # 전파하면 아래의 헤더 부여와 완료 로그가 건너뛰어지므로, 여기서
            # 직접 같은 처리기를 호출해 응답을 만들고 로그 흐름을 보장한다.
            # 예외를 여기서 소비하면 ServerErrorMiddleware까지 전파되지 않아
            # (그곳에서의 재전파로 서버가 남기던) traceback도 함께 사라지므로,
            # 실제로 예외를 잡는 이 지점에서 한 번만 traceback을 남긴다.
            logger.exception(
                "server_exception",
                extra={
                    "request_id": request_id,
                    "exception_type": type(exc).__name__,
                },
            )
            response = await unhandled_error_handler(request, exc)
        response.headers["X-Request-ID"] = request_id

        route = request.scope.get("route")
        route_template = getattr(route, "path", "unmatched")
        logger.info(
            "request_completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "route": route_template,
                "status_code": response.status_code,
                "duration_ms": round((perf_counter() - started_at) * 1000, 2),
            },
        )
        return response
