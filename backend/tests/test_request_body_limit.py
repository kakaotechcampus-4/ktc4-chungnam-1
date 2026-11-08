"""요청 본문 크기 상한과 업로드 경로의 본문 읽기 전 인증 확인(app/api/body_limits.py).

본문을 조각으로 흘려보내는 ASGI 호출로 서버가 본문을 얼마나 가져갔는지 센다. 토큰, 사진과
음성은 모두 합성 값이다.
"""

import json
import wave
from collections.abc import Iterator
from io import BytesIO
from typing import Any

import pytest

from app.api.body_limits import (
    DEFAULT_BODY_LIMIT,
    MIB,
    find_upload_route,
)
from app.api.deps import get_image_storage, get_speech_audio_storage, get_token_issuer
from app.core.config import Settings, get_settings
from app.main import create_app
from app.services.session_tokens import TokenIssuer
from app.services.speech_transcription import MAX_BYTES as SHORT_AUDIO_MAX_BYTES
from tests.db_api import DbApi
from tests.support import run
from tests.test_profile_photos import JPEG, MemoryImageStorage
from tests.test_speech_analyses import FakeAiServer, FakeAudioStorage

SECRET = "body-limit-test-secret-value-32bytes"
ACCOUNT_ID = "00000000-0000-4000-8000-0000000000aa"
CHUNK = 64 * 1024
BOUNDARY = "synthetic-boundary"
SMALL_FILE_LIMIT = 64 * 1024

# (경로, multipart 필드, 상한을 넘었을 때의 오류 코드)
UPLOADS = [
    (
        "/api/v1/profiles/00000000-0000-4000-8000-000000000001/photos",
        "image",
        "IMAGE_TOO_LARGE",
    ),
    (
        "/api/v1/visit-sessions/00000000-0000-4000-8000-000000000201/photo",
        "image",
        "IMAGE_TOO_LARGE",
    ),
    (
        "/api/v1/visit-sessions/00000000-0000-4000-8000-000000000201/speech-analyses",
        "audio",
        "AUDIO_TOO_LARGE",
    ),
    ("/api/v1/speech-transcriptions", "audio", "AUDIO_TOO_LARGE"),
]
UPLOAD_IDS = ["profile-photo", "visit-photo", "visit-audio", "short-audio"]


def _settings(**overrides: Any) -> Settings:
    return Settings(_env_file=None, session_secret=SECRET, **overrides)


def _app(settings: Settings):
    application = create_app()
    application.dependency_overrides[get_settings] = lambda: settings
    return application


def _token(settings: Settings) -> str:
    return get_token_issuer(settings).issue_session(ACCOUNT_ID).value


class Body:
    """조각으로 흘려보낼 본문. 큰 본문도 메모리에 한 번에 만들지 않는다."""

    def __init__(self, head: bytes, size: int, tail: bytes = b"") -> None:
        self.head = head
        self.size = size
        self.tail = tail

    @property
    def length(self) -> int:
        return len(self.head) + self.size + len(self.tail)

    def chunks(self) -> Iterator[bytes]:
        yield self.head
        remaining = self.size
        while remaining > 0:
            piece = min(CHUNK, remaining)
            yield b"\0" * piece
            remaining -= piece
        if self.tail:
            yield self.tail


def _multipart(field: str, file_bytes: int) -> Body:
    head = (
        f"--{BOUNDARY}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="synthetic"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    return Body(head, file_bytes, f"\r\n--{BOUNDARY}--\r\n".encode())


def _json(size: int) -> Body:
    return Body(b'{"name": "', size, b'"}')


def _call(
    application,
    path: str,
    body: Body,
    *,
    content_type: str,
    declare_length: bool,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict[str, Any], dict[bytes, bytes], int]:
    """(상태, 오류 본문, 응답 헤더, 서버가 가져간 본문 바이트 수)."""

    async def scenario():
        pieces = body.chunks()
        consumed = 0
        finished = False

        async def receive() -> dict[str, Any]:
            nonlocal consumed, finished
            if finished:
                return {"type": "http.disconnect"}
            piece = next(pieces, None)
            if piece is None:
                finished = True
                return {"type": "http.request", "body": b"", "more_body": False}
            consumed += len(piece)
            return {"type": "http.request", "body": piece, "more_body": True}

        messages: list[dict[str, Any]] = []

        async def send(message: dict[str, Any]) -> None:
            messages.append(message)

        raw_headers = [(b"content-type", content_type.encode())]
        if declare_length:
            raw_headers.append((b"content-length", str(body.length).encode()))
        for name, value in (headers or {}).items():
            raw_headers.append((name.lower().encode(), value.encode()))
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "http",
            "path": path,
            "raw_path": path.encode(),
            "query_string": b"",
            "root_path": "",
            "headers": raw_headers,
            "client": ("testclient", 50000),
            "server": ("testserver", 80),
        }
        await application(scope, receive, send)
        start = next(m for m in messages if m["type"] == "http.response.start")
        content = b"".join(
            m.get("body", b"") for m in messages if m["type"] == "http.response.body"
        )
        return start["status"], json.loads(content), dict(start["headers"]), consumed

    return run(scenario())


