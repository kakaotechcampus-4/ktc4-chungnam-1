import asyncio
from datetime import UTC, datetime, timedelta
from io import BytesIO
from urllib.parse import parse_qs, urlsplit

import boto3

from app.services.audio_storage import S3AudioStorage


def test_download_url_uses_regional_endpoint_without_network(monkeypatch) -> None:
    create_client = boto3.client

    def client_with_synthetic_credentials(*args, **kwargs):
        return create_client(
            *args, **kwargs,
            aws_access_key_id="synthetic", aws_secret_access_key="synthetic",
        )

    monkeypatch.setattr(boto3, "client", client_with_synthetic_credentials)
    storage = S3AudioStorage(
        bucket="synthetic-bucket", region="ap-northeast-2", presigned_ttl_seconds=900
    )
    download = asyncio.run(storage.create_download(
        object_key="temporary/speech/synthetic.wav",
        expires_at=datetime.now(UTC) + timedelta(minutes=5),
    ))
    parsed = urlsplit(download.url)
    assert parsed.hostname == "synthetic-bucket.s3.ap-northeast-2.amazonaws.com"
    assert parsed.path == "/temporary/speech/synthetic.wav"
    query = parse_qs(parsed.query)
    assert query["X-Amz-Algorithm"] == ["AWS4-HMAC-SHA256"]
    assert "/ap-northeast-2/s3/aws4_request" in query["X-Amz-Credential"][0]


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
