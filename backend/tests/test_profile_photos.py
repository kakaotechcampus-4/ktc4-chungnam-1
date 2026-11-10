"""프로필 사진 API (3-1, 3-2)와 프로필 응답(2-3)의 사진 검증.

임시 DB에 최신 migration을 적용해 실행한다(`conftest.py`). S3는 메모리 저장소로 바꿔
끼운다. 사진과 값은 모두 합성 데이터다.
"""

import asyncio
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from io import BytesIO
from typing import BinaryIO
from uuid import UUID

from fastapi import UploadFile
import pytest

from app.api.deps import get_image_storage
from app.core.database import connect
from app.core.errors import AppError
from app.services import profile_photos
from app.services.image_storage import ImageDownload, UnconfiguredImageStorage
from app.services.image_validation import ValidatedImage
from app.services.storage_deletion import process_deletions
from tests.db_api import Caregiver, DbApi
from tests.support import run
from tests.test_storage_deletion import TARGETS, FakeDelete, process

JPEG = b"\xff\xd8\xff\xe0" + b"synthetic-jpeg"
PNG = b"\x89PNG\r\n\x1a\n" + b"synthetic-png"
URL_EXPIRES_AT = datetime(2026, 8, 21, 3, 35, tzinfo=UTC)
MISSING_ID = "00000000-0000-4000-8000-000000000999"


class MemoryImageStorage:
    """S3 대신 객체를 메모리에 둔다. 실패와 업로드 중의 다른 요청을 흉내 낼 수 있다."""

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

    async def upload(
        self, *, object_key: str, file: BinaryIO, image: ValidatedImage
    ) -> None:
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


def _api(database_url: str, storage: object) -> DbApi:
    api = DbApi(database_url)
    api.app.dependency_overrides[get_image_storage] = lambda: storage
    return api


def _upload(
    caregiver: Caregiver,
    profile_id: str,
    data: bytes = JPEG,
    filename: str = "photo.jpg",
):
    return caregiver.call(
        "POST",
        f"/api/v1/profiles/{profile_id}/photos",
        files={"image": (filename, data, "image/jpeg")},
    )


def _deletion_queue(api: DbApi) -> list[dict]:
    return api.query(
        "SELECT s3_object_key, not_before <= now() AS due "
        "FROM storage_deletion_request_queue ORDER BY s3_object_key"
    )


def _photo_rows(api: DbApi, profile_id: str) -> list[dict]:
    return api.query(
        "SELECT photo_id, s3_object_key, analysis_status FROM photos "
        "WHERE profile_id = %s AND session_id IS NULL ORDER BY created_at",
        (profile_id,),
    )


def test_uploaded_photo_is_stored_and_waits_for_analysis(migrated_database_url):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]

    response = _upload(caregiver, profile_id, PNG, "photo.jpg")

    assert response.status_code == 201
    body = response.json()
    photo_id = body.pop("photoId")
    assert body.pop("createdAt")
    # 확장자와 Content-Type은 앱이 보낸 이름이 아니라 파일 시그니처를 따른다.
    object_key = f"photos/{photo_id}.png"
    assert body == {
        "schemaVersion": 1,
        "profileId": profile_id,
        "imageUrl": (
            f"https://synthetic-bucket.example/{object_key}?signature=synthetic"
        ),
        "imageUrlExpiresAt": "2026-08-21T03:35:00Z",
        "analysisStatus": "pending",
        "description": None,
        "descriptionSource": None,
        "error": None,
    }
    assert storage.objects == {object_key: PNG}
    assert _photo_rows(api, profile_id) == [
        {
            "photo_id": UUID(photo_id),
            "s3_object_key": object_key,
            "analysis_status": "pending",
        }
    ]


def test_profile_and_photo_reads_show_analysis_results(migrated_database_url):
    api = _api(migrated_database_url, MemoryImageStorage())
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    photo_ids = [_upload(caregiver, profile_id).json()["photoId"] for _ in range(3)]
    api.query(
        "UPDATE photos SET analysis_status = 'completed', description = '합성 사진 설명', "
        "model = 'synthetic-model', prompt_version = 'image-v1' WHERE photo_id = %s",
        (photo_ids[0],),
    )
    api.query(
        "UPDATE photos SET analysis_status = 'failed', error_code = 'AI_SERVER_ERROR' "
        "WHERE photo_id = %s",
        (photo_ids[1],),
    )

    profile = caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()
    single = caregiver.call("GET", f"/api/v1/profile-photos/{photo_ids[0]}")

    assert [photo["photoId"] for photo in profile["photos"]] == photo_ids
    assert [
        (photo["analysisStatus"], photo["description"], photo["error"])
        for photo in profile["photos"]
    ] == [
        ("completed", "합성 사진 설명", None),
        ("failed", None, {"errorCode": "AI_SERVER_ERROR"}),
        ("pending", None, None),
    ]
    assert single.status_code == 200
    assert single.json() == profile["photos"][0]


