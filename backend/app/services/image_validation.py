"""프로필 사진(3-1)과 면회 사진(5-2) 업로드 검증.

앱이 보낸 Content-Type은 믿지 않고 파일 앞부분의 시그니처로 JPEG와 PNG를 가린다.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from fastapi import UploadFile

from app.core.errors import AppError

_READ_CHUNK_BYTES = 1024 * 1024
_JPEG_SIGNATURE = b"\xff\xd8\xff"
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


@dataclass(frozen=True)
class ValidatedImage:
    content_type: Literal["image/jpeg", "image/png"]
    extension: Literal["jpg", "png"]
    size_bytes: int


async def validate_image(image: UploadFile, *, max_size_bytes: int) -> ValidatedImage:
    """크기와 형식을 검사하고, 업로드에 다시 쓸 수 있게 파일을 처음으로 되감는다."""
    await image.seek(0)
    head = b""
    size_bytes = 0
    while chunk := await image.read(_READ_CHUNK_BYTES):
        if not head:
            head = chunk[: len(_PNG_SIGNATURE)]
        size_bytes += len(chunk)
        if size_bytes > max_size_bytes:
            raise AppError(
                status_code=413,
                error_code="IMAGE_TOO_LARGE",
                message="사진 파일이 허용된 크기를 초과했습니다.",
            )
    await image.seek(0)

    if head.startswith(_JPEG_SIGNATURE):
        return ValidatedImage("image/jpeg", "jpg", size_bytes)
    if head.startswith(_PNG_SIGNATURE):
        return ValidatedImage("image/png", "png", size_bytes)
    raise AppError(
        status_code=422,
        error_code="INVALID_IMAGE_FORMAT",
        message="JPEG 또는 PNG 사진만 올릴 수 있습니다.",
    )
