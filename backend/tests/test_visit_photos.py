"""API 5-2(면회 사진) 검증.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). S3는 메모리 저장소로 바꿔 끼움.
사진과 값은 모두 합성 데이터.
"""

from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import BinaryIO
from uuid import UUID

from app.api.deps import get_image_storage
from app.core.database import connect
from app.core.errors import AppError
from app.services.image_storage import ImageDownload, UnconfiguredImageStorage
from app.services.image_validation import ValidatedImage
from tests.card_fixtures import (
    completed_card_set,
    make_app,
    query,
    user_and_profile,
    visit_with,
    with_db,
)
from tests.support import request

JPEG = b"\xff\xd8\xff\xe0" + b"synthetic-jpeg"
PNG = b"\x89PNG\r\n\x1a\n" + b"synthetic-png"
URL_EXPIRES_AT = datetime(2026, 8, 21, 5, 15, tzinfo=UTC)
MISSING_ID = "00000000-0000-4000-8000-000000000999"


class MemoryImageStorage:
    """S3 대신 객체를 메모리에 둠. 실패와 업로드 중의 다른 요청을 흉내 낼 수 있음."""

    def __init__(
        self,
        *,
        upload_fails: bool = False,
        delete_fails: bool = False,
        on_upload: Callable[[], Awaitable[None]] | None = None,
    ) -> None:
        self.objects: dict[str, bytes] = {}
        self.upload_fails = upload_fails
        self.delete_fails = delete_fails
        self.on_upload = on_upload
        self.uploads = 0

    def object_key(self, *, photo_id: UUID, image: ValidatedImage) -> str:
        return f"photos/{photo_id}.{image.extension}"

    async def upload(self, *, object_key: str, file: BinaryIO, image: ValidatedImage) -> None:
        self.uploads += 1
        if self.upload_fails:
            raise _storage_unavailable()
        file.seek(0)
        self.objects[object_key] = file.read()
        if self.on_upload is not None:
            await self.on_upload()

    async def create_download(self, *, object_key: str) -> ImageDownload:
        return ImageDownload(
            url=f"https://synthetic-bucket.example/{object_key}?signature=synthetic",
            expires_at=URL_EXPIRES_AT,
        )

    async def delete(self, *, object_key: str) -> None:
        if self.delete_fails:
            raise _storage_unavailable()
        self.objects.pop(object_key, None)


def _storage_unavailable() -> AppError:
    return AppError(
        status_code=503,
        error_code="IMAGE_STORAGE_UNAVAILABLE",
        message="사진 저장소를 사용할 수 없습니다.",
        retryable=True,
    )


async def _session(connection, *, evaluated=False):
    user_id, profile_id = await user_and_profile(connection)
    set_id, cards = await completed_card_set(connection, profile_id)
    session_id = await visit_with(connection, profile_id, set_id, evaluated=evaluated)
    return user_id, profile_id, session_id, cards


def _execute_during_upload(database_url, sql, params):
    """업로드하는 동안 다른 요청이 같은 회차를 바꾼 것처럼 SQL을 실행."""

    async def execute() -> None:
        async with connect(database_url) as connection:
            await connection.execute(sql, params)

    return execute


def _app(database_url, user_id, storage, **settings):
    app = make_app(database_url, user_id, **settings)
    app.dependency_overrides[get_image_storage] = lambda: storage
    return app


def _upload(app, session_id, data=JPEG, filename="visit.jpg"):
    return request(
        app,
        "POST",
        f"/api/v1/visit-sessions/{session_id}/photo",
        files={"image": (filename, data, "image/jpeg")},
    )


def _photo_rows(database_url, session_id):
    return query(
        database_url,
        "SELECT photo_id, s3_object_key, analysis_status FROM photos WHERE session_id = %s",
        (session_id,),
    )


def _deletion_queue(database_url):
    return query(
        database_url,
        "SELECT s3_object_key FROM storage_deletion_request_queue ORDER BY s3_object_key",
    )


def test_uploaded_photo_is_stored_on_the_session(migrated_database_url):
    user_id, profile_id, session_id, cards = with_db(migrated_database_url, _session)
    storage = MemoryImageStorage()
    app = _app(migrated_database_url, user_id, storage)

    response = _upload(app, session_id, PNG, "visit.jpg")
    session = request(
        app,
        "PATCH",
        f"/api/v1/visit-sessions/{session_id}/cards",
        json={"cardIds": [str(cards[9])]},
    )

    assert response.status_code == 201
    body = response.json()
    photo_id = body.pop("photoId")
    assert body.pop("createdAt")
    # 확장자와 Content-Type은 앱이 보낸 이름이 아니라 파일 시그니처를 따름.
    object_key = f"photos/{photo_id}.png"
    assert body == {
        "schemaVersion": 1,
        "sessionId": str(session_id),
        "imageUrl": f"https://synthetic-bucket.example/{object_key}?signature=synthetic",
        "imageUrlExpiresAt": "2026-08-21T05:15:00Z",
    }
    assert storage.objects == {object_key: PNG}
    # 면회 사진은 분석하지 않으므로 기본값 `pending`으로 남고 분석 대기열이 가져가지 않음.
    assert _photo_rows(migrated_database_url, session_id) == [
        {"photo_id": UUID(photo_id), "s3_object_key": object_key, "analysis_status": "pending"}
    ]
    owner = query(
        migrated_database_url, "SELECT profile_id FROM photos WHERE photo_id = %s", (photo_id,)
    )
    assert owner == [{"profile_id": profile_id}]
    # 회차 응답(5-3)의 `photoId`에도 이어짐.
    assert session.status_code == 200 and session.json()["photoId"] == photo_id


