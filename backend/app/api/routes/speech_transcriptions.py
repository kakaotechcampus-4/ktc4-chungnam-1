from typing import Annotated

from fastapi import APIRouter, Depends, File, Request, UploadFile

from app.api.deps import (
    CurrentAccountDep, DbConnectionDep, SettingsDep, get_speech_audio_storage,
)
from app.services.audio_storage import AudioStorage
from app.services.speech_transcription import transcribe_short_audio

router = APIRouter(tags=["speech-transcriptions"])


@router.post("/api/v1/speech-transcriptions", summary="프로필 입력용 짧은 녹음을 글로 변환")
async def transcribe(
    account: CurrentAccountDep, connection: DbConnectionDep, settings: SettingsDep,
    request: Request, audio: Annotated[UploadFile, File()],
    storage: Annotated[AudioStorage, Depends(get_speech_audio_storage)],
) -> dict:
    text = await transcribe_short_audio(
        connection, account=account, audio=audio, storage=storage,
        ai_server=request.app.state.ai_server_client,
        object_prefix=settings.speech_audio_s3_prefix,
        retention_seconds=settings.speech_audio_retention_seconds,
        timeout_seconds=settings.ai_server_timeout_seconds,
        max_audio_bytes=settings.max_audio_bytes,
    )
    return {"schemaVersion": 1, "text": text}