def _upload(application, path, field, file_bytes, *, declare_length, headers=None):
    return _call(
        application,
        path,
        _multipart(field, file_bytes),
        content_type=f"multipart/form-data; boundary={BOUNDARY}",
        declare_length=declare_length,
        headers=headers,
    )


def _assert_error_envelope(body: dict[str, Any], headers: dict[bytes, bytes], code: str):
    assert body["errorCode"] == code
    assert body["schemaVersion"] == 1
    # 요청 로그 미들웨어가 바깥에 있어 여기서 거절해도 요청 ID가 붙는다.
    assert body["requestId"] and headers[b"x-request-id"] == body["requestId"].encode()


@pytest.mark.parametrize("declare_length", [True, False], ids=["content-length", "chunked"])
@pytest.mark.parametrize("path,field,_code", UPLOADS, ids=UPLOAD_IDS)
def test_upload_without_session_is_refused_before_reading_body(
    path, field, _code, declare_length
):
    status, body, headers, consumed = _upload(
        _app(_settings()), path, field, 64 * MIB, declare_length=declare_length
    )

    assert status == 401
    _assert_error_envelope(body, headers, "UNAUTHENTICATED")
    assert consumed == 0


def _expired_token(settings: Settings) -> str:
    return TokenIssuer(
        secret=SECRET,
        issuer=settings.service_name,
        session_ttl_seconds=-60,
        registration_ttl_seconds=600,
    ).issue_session(ACCOUNT_ID).value


def _forged_token(settings: Settings) -> str:
    return TokenIssuer(
        secret="another-secret-value-for-forged-token",
        issuer=settings.service_name,
        session_ttl_seconds=600,
        registration_ttl_seconds=600,
    ).issue_session(ACCOUNT_ID).value


def _registration_token(settings: Settings) -> str:
    return get_token_issuer(settings).issue_registration(
        provider="google", social_id="synthetic-sub"
    ).value


@pytest.mark.parametrize(
    "make_token,code",
    [
        (_forged_token, "UNAUTHENTICATED"),
        (_registration_token, "UNAUTHENTICATED"),
        (_expired_token, "SESSION_EXPIRED"),
    ],
    ids=["forged", "registration", "expired"],
)
def test_upload_with_unusable_session_is_refused_before_reading_body(make_token, code):
    settings = _settings()
    status, body, headers, consumed = _upload(
        _app(settings),
        "/api/v1/speech-transcriptions",
        "audio",
        12 * MIB,
        declare_length=True,
        headers={"Authorization": f"Bearer {make_token(settings)}"},
    )

    assert status == 401
    _assert_error_envelope(body, headers, code)
    assert consumed == 0


def test_old_app_is_refused_before_session_check_and_body():
    status, body, headers, consumed = _upload(
        _app(_settings(min_android_version_code=5)),
        "/api/v1/profiles/00000000-0000-4000-8000-000000000001/photos",
        "image",
        32 * MIB,
        declare_length=True,
        headers={"X-App-Version-Code": "3"},
    )

    assert status == 426
    _assert_error_envelope(body, headers, "APP_UPDATE_REQUIRED")
    assert consumed == 0


def _small_upload_settings() -> Settings:
    return _settings(max_image_bytes=SMALL_FILE_LIMIT, max_audio_bytes=SMALL_FILE_LIMIT)


@pytest.mark.parametrize("path,field,code", UPLOADS, ids=UPLOAD_IDS)
def test_signed_upload_declaring_too_much_is_refused_without_reading(path, field, code):
    settings = _small_upload_settings()
    cap = SMALL_FILE_LIMIT + MIB

    status, body, headers, consumed = _upload(
        _app(settings),
        path,
        field,
        cap,
        declare_length=True,
        headers={"Authorization": f"Bearer {_token(settings)}"},
    )

    assert status == 413
    _assert_error_envelope(body, headers, code)
    assert consumed == 0


