from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.schemas.common import ErrorResponse

ExceptionHandler = Callable[[Request, Exception], Awaitable[JSONResponse]]


class AppError(Exception):
    def __init__(
        self,
        *,
        status_code: int,
        error_code: str,
        message: str,
        retryable: bool = False,
    ) -> None:
        super().__init__(error_code)
        self.status_code = status_code
        self.error_code = error_code
        self.message = message
        self.retryable = retryable


class RequestBodyTooLarge(StarletteHTTPException):
    """요청 본문이 경로별 상한(app/api/body_limits.py)을 넘었다.

    FastAPI는 본문을 읽다 난 예외 중 HTTPException만 그대로 올리고 나머지는 400으로
    바꾼다. 그래서 AppError가 아니라 HTTPException을 이어받고, 아래 처리기에서 공통
    오류 형식으로 바꾼다.
    """

    def __init__(self, *, error_code: str, message: str) -> None:
        super().__init__(status_code=413)
        self.error_code = error_code
        self.message = message


def _error_response(
    request: Request,
    *,
    status_code: int,
    error_code: str,
    message: str,
    retryable: bool = False,
) -> JSONResponse:
    body = ErrorResponse(
        error_code=error_code,
        message=message,
        request_id=getattr(request.state, "request_id", None),
        retryable=retryable,
    )
    return JSONResponse(
        status_code=status_code,
        content=body.model_dump(by_alias=True),
    )


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return _error_response(
        request,
        status_code=exc.status_code,
        error_code=exc.error_code,
        message=exc.message,
        retryable=exc.retryable,
    )


async def request_body_too_large_handler(
    request: Request, exc: RequestBodyTooLarge
) -> JSONResponse:
    return _error_response(
        request,
        status_code=413,
        error_code=exc.error_code,
        message=exc.message,
    )


async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    del exc
    return _error_response(
        request,
        status_code=422,
        error_code="INVALID_REQUEST",
        message="요청 형식이 올바르지 않습니다.",
    )


async def http_error_handler(
    request: Request, exc: StarletteHTTPException
) -> JSONResponse:
    error_code = "NOT_FOUND" if exc.status_code == 404 else "HTTP_ERROR"
    message = (
        "요청한 경로를 찾을 수 없습니다."
        if exc.status_code == 404
        else "요청을 처리할 수 없습니다."
    )
    return _error_response(
        request,
        status_code=exc.status_code,
        error_code=error_code,
        message=message,
    )


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    del exc
    return _error_response(
        request,
        status_code=500,
        error_code="INTERNAL_SERVER_ERROR",
        message="서버에서 요청을 처리하지 못했습니다.",
        retryable=True,
    )


def register_exception_handlers(application: FastAPI) -> None:
    application.add_exception_handler(AppError, app_error_handler)
    application.add_exception_handler(RequestBodyTooLarge, request_body_too_large_handler)
    application.add_exception_handler(RequestValidationError, validation_error_handler)
    application.add_exception_handler(StarletteHTTPException, http_error_handler)
    application.add_exception_handler(Exception, unhandled_error_handler)
