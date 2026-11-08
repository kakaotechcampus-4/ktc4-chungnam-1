"""요청 본문 크기 상한과 업로드 경로의 본문 읽기 전 인증 확인.

FastAPI는 라우트의 의존성(앱 버전, 인증, 소유권, 파일 크기 검사)을 풀기 전에 multipart와
JSON 본문을 끝까지 읽는다. 상한이 없으면 로그인하지 않은 요청도 큰 본문을 API의 메모리와
임시 파일에 다 쓴 뒤에야 거절된다. 이 미들웨어는 FastAPI가 본문을 읽기 전에 돌며 다음
순서로 확인한다.

1. 경로별 상한을 정한다. 업로드 네 경로는 그 경로의 파일 상한에 1 MiB(multipart 경계와
   다른 필드 몫)를 더하고, 나머지 경로는 1 MiB다.
2. 업로드 경로는 본문을 읽기 전에 앱 버전(426)과 세션 토큰의 서명과 만료(401)를 확인한다.
   폐기 여부와 계정 확인은 지금처럼 `get_current_session`, `get_current_account`가 한다.
3. `Content-Length`가 상한을 넘으면 본문을 읽지 않고 413으로 거절한다.
4. 길이를 밝히지 않았거나(chunked) 밝힌 길이보다 더 보내면, 읽은 양을 세다가 상한을 넘는
   순간 413으로 끊는다.
"""

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.api.deps import (
    APP_VERSION_CODE_HEADER,
    bearer_scheme,
    get_current_account,
    get_current_session,
    get_token_issuer,
    read_signed_session,
    require_supported_app_version,
)
from app.core.config import Settings, get_settings
from app.core.errors import (
    AppError,
    RequestBodyTooLarge,
    app_error_handler,
    request_body_too_large_handler,
)
from app.services.speech_transcription import MAX_BYTES as SHORT_AUDIO_MAX_BYTES

MIB = 1024 * 1024
# 업로드가 아닌 요청(JSON)의 상한. 가장 큰 JSON 요청도 수 KB 수준이다.
DEFAULT_BODY_LIMIT = MIB
# multipart 경계, 파트 헤더와 파일이 아닌 필드(participantCount 등)의 여유.
MULTIPART_ALLOWANCE = MIB


@dataclass(frozen=True)
class TooLarge:
    error_code: str
    message: str

    def error(self) -> RequestBodyTooLarge:
        return RequestBodyTooLarge(error_code=self.error_code, message=self.message)


# 업로드 경로는 라우트의 파일 크기 검사와 같은 오류 코드와 문구를 쓴다. 앱이 이미 구분하는 값이다.
IMAGE_TOO_LARGE = TooLarge("IMAGE_TOO_LARGE", "사진 파일이 허용된 크기를 초과했습니다.")
AUDIO_TOO_LARGE = TooLarge("AUDIO_TOO_LARGE", "음성 파일이 허용된 크기를 초과했습니다.")
REQUEST_TOO_LARGE = TooLarge("REQUEST_TOO_LARGE", "요청 본문이 허용된 크기를 초과했습니다.")


@dataclass(frozen=True)
class UploadRoute:
    pattern: re.Pattern[str]
    # 라우트가 파일에 적용하는 상한. 라우트와 같은 설정값과 상수에서 읽는다.
    file_limit: Callable[[Settings], int]
    too_large: TooLarge

    def body_limit(self, settings: Settings) -> int:
        return self.file_limit(settings) + MULTIPART_ALLOWANCE


UPLOAD_ROUTES = (
    # 3-1 프로필 사진
    UploadRoute(
        re.compile(r"/api/v1/profiles/[^/]+/photos"),
        lambda settings: settings.max_image_bytes,
        IMAGE_TOO_LARGE,
    ),
    # 5-2 면회 사진
    UploadRoute(
        re.compile(r"/api/v1/visit-sessions/[^/]+/photo"),
        lambda settings: settings.max_image_bytes,
        IMAGE_TOO_LARGE,
    ),
    # 6-2 면회 음성
    UploadRoute(
        re.compile(r"/api/v1/visit-sessions/[^/]+/speech-analyses"),
        lambda settings: settings.max_audio_bytes,
        AUDIO_TOO_LARGE,
    ),
    # 6-6 프로필 입력용 짧은 음성. speech_transcription.py와 같은 상한이다.
    UploadRoute(
        re.compile(r"/api/v1/speech-transcriptions"),
        lambda settings: min(settings.max_audio_bytes, SHORT_AUDIO_MAX_BYTES),
        AUDIO_TOO_LARGE,
    ),
)


def find_upload_route(method: str, path: str) -> UploadRoute | None:
    if method != "POST":
        return None
    for route in UPLOAD_ROUTES:
        if route.pattern.fullmatch(path):
            return route
    return None


class RequestBodyLimit:
    """FastAPI가 본문을 읽기 전에 경로별 상한과 업로드 경로의 세션 서명을 확인한다."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request = Request(scope)
        upload = find_upload_route(scope["method"], scope["path"])
        limit, too_large = DEFAULT_BODY_LIMIT, REQUEST_TOO_LARGE
        try:
            if upload is not None:
                overrides = _dependency_overrides(scope)
                settings = overrides.get(get_settings, get_settings)()
                await _check_before_body(request, settings, overrides)
                limit, too_large = upload.body_limit(settings), upload.too_large
            declared = _content_length(request)
            if declared is not None and declared > limit:
                raise too_large.error()
        except AppError as exc:
            response = await app_error_handler(request, exc)
            await response(scope, receive, send)
            return
        except RequestBodyTooLarge as exc:
            response = await request_body_too_large_handler(request, exc)
            await response(scope, receive, send)
            return

        received = 0

        async def receive_within_limit() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    # 라우트 안에서 본문을 읽다 나므로 FastAPI의 예외 처리기가 413으로 바꾼다.
                    raise too_large.error()
            return message

        await self.app(scope, receive_within_limit, send)


async def _check_before_body(
    request: Request, settings: Settings, overrides: Mapping[Any, Any]
) -> None:
    # 라우터 의존성과 같은 순서다. 앱 버전을 인증보다 먼저 본다.
    require_supported_app_version(settings, request.headers.get(APP_VERSION_CODE_HEADER))
    # 테스트가 인증 의존성을 바꿔 끼운 앱은 라우트도 토큰을 보지 않는다. 같은 기준으로
    # 건너뛴다. 운영 앱은 dependency_overrides를 쓰지 않는다.
    if get_current_session in overrides or get_current_account in overrides:
        return
    read_signed_session(await bearer_scheme(request), get_token_issuer(settings))


def _dependency_overrides(scope: Scope) -> Mapping[Any, Any]:
    # 테스트는 설정을 dependency_overrides로 바꾼다. 라우트와 같은 설정을 보도록 따른다.
    return getattr(scope.get("app"), "dependency_overrides", None) or {}


_CONTENT_LENGTH_PATTERN = re.compile(r"[0-9]{1,20}")


def _content_length(request: Request) -> int | None:
    # 형식이 다른 값은 믿지 않고 실제로 읽은 양만 센다.
    value = request.headers.get("content-length")
    if value is None or not _CONTENT_LENGTH_PATTERN.fullmatch(value):
        return None
    return int(value)