def test_invalid_and_too_large_images_are_refused_before_upload(
    migrated_database_url,
):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    api.settings = api.settings.model_copy(update={"max_image_bytes": len(JPEG)})
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]

    not_image = _upload(caregiver, profile_id, b"GIF89a-synthetic", "photo.jpg")
    too_large = _upload(caregiver, profile_id, JPEG + b"x")
    missing = caregiver.call("POST", f"/api/v1/profiles/{profile_id}/photos")

    assert (not_image.status_code, not_image.json()["errorCode"]) == (
        422,
        "INVALID_IMAGE_FORMAT",
    )
    assert (too_large.status_code, too_large.json()["errorCode"]) == (
        413,
        "IMAGE_TOO_LARGE",
    )
    assert (missing.status_code, missing.json()["errorCode"]) == (
        422,
        "INVALID_REQUEST",
    )
    assert storage.uploads == 0
    assert _photo_rows(api, profile_id) == []


def test_sixth_photo_is_refused_but_visit_photos_do_not_count(
    migrated_database_url,
):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    session_id = api.query(
        "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
        (profile_id,),
    )[0]["session_id"]
    api.query(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, 'synthetic/visit.jpg')",
        (profile_id, session_id),
    )
    for _ in range(profile_photos.PHOTO_LIMIT):
        assert _upload(caregiver, profile_id).status_code == 201

    refused = _upload(caregiver, profile_id)

    assert refused.status_code == 409
    assert refused.json()["errorCode"] == "PHOTO_LIMIT_EXCEEDED"
    assert storage.uploads == profile_photos.PHOTO_LIMIT
    assert len(_photo_rows(api, profile_id)) == profile_photos.PHOTO_LIMIT
    profile = caregiver.call("GET", f"/api/v1/profiles/{profile_id}").json()
    assert len(profile["photos"]) == profile_photos.PHOTO_LIMIT


def _fill_to_limit_during_upload(api: DbApi, profile_id: str):
    """업로드하는 동안 다른 요청이 마지막 자리를 채운 것처럼 행을 넣는다."""

    async def fill() -> None:
        async with connect(api.database_url) as connection:
            await connection.execute(
                "INSERT INTO photos (profile_id, s3_object_key) "
                "VALUES (%s, 'synthetic/concurrent.jpg')",
                (profile_id,),
            )

    return fill


def _seed_photos(api: DbApi, profile_id: str, count: int) -> None:
    for index in range(count):
        api.query(
            "INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, %s)",
            (profile_id, f"synthetic/{profile_id}/{index}.jpg"),
        )


def test_upload_that_loses_the_last_slot_removes_its_object(migrated_database_url):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    _seed_photos(api, profile_id, profile_photos.PHOTO_LIMIT - 1)
    storage.on_upload = _fill_to_limit_during_upload(api, profile_id)

    refused = _upload(caregiver, profile_id)

    assert refused.status_code == 409
    assert refused.json()["errorCode"] == "PHOTO_LIMIT_EXCEEDED"
    assert storage.uploads == 1
    assert storage.objects == {}
    assert len(_photo_rows(api, profile_id)) == profile_photos.PHOTO_LIMIT
    # 바로 지웠어도 삭제 확인은 실행기에 맡기므로 요청이 남고, 기한을 기다리지 않는다.
    [queued] = _deletion_queue(api)
    assert queued["s3_object_key"].startswith("photos/") and queued["due"] is True


def test_object_that_cannot_be_removed_is_queued_for_deletion(
    migrated_database_url,
):
    storage = MemoryImageStorage(delete_fails=True)
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    _seed_photos(api, profile_id, profile_photos.PHOTO_LIMIT - 1)
    storage.on_upload = _fill_to_limit_during_upload(api, profile_id)

    refused = _upload(caregiver, profile_id)

    assert refused.json()["errorCode"] == "PHOTO_LIMIT_EXCEEDED"
    [left_over] = storage.objects
    assert _deletion_queue(api) == [{"s3_object_key": left_over, "due": True}]