@pytest.mark.parametrize("path,field,code", UPLOADS, ids=UPLOAD_IDS)
def test_signed_chunked_upload_is_cut_once_it_passes_the_limit(path, field, code):
    settings = _small_upload_settings()
    cap = SMALL_FILE_LIMIT + MIB
    sent = 8 * MIB

    status, body, headers, consumed = _upload(
        _app(settings),
        path,
        field,
        sent,
        declare_length=False,
        headers={"Authorization": f"Bearer {_token(settings)}"},
    )

    assert status == 413
    _assert_error_envelope(body, headers, code)
    # 상한을 넘긴 조각까지만 받고 나머지는 읽지 않는다.
    assert cap < consumed <= cap + CHUNK
    assert consumed < sent


@pytest.mark.parametrize("declare_length", [True, False], ids=["content-length", "chunked"])
def test_json_body_over_default_limit_is_refused(declare_length):
    sent = 4 * MIB
    status, body, headers, consumed = _call(
        _app(_settings()),
        "/api/v1/profiles",
        _json(sent),
        content_type="application/json",
        declare_length=declare_length,
    )

    assert status == 413
    _assert_error_envelope(body, headers, "REQUEST_TOO_LARGE")
    if declare_length:
        assert consumed == 0
    else:
        assert DEFAULT_BODY_LIMIT < consumed <= DEFAULT_BODY_LIMIT + CHUNK


def test_upload_limits_follow_route_settings():
    settings = _settings(max_image_bytes=3 * MIB, max_audio_bytes=40 * MIB)
    limits = {
        path: find_upload_route("POST", path).body_limit(settings)
        for path, _field, _code in UPLOADS
    }

    assert list(limits.values()) == [
        3 * MIB + MIB,
        3 * MIB + MIB,
        40 * MIB + MIB,
        min(40 * MIB, SHORT_AUDIO_MAX_BYTES) + MIB,
    ]
    small_audio = _settings(max_audio_bytes=2 * MIB)
    short = find_upload_route("POST", "/api/v1/speech-transcriptions")
    assert short.body_limit(small_audio) == 3 * MIB
    # 업로드가 아닌 메서드와 경로는 기본 상한이다.
    assert find_upload_route("GET", UPLOADS[0][0]) is None
    assert find_upload_route("POST", "/api/v1/profiles") is None
    assert find_upload_route("POST", UPLOADS[0][0] + "/extra") is None


def test_signed_photo_upload_at_the_file_limit_still_works(migrated_database_url):
    storage = MemoryImageStorage()
    api = DbApi(migrated_database_url)
    api.app.dependency_overrides[get_image_storage] = lambda: storage
    # 기본 상한 1 MiB보다 큰 파일이 업로드 경로에서는 통과하는지 본다.
    api.settings = api.settings.model_copy(update={"max_image_bytes": 2 * MIB})
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    at_limit = JPEG + b"\0" * (2 * MIB - len(JPEG))

    accepted = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/photos",
        files={"image": ("photo.jpg", at_limit, "image/jpeg")},
    )
    over = caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/photos",
        files={"image": ("photo.jpg", at_limit + b"\0", "image/jpeg")},
    )

    assert accepted.status_code == 201, accepted.text
    assert list(storage.objects.values()) == [at_limit]
    # 1바이트 넘는 파일은 미들웨어가 아니라 라우트의 파일 검사가 거절한다.
    assert (over.status_code, over.json()["errorCode"]) == (413, "IMAGE_TOO_LARGE")


def _wav_of_size(total_bytes: int) -> bytes:
    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(b"\0\0" * ((total_bytes - 44) // 2))
    data = output.getvalue()
    assert len(data) == total_bytes
    return data


def test_signed_short_audio_at_the_file_limit_still_works(migrated_database_url):
    storage = FakeAudioStorage()
    api = DbApi(migrated_database_url)
    api.app.dependency_overrides[get_speech_audio_storage] = lambda: storage
    api.app.state.ai_server_client = FakeAiServer()
    api.settings = api.settings.model_copy(update={"max_audio_bytes": 2 * MIB})
    caregiver = api.create_account()

    response = caregiver.call(
        "POST",
        "/api/v1/speech-transcriptions",
        files={"audio": ("synthetic.wav", _wav_of_size(2 * MIB), "audio/wav")},
    )

    assert response.status_code == 200, response.text
    assert response.json()["schemaVersion"] == 1
