import asyncio
from datetime import UTC, datetime, timedelta
from io import BytesIO

from app.services.audio_storage import S3AudioStorage


class FakeS3Client:
    def __init__(self) -> None:
        self.upload = None
        self.presign = None
        self.delete = None

    def upload_fileobj(self, file, bucket, key, ExtraArgs):
        self.upload = (file.read(), bucket, key, ExtraArgs)

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        self.presign = (operation, Params, ExpiresIn)
        return "https://synthetic-bucket.s3.amazonaws.com/object"

    def delete_object(self, *, Bucket, Key):
        self.delete = (Bucket, Key)


def test_s3_audio_is_private_encrypted_and_has_a_bounded_download_url() -> None:
    client = FakeS3Client()
    storage = S3AudioStorage(
        bucket="synthetic-bucket",
        region="ap-northeast-2",
        presigned_ttl_seconds=900,
        client=client,
    )
    file = BytesIO(b"synthetic-wave")

    asyncio.run(storage.upload(object_key="temporary/speech/id.wav", file=file))
    download = asyncio.run(
        storage.create_download(
            object_key="temporary/speech/id.wav",
            expires_at=datetime.now(UTC) + timedelta(minutes=5),
        )
    )
    asyncio.run(storage.delete(object_key="temporary/speech/id.wav"))

    assert client.upload == (
        b"synthetic-wave",
        "synthetic-bucket",
        "temporary/speech/id.wav",
        {"ContentType": "audio/wav", "ServerSideEncryption": "AES256"},
    )
    assert client.presign[0] == "get_object"
    assert 0 < client.presign[2] <= 300
    assert download.url.startswith("https://")
    assert client.delete == ("synthetic-bucket", "temporary/speech/id.wav")