def test_concurrent_uploads_do_not_exceed_the_limit(migrated_database_url):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = UUID(caregiver.create_profile()["profileId"])

    async def upload_one() -> str:
        async with connect(migrated_database_url) as connection:
            try:
                await profile_photos.add_profile_photo(
                    connection,
                    storage,
                    profile_id,
                    account_id=caregiver.account_id,
                    image=UploadFile(file=BytesIO(JPEG), filename="photo.jpg"),
                    max_size_bytes=1024,
                )
            except AppError as error:
                return error.error_code
            return "created"

    async def scenario() -> list[str]:
        return await asyncio.gather(*(upload_one() for _ in range(7)))

    results = run(scenario())

    assert sorted(results) == ["PHOTO_LIMIT_EXCEEDED"] * 2 + ["created"] * 5
    rows = _photo_rows(api, str(profile_id))
    assert len(rows) == profile_photos.PHOTO_LIMIT
    # 거절된 요청이 올린 객체는 남지 않는다.
    assert set(storage.objects) == {row["s3_object_key"] for row in rows}


def test_other_accounts_and_visit_photos_look_missing(migrated_database_url):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    owner = api.create_account()
    stranger = api.create_account()
    profile_id = owner.create_profile()["profileId"]
    photo_id = _upload(owner, profile_id).json()["photoId"]
    session_id = api.query(
        "INSERT INTO visit_sessions (profile_id) VALUES (%s) RETURNING session_id",
        (profile_id,),
    )[0]["session_id"]
    visit_photo_id = api.query(
        "INSERT INTO photos (profile_id, session_id, s3_object_key) "
        "VALUES (%s, %s, 'synthetic/visit.jpg') RETURNING photo_id",
        (profile_id, session_id),
    )[0]["photo_id"]

    upload_to_other = _upload(stranger, profile_id)
    upload_to_missing = _upload(owner, MISSING_ID)
    reads = [
        stranger.call("GET", f"/api/v1/profile-photos/{photo_id}"),
        owner.call("GET", f"/api/v1/profile-photos/{visit_photo_id}"),
        owner.call("GET", f"/api/v1/profile-photos/{MISSING_ID}"),
    ]

    assert [upload_to_other.status_code, upload_to_missing.status_code] == [404, 404]
    assert {
        upload_to_other.json()["errorCode"],
        upload_to_missing.json()["errorCode"],
    } == {"PROFILE_NOT_FOUND"}
    assert [r.status_code for r in reads] == [404] * 3
    assert {r.json()["errorCode"] for r in reads} == {"PROFILE_PHOTO_NOT_FOUND"}
    assert storage.uploads == 1
    # 면회 사진은 프로필 응답의 사진 목록에도 담기지 않는다.
    profile = owner.call("GET", f"/api/v1/profiles/{profile_id}").json()
    assert [photo["photoId"] for photo in profile["photos"]] == [photo_id]


def test_storage_failures_are_reported_without_saving(migrated_database_url):
    failing = MemoryImageStorage(upload_fails=True)
    api = _api(migrated_database_url, failing)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]

    unavailable = _upload(caregiver, profile_id)
    api.app.dependency_overrides[get_image_storage] = UnconfiguredImageStorage
    not_configured = _upload(caregiver, profile_id)
    # 사진이 없는 프로필은 버킷 설정 없이도 읽힌다.
    readable = caregiver.call("GET", f"/api/v1/profiles/{profile_id}")

    assert unavailable.status_code == 503
    assert unavailable.json()["errorCode"] == "IMAGE_STORAGE_UNAVAILABLE"
    assert unavailable.json()["retryable"] is True
    assert not_configured.status_code == 503
    assert not_configured.json()["errorCode"] == "IMAGE_STORAGE_NOT_CONFIGURED"
    assert not_configured.json()["retryable"] is False
    assert _photo_rows(api, profile_id) == []
    # 업로드 실패는 응답만 잃고 저장됐을 수도 있어 삭제 요청을 남긴다. 저장소가 설정되지
    # 않았으면 객체 키를 만들기 전에 거절하므로 요청도 없다.
    [queued] = _deletion_queue(api)
    assert queued["due"] is True
    assert readable.status_code == 200
    assert readable.json()["photos"] == []


def test_deleting_a_profile_photo_removes_it_and_queues_the_file(migrated_database_url):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    photo_id = _upload(caregiver, profile_id).json()["photoId"]
    object_key = f"photos/{photo_id}.jpg"

    response = caregiver.call("DELETE", f"/api/v1/profile-photos/{photo_id}")

    assert response.status_code == 204
    assert caregiver.call("GET", f"/api/v1/profile-photos/{photo_id}").status_code == 404
    assert _photo_rows(api, profile_id) == []
    # S3 원본은 트리거가 넣은 삭제 대기열로 지운다. 요청 처리 중에는 저장소를 부르지 않는다.
    assert api.query(
        "SELECT s3_object_key FROM storage_deletion_request_queue WHERE s3_object_key = %s",
        (object_key,),
    ) == [{"s3_object_key": object_key}]


