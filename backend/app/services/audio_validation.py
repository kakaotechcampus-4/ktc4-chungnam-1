from __future__ import annotations

import asyncio
from dataclasses import dataclass
import hashlib
from typing import BinaryIO
import wave

from fastapi import UploadFile

from app.core.errors import AppError


_READ_CHUNK_BYTES = 1024 * 1024


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
    while chunk := await audio.read(_READ_CHUNK_BYTES):
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
        # 음성 데이터를 끝까지 읽으므로 큰 파일에서 이벤트 루프를 막지 않게 한다.
        valid, intact = await asyncio.to_thread(_inspect_wav, audio.file)
    finally:
        await audio.seek(0)

    if not valid:
        raise AppError(
            status_code=422,
            error_code="INVALID_AUDIO_FORMAT",
            message="음성은 WAV/PCM 16-bit/16kHz/mono 형식이어야 합니다.",
        )
    if not intact:
        raise AppError(
            status_code=422,
            error_code="INVALID_AUDIO",
            message="음성 데이터가 손상되었거나 일부가 없습니다.",
        )

    return ValidatedAudio(size_bytes=size_bytes, sha256=digest.hexdigest())


def _inspect_wav(file: BinaryIO) -> tuple[bool, bool]:
    """WAV 규격이 맞는지와 헤더가 선언한 음성 데이터가 실제로 모두 있는지 본다."""

    try:
        with wave.open(file, "rb") as wav:
            valid = (
                wav.getcomptype() == "NONE"
                and wav.getsampwidth() == 2
                and wav.getframerate() == 16_000
                and wav.getnchannels() == 1
                and wav.getnframes() > 0
            )
            if not valid:
                return False, False

            # getnframes()는 헤더의 선언값일 뿐이다. 헤더만 있거나 중간에 잘린
            # 파일도 선언값은 정상이므로 실제 바이트를 끝까지 읽어 비교한다.
            # 파일 전체 크기와 비교하지 않는다. data 뒤에 다른 청크가 붙을 수 있다.
            frame_bytes = wav.getsampwidth() * wav.getnchannels()
            declared_bytes = wav.getnframes() * frame_bytes
            frames_per_read = _READ_CHUNK_BYTES // frame_bytes
            actual_bytes = 0
            while data := wav.readframes(frames_per_read):
                actual_bytes += len(data)
            return True, actual_bytes >= declared_bytes
    except (EOFError, wave.Error):
        return False, False
