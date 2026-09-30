from __future__ import annotations

from dataclasses import dataclass
import hashlib
import wave

from fastapi import UploadFile

from app.core.errors import AppError


@dataclass(frozen=True)
class ValidatedAudio:
    size_bytes: int
    sha256: str


async def validate_visit_audio(
    audio: UploadFile,
    *,
    max_size_bytes: int,
) -> ValidatedAudio:
    """업로드를 다시 사용 가능하게 되감으면서 크기·해시·WAV 규격을 검사한다."""

    digest = hashlib.sha256()
    size_bytes = 0
    await audio.seek(0)
    while chunk := await audio.read(1024 * 1024):
        size_bytes += len(chunk)
        if size_bytes > max_size_bytes:
            raise AppError(
                status_code=413,
                error_code="AUDIO_TOO_LARGE",
                message="음성 파일이 허용된 크기를 초과했습니다.",
            )
        digest.update(chunk)

    if size_bytes == 0:
        raise AppError(
            status_code=422,
            error_code="INVALID_AUDIO",
            message="비어 있는 음성 파일은 처리할 수 없습니다.",
        )

    await audio.seek(0)
    try:
        with wave.open(audio.file, "rb") as wav:
            valid = (
                wav.getcomptype() == "NONE"
                and wav.getsampwidth() == 2
                and wav.getframerate() == 16_000
                and wav.getnchannels() == 1
                and wav.getnframes() > 0
            )
    except (EOFError, wave.Error):
        valid = False
    finally:
        await audio.seek(0)

    if not valid:
        raise AppError(
            status_code=422,
            error_code="INVALID_AUDIO_FORMAT",
            message="음성은 WAV/PCM 16-bit/16kHz/mono 형식이어야 합니다.",
        )

    return ValidatedAudio(size_bytes=size_bytes, sha256=digest.hexdigest())