def test_second_upload_replaces_the_photo(migrated_database_url):
    user_id, _, session_id, _ = with_db(migrated_database_url, _session)
    storage = MemoryImageStorage()
    app = _app(migrated_database_url, user_id, storage)

    first = _upload(app, session_id).json()
    second = _upload(app, session_id, PNG)

    assert second.status_code == 201
    [row] = _photo_rows(migrated_database_url, session_id)
    assert str(row["photo_id"]) == second.json()["photoId"] != first["photoId"]
    # 지운 행의 객체 키는 trigger가 S3 삭제 대기열에 넣음.
    assert _deletion_queue(migrated_database_url) == [
        {"s3_object_key": f"photos/{first['photoId']}.jpg"}
    ]


def test_evaluated_session_refuses_photo_before_upload(migrated_database_url):
    async def build(connection):
        return await _session(connection, evaluated=True)

    user_id, _, session_id, _ = with_db(migrated_database_url, build)
    storage = MemoryImageStorage()

    res = _upload(_app(migrated_database_url, user_id, storage), session_id)

    assert res.status_code == 409 and res.json()["errorCode"] == "INVALID_SESSION_STATE"
    assert storage.uploads == 0
    assert _photo_rows(migrated_database_url, session_id) == []


def test_session_evaluated_during_upload_removes_its_object(migrated_database_url):
    user_id, _, session_id, _ = with_db(migrated_database_url, _session)
    evaluate = _execute_during_upload(
        migrated_database_url,
        "UPDATE visit_sessions SET evaluated_at = now(), evaluation_satisfaction = 4,"
        " evaluation_reaction = 'pleased' WHERE session_id = %s",
        (session_id,),
    )
    storage = MemoryImageStorage(on_upload=evaluate)

    res = _upload(_app(migrated_database_url, user_id, storage), session_id)

    assert res.status_code == 409 and res.json()["errorCode"] == "INVALID_SESSION_STATE"
    assert storage.uploads == 1 and storage.objects == {}
    assert _photo_rows(migrated_database_url, session_id) == []
    assert _deletion_queue(migrated_database_url) == []


def test_object_that_cannot_be_removed_is_queued_for_deletion(migrated_database_url):
    user_id, profile_id, session_id, _ = with_db(migrated_database_url, _session)
    # 업로드하는 동안 같은 계정의 다른 요청이 프로필을 지워 회차도 함께 지워짐.
    delete_profile = _execute_during_upload(
        migrated_database_url, "DELETE FROM profiles WHERE profile_id = %s", (profile_id,)
    )
    storage = MemoryImageStorage(delete_fails=True, on_upload=delete_profile)

    res = _upload(_app(migrated_database_url, user_id, storage), session_id)

    assert res.status_code == 404 and res.json()["errorCode"] == "VISIT_SESSION_NOT_FOUND"
    [left_over] = storage.objects
    assert _deletion_queue(migrated_database_url) == [{"s3_object_key": left_over}]


def test_invalid_and_too_large_images_are_refused_before_upload(migrated_database_url):
    user_id, _, session_id, _ = with_db(migrated_database_url, _session)
    storage = MemoryImageStorage()
    app = _app(migrated_database_url, user_id, storage, max_image_bytes=len(JPEG))

    not_image = _upload(app, session_id, b"GIF89a-synthetic")
    too_large = _upload(app, session_id, JPEG + b"x")
    missing = request(app, "POST", f"/api/v1/visit-sessions/{session_id}/photo")

    assert (not_image.status_code, not_image.json()["errorCode"]) == (
        422,
        "INVALID_IMAGE_FORMAT",
    )
    assert (too_large.status_code, too_large.json()["errorCode"]) == (413, "IMAGE_TOO_LARGE")
    assert (missing.status_code, missing.json()["errorCode"]) == (422, "INVALID_REQUEST")
    assert storage.uploads == 0
    assert _photo_rows(migrated_database_url, session_id) == []


def test_other_accounts_and_missing_sessions_are_not_found(migrated_database_url):
    async def build(connection):
        _, _, session_id, _ = await _session(connection)
        other_user, _ = await user_and_profile(connection)
        return other_user, session_id

    other_user, session_id = with_db(migrated_database_url, build)
    storage = MemoryImageStorage()
    app = _app(migrated_database_url, other_user, storage)

    responses = [_upload(app, session_id), _upload(app, MISSING_ID)]

    assert [r.status_code for r in responses] == [404, 404]
    assert {r.json()["errorCode"] for r in responses} == {"VISIT_SESSION_NOT_FOUND"}
    assert storage.uploads == 0


def test_storage_failures_are_reported_without_saving(migrated_database_url):
    user_id, _, session_id, _ = with_db(migrated_database_url, _session)
    app = _app(migrated_database_url, user_id, MemoryImageStorage(upload_fails=True))

    unavailable = _upload(app, session_id)
    app.dependency_overrides[get_image_storage] = UnconfiguredImageStorage
    not_configured = _upload(app, session_id)

    assert unavailable.status_code == 503
    assert unavailable.json()["errorCode"] == "IMAGE_STORAGE_UNAVAILABLE"
    assert unavailable.json()["retryable"] is True
    assert not_configured.status_code == 503
    assert not_configured.json()["errorCode"] == "IMAGE_STORAGE_NOT_CONFIGURED"
    assert _photo_rows(migrated_database_url, session_id) == []
