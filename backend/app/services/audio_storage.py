from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import BinaryIO, Protocol

import boto3


@dataclass(frozen=True)
class AudioDownload:
    url: str
    expires_at: datetime


class AudioStorage(Protocol):
    async def upload(self, *, object_key: str, file: BinaryIO) -> None: ...

    async def create_download(
        self,
        *,
        object_key: str,
        expires_at: datetime,
    ) -> AudioDownload: ...

    async def delete(self, *, object_key: str) -> None: ...


class S3AudioStorage:
    """비공개 S3 버킷의 임시 면회 음성을 관리한다."""

    def __init__(
        self,
        *,
        bucket: str,
        region: str,
        presigned_ttl_seconds: int,
        server_side_encryption: str = "AES256",
        client: object | None = None,
    ) -> None:
        if not bucket:
            raise ValueError("S3 음성 버킷 이름이 필요합니다.")
        self._bucket = bucket
        self._presigned_ttl_seconds = presigned_ttl_seconds
        self._server_side_encryption = server_side_encryption
        self._client = client or boto3.client("s3", region_name=region)

    async def upload(self, *, object_key: str, file: BinaryIO) -> None:
        file.seek(0)
        await asyncio.to_thread(
            self._client.upload_fileobj,
            file,
            self._bucket,
            object_key,
            ExtraArgs={
                "ContentType": "audio/wav",
                "ServerSideEncryption": self._server_side_encryption,
            },
        )

    async def create_download(
        self,
        *,
        object_key: str,
        expires_at: datetime,
    ) -> AudioDownload:
        now = datetime.now(UTC)
        remaining = int((expires_at - now).total_seconds())
        ttl = min(self._presigned_ttl_seconds, remaining)
        if ttl <= 0:
            raise ValueError("음성 원본의 보관 기한이 지났습니다.")

        url = await asyncio.to_thread(
            self._client.generate_presigned_url,
            "get_object",
            Params={"Bucket": self._bucket, "Key": object_key},
            ExpiresIn=ttl,
        )
        return AudioDownload(url=url, expires_at=now + timedelta(seconds=ttl))

    async def delete(self, *, object_key: str) -> None:
        await asyncio.to_thread(
            self._client.delete_object,
            Bucket=self._bucket,
            Key=object_key,
        )
