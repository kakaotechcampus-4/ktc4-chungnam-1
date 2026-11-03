"""#138의 프로필 입력용 전사. 회차와 전사 DB 저장 없이 텍스트를 돌려준다."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
import logging
from uuid import uuid4
import wave

from fastapi import UploadFile

from app.clients.ai_server import AiServerClient
from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisRequest
from app.services.accounts import Account
from app.services.audio_storage import AudioStorage
from app.services.audio_validation import validate_visit_audio
from app.services.speech_analysis_pipeline import SpeechAnalysisSubmissionService
from app.services.deployment_control import short_speech_admission

logger = logging.getLogger("saerok.speech_transcription")
MAX_SECONDS = 300
# 합의한 5분 PCM은 9.6 MB다. 헤더 여유를 포함하며 면회 업로드 상한을 늘리지 않는다.
MAX_BYTES = 10 * 1024 * 1024


async def transcribe_short_audio(
    connection: DbConnection, *, account: Account, audio: UploadFile,
    storage: AudioStorage, ai_server: AiServerClient, object_prefix: str,
    retention_seconds: int, timeout_seconds: float, max_audio_bytes: int,
) -> str:
    SpeechAnalysisSubmissionService._assert_account_consents(account)
    async with short_speech_admission(connection):
        return await _transcribe_short_audio(
            connection, audio=audio, storage=storage, ai_server=ai_server,
            object_prefix=object_prefix, retention_seconds=retention_seconds,
            timeout_seconds=timeout_seconds, max_audio_bytes=max_audio_bytes,
        )


async def _transcribe_short_audio(
    connection, *, audio, storage, ai_server, object_prefix,
    retention_seconds, timeout_seconds, max_audio_bytes,
):
    validated = await validate_visit_audio(audio, max_size_bytes=min(max_audio_bytes, MAX_BYTES))
    with wave.open(audio.file, "rb") as wav:
        seconds = wav.getnframes() / wav.getframerate()
    await audio.seek(0)
    if seconds > MAX_SECONDS:
        raise AppError(status_code=413, error_code="AUDIO_TOO_LARGE",
                       message="음성 입력은 5분까지 보낼 수 있습니다.")

    analysis_id = str(uuid4())
    key = f"{object_prefix.strip('/')}/{analysis_id}.wav"
    expires_at = datetime.now(UTC) + timedelta(seconds=retention_seconds)
    # 업로드 직후 프로세스가 종료돼도 정리할 키는 남는다. 처리 중 조기 삭제는 막는다.
    await connection.execute(
        "INSERT INTO storage_deletion_request_queue (s3_object_key, not_before) VALUES (%s,%s)",
        (key, expires_at),
    )
    try:
        try:
            # S3 업로드 스레드가 살아 있는 채로 삭제하면 뒤늦게 원본이 다시 생길 수 있다.
            uploading = asyncio.create_task(storage.upload(object_key=key, file=audio.file))
            try:
                await asyncio.shield(uploading)
            except asyncio.CancelledError:
                await uploading
                raise
            download = await storage.create_download(object_key=key, expires_at=expires_at)
        except Exception as error:
            raise AppError(status_code=503, error_code="AUDIO_STORAGE_UNAVAILABLE",
                           message="음성을 임시 저장하지 못했습니다.", retryable=True) from error

        payload = SpeechAnalysisRequest(
            schemaVersion=1, analysisId=analysis_id, language="ko", speakerCount=1,
            audioSource={
                "type": "s3PresignedGet", "downloadUrl": download.url,
                "downloadUrlExpiresAt": download.expires_at,
                "sizeBytes": validated.size_bytes, "sha256": validated.sha256,
            }, dataExpiresAt=expires_at,
        )
        try:
            result = await asyncio.wait_for(
                ai_server.analyze_speech(payload),
                timeout=min(timeout_seconds, max(0.0, (expires_at - datetime.now(UTC)).total_seconds())),
            )
        except TimeoutError as error:
            raise AppError(status_code=504, error_code="AI_SERVER_TIMEOUT",
                           message="음성을 글로 옮기는 시간이 초과되었습니다.", retryable=True) from error
        # 빈 문자열 판정 이외의 인식 임계값은 AI 담당자 결정과 실측이 필요하다.
        return result.text.strip()
    finally:
        cleanup = asyncio.create_task(_cleanup(connection, storage, key))
        try:
            await asyncio.shield(cleanup)
        except asyncio.CancelledError:
            await cleanup
            raise


async def _cleanup(connection, storage, key):
    try:
        await connection.execute(
            "UPDATE storage_deletion_request_queue SET not_before=now() WHERE s3_object_key=%s",
            (key,),
        )
    except Exception:
        # 최초 만료 시각의 큐가 남아 있다. 예외와 파일 주소는 로그에 쓰지 않는다.
        logger.warning("short_speech_cleanup_schedule_failed")
    try:
        await storage.delete(object_key=key)
    except Exception:
        logger.warning("short_speech_deletion_pending")
    # 성공 응답만으로 실제 삭제를 확정하지 않는다. 삭제 실행기가 HEAD 404를 확인한 뒤
    # 큐를 제거한다. 전사 성공 여부와 삭제 실패를 섞지 않는다.