def test_another_account_cannot_delete_the_photo(migrated_database_url):
    api = _api(migrated_database_url, MemoryImageStorage())
    owner = api.create_account()
    other = api.create_account()
    profile_id = owner.create_profile()["profileId"]
    photo_id = _upload(owner, profile_id).json()["photoId"]

    response = other.call("DELETE", f"/api/v1/profile-photos/{photo_id}")

    assert response.status_code == 404
    assert response.json()["errorCode"] == "PROFILE_PHOTO_NOT_FOUND"
    assert len(_photo_rows(api, profile_id)) == 1


def test_deleting_a_photo_makes_the_unused_card_set_need_refresh(migrated_database_url):
    api = _api(migrated_database_url, MemoryImageStorage())
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    photo_id = _upload(caregiver, profile_id).json()["photoId"]
    api.query(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version, generation_log) "
        "VALUES (%s, 'completed', 'synthetic-model', '1', '{\"input\": {}}')",
        (profile_id,),
    )

    assert caregiver.call("DELETE", f"/api/v1/profile-photos/{photo_id}").status_code == 204

    status = caregiver.call("GET", f"/api/v1/profiles/{profile_id}/card-generations/status")
    assert status.json()["needsRefresh"] is True


def test_photo_is_kept_while_cards_are_being_generated(migrated_database_url):
    api = _api(migrated_database_url, MemoryImageStorage())
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    photo_id = _upload(caregiver, profile_id).json()["photoId"]
    api.query(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
        "VALUES (%s, 'running', 'synthetic-model', '1')",
        (profile_id,),
    )

    response = caregiver.call("DELETE", f"/api/v1/profile-photos/{photo_id}")

    assert response.status_code == 409
    assert response.json()["errorCode"] == "CARD_GENERATION_IN_PROGRESS"
    assert len(_photo_rows(api, profile_id)) == 1


def test_upload_keeps_a_deletion_request_only_until_the_row_is_saved(
    migrated_database_url,
):
    storage = MemoryImageStorage()
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]
    seen = {}

    async def look_during_upload() -> None:
        async with connect(migrated_database_url) as connection:
            cursor = await connection.execute(
                "SELECT s3_object_key, not_before > now() + interval '50 minutes' AS later "
                "FROM storage_deletion_request_queue"
            )
            seen["queue"] = await cursor.fetchall()
            seen["runner"] = await process_deletions(
                connection, targets=TARGETS, backend=FakeDelete()
            )

    storage.on_upload = look_during_upload

    response = _upload(caregiver, profile_id)

    assert response.status_code == 201
    [object_key] = storage.objects
    # 올리는 동안에는 키가 기한과 함께 대기열에 있고, 삭제 실행기는 기한 전이라 읽지 않는다.
    assert seen["queue"] == [{"s3_object_key": object_key, "later": True}]
    assert seen["runner"]["inspected"] == 0
    # 행을 넣은 트랜잭션에서 사전 등록을 지웠다. 이후 삭제는 photos trigger가 맡는다.
    assert _deletion_queue(api) == []


class _Stopped(BaseException):
    """업로드 직후 프로세스가 끝나 이후 코드가 돌지 않은 경우를 흉내 낸다."""


def test_object_left_by_a_stopped_upload_is_reached_after_the_window(
    migrated_database_url,
):
    async def stop() -> None:
        raise _Stopped

    storage = MemoryImageStorage(on_upload=stop)
    api = _api(migrated_database_url, storage)
    caregiver = api.create_account()
    profile_id = caregiver.create_profile()["profileId"]

    async def upload() -> None:
        async with connect(migrated_database_url) as connection:
            await profile_photos.add_profile_photo(
                connection,
                storage,
                UUID(profile_id),
                account_id=caregiver.account_id,
                image=UploadFile(file=BytesIO(JPEG), filename="photo.jpg"),
                max_size_bytes=1024,
            )

    with pytest.raises(_Stopped):
        run(upload())
    [object_key] = storage.objects
    # 탈퇴해도 사진 행이 없어 trigger는 닿지 않는다. 미리 넣은 요청이 객체를 가리킨다.
    api.query("DELETE FROM users WHERE user_id = %s", (caregiver.account_id,))
    assert _deletion_queue(api) == [{"s3_object_key": object_key, "due": False}]
    assert process(migrated_database_url, FakeDelete())["inspected"] == 0

    api.query(
        "UPDATE storage_deletion_request_queue SET not_before = now() - interval '1 second'"
    )
    backend = FakeDelete()
    result = process(migrated_database_url, backend, apply=True)

    assert result["deleted"] == 1 and result["errors"] == {}
    assert backend.calls == [(TARGETS[1], object_key)]
    assert _deletion_queue(api) == []
