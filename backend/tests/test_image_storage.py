"""사진 업로드 검증과 S3 사진 저장소 검증. 값은 모두 합성 데이터다."""

from io import BytesIO
from uuid import UUID

import pytest
from botocore.exceptions import ClientError
from fastapi import UploadFile

from app.api.deps import get_image_storage
from app.core.config import Settings
from app.core.errors import AppError
from app.services.image_storage import S3ImageStorage, UnconfiguredImageStorage
from app.services.image_validation import ValidatedImage, validate_image
from tests.support import run

JPEG = b"\xff\xd8\xff\xe0" + b"synthetic-jpeg"
PNG = b"\x89PNG\r\n\x1a\n" + b"synthetic-png"
PHOTO_ID = UUID("00000000-0000-4000-8000-000000000121")


def _upload(data: bytes, filename: str = "photo.jpg") -> UploadFile:
    return UploadFile(file=BytesIO(data), filename=filename)


class FakeS3Client:
    def __init__(self, *, fails: bool = False) -> None:
        self.fails = fails
        self.upload = None
        self.presign = None
        self.delete = None

    def _maybe_fail(self) -> None:
        if self.fails:
            raise ClientError({"Error": {"Code": "InternalError"}}, "operation")

    def upload_fileobj(self, file, bucket, key, ExtraArgs):
        self._maybe_fail()
        self.upload = (file.read(), bucket, key, ExtraArgs)

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        self._maybe_fail()
        self.presign = (operation, Params, ExpiresIn)
        return "https://synthetic-bucket.s3.amazonaws.com/object"

    def delete_object(self, *, Bucket, Key):
        self._maybe_fail()
        self.delete = (Bucket, Key)


def _storage(client: FakeS3Client) -> S3ImageStorage:
    return S3ImageStorage(
        bucket="synthetic-bucket",
        region="ap-northeast-2",
        prefix="photos/",
        presigned_ttl_seconds=900,
        client=client,
    )


@pytest.mark.parametrize(
    ("data", "content_type", "extension"),
    [(JPEG, "image/jpeg", "jpg"), (PNG, "image/png", "png")],
)
def test_jpeg_and_png_are_detected_from_the_file_itself(data, content_type, extension):
    # 파일 이름이나 앱이 보낸 형식이 아니라 파일 시그니처로 판단한다.
    upload = _upload(data, filename="photo.gif")

    image = run(validate_image(upload, max_size_bytes=1024))

    assert image == ValidatedImage(content_type, extension, len(data))
    assert run(upload.read()) == data, "업로드에 쓸 수 있게 처음으로 되감는다"


@pytest.mark.parametrize("data", [b"", b"GIF89a-synthetic", b"\xff\xd8"])
def test_other_formats_are_rejected(data):
    with pytest.raises(AppError) as excinfo:
        run(validate_image(_upload(data), max_size_bytes=1024))

    assert (excinfo.value.status_code, excinfo.value.error_code) == (
        422,
        "INVALID_IMAGE_FORMAT",
    )


def test_images_over_the_limit_are_rejected():
    with pytest.raises(AppError) as excinfo:
        run(validate_image(_upload(JPEG), max_size_bytes=len(JPEG) - 1))

    assert (excinfo.value.status_code, excinfo.value.error_code) == (
        413,
        "IMAGE_TOO_LARGE",
    )


def test_s3_photo_is_private_encrypted_and_keyed_without_personal_data():
    client = FakeS3Client()
    storage = _storage(client)
    image = ValidatedImage("image/png", "png", len(PNG))

    key = storage.object_key(photo_id=PHOTO_ID, image=image)
    run(storage.upload(object_key=key, file=BytesIO(PNG), image=image))
    download = run(storage.create_download(object_key=key))
    run(storage.delete(object_key=key))

    assert key == f"photos/{PHOTO_ID}.png"
    assert client.upload == (
        PNG,
        "synthetic-bucket",
        key,
        {"ContentType": "image/png", "ServerSideEncryption": "AES256"},
    )
    assert client.presign == (
        "get_object",
        {"Bucket": "synthetic-bucket", "Key": key},
        900,
    )
    assert download.url.startswith("https://")
    assert download.expires_at is not None
    assert client.delete == ("synthetic-bucket", key)


def test_s3_failures_become_a_retryable_storage_error():
    storage = _storage(FakeS3Client(fails=True))
    image = ValidatedImage("image/jpeg", "jpg", len(JPEG))

    for call in (
        lambda: storage.upload(object_key="photos/x.jpg", file=BytesIO(JPEG), image=image),
        lambda: storage.create_download(object_key="photos/x.jpg"),
        lambda: storage.delete(object_key="photos/x.jpg"),
    ):
        with pytest.raises(AppError) as excinfo:
            run(call())
        error = excinfo.value
        assert (error.status_code, error.error_code, error.retryable) == (
            503,
            "IMAGE_STORAGE_UNAVAILABLE",
            True,
        )
        assert "photos/x.jpg" not in error.message


def test_unconfigured_storage_refuses_only_when_a_photo_is_needed(monkeypatch):
    monkeypatch.setattr(
        "app.api.deps.get_settings", lambda: Settings(_env_file=None, image_s3_bucket="")
    )
    get_image_storage.cache_clear()
    try:
        storage = get_image_storage()
    finally:
        get_image_storage.cache_clear()

    assert isinstance(storage, UnconfiguredImageStorage)
    with pytest.raises(AppError) as excinfo:
        run(storage.create_download(object_key="photos/x.jpg"))
    assert (excinfo.value.status_code, excinfo.value.error_code) == (
        503,
        "IMAGE_STORAGE_NOT_CONFIGURED",
    )
