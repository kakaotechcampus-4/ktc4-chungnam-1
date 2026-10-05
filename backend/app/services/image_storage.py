"""프로필 사진과 면회 사진의 S3 저장.

사진은 음성과 달리 계속 보관하므로, 음성 버킷의 24시간 Lifecycle이 걸리지 않는 비공개
버킷에 서버 측 암호화로 저장한다. 객체 키에는 개인정보를 넣지 않고 `photo_id`만 쓴다.
앱 응답의 `imageUrl`과 AI 서버에 넘기는 `downloadUrl`은 모두 수명이 짧은 Presigned GET
URL이다.

S3 오류는 `IMAGE_STORAGE_UNAVAILABLE`(503, 재시도 가능)로 바꿔 올린다. 버킷이 설정되지
않았으면 사진이 필요한 순간에만 `IMAGE_STORAGE_NOT_CONFIGURED`(503)로 거절하므로, 사진이
없는 프로필 조회 같은 요청은 그대로 동작한다.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import BinaryIO, Protocol
from uuid import UUID

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from app.core.errors import AppError
from app.services.image_validation import ValidatedImage


@dataclass(frozen=True)
class ImageDownload:
    url: str
    expires_at: datetime


class ImageStorage(Protocol):
    def object_key(self, *, photo_id: UUID, image: ValidatedImage) -> str: ...

    async def upload(
        self, *, object_key: str, file: BinaryIO, image: ValidatedImage
    ) -> None: ...

    async def create_download(self, *, object_key: str) -> ImageDownload: ...

    async def delete(self, *, object_key: str) -> None: ...


class S3ImageStorage:
    def __init__(
        self,
        *,
        bucket: str,
        region: str,
        prefix: str,
        presigned_ttl_seconds: int,
        server_side_encryption: str = "AES256",
        client: object | None = None,
    ) -> None:
        if not bucket:
            raise ValueError("S3 사진 버킷 이름이 필요합니다.")
        self._bucket = bucket
        self._prefix = prefix.strip("/")
        self._presigned_ttl_seconds = presigned_ttl_seconds
        self._server_side_encryption = server_side_encryption
        self._client = client or boto3.client("s3", region_name=region)

    def object_key(self, *, photo_id: UUID, image: ValidatedImage) -> str:
        return f"{self._prefix}/{photo_id}.{image.extension}"

    async def upload(
        self, *, object_key: str, file: BinaryIO, image: ValidatedImage
    ) -> None:
        file.seek(0)
        await self._call(
            self._client.upload_fileobj,
            file,
            self._bucket,
            object_key,
            ExtraArgs={
                "ContentType": image.content_type,
                "ServerSideEncryption": self._server_side_encryption,
            },
        )

    async def create_download(self, *, object_key: str) -> ImageDownload:
        now = datetime.now(UTC)
        url = await self._call(
            self._client.generate_presigned_url,
            "get_object",
            Params={"Bucket": self._bucket, "Key": object_key},
            ExpiresIn=self._presigned_ttl_seconds,
        )
        return ImageDownload(
            url=url, expires_at=now + timedelta(seconds=self._presigned_ttl_seconds)
        )

    async def delete(self, *, object_key: str) -> None:
        await self._call(
            self._client.delete_object, Bucket=self._bucket, Key=object_key
        )

    @staticmethod
    async def _call(function, *args, **kwargs):
        try:
            return await asyncio.to_thread(function, *args, **kwargs)
        except (BotoCoreError, ClientError) as error:
            # 객체 키와 S3 오류 본문은 응답에 넣지 않는다.
            raise AppError(
                status_code=503,
                error_code="IMAGE_STORAGE_UNAVAILABLE",
                message="사진 저장소를 사용할 수 없습니다.",
                retryable=True,
            ) from error


class UnconfiguredImageStorage:
    """`SAEROK_IMAGE_S3_BUCKET`이 비었을 때 쓴다. 사진이 필요한 순간에 거절한다."""

    def object_key(self, *, photo_id: UUID, image: ValidatedImage) -> str:
        raise _not_configured()

    async def upload(
        self, *, object_key: str, file: BinaryIO, image: ValidatedImage
    ) -> None:
        raise _not_configured()

    async def create_download(self, *, object_key: str) -> ImageDownload:
        raise _not_configured()

    async def delete(self, *, object_key: str) -> None:
        raise _not_configured()


def _not_configured() -> AppError:
    return AppError(
        status_code=503,
        error_code="IMAGE_STORAGE_NOT_CONFIGURED",
        message="사진 저장소가 설정되지 않았습니다.",
    )
