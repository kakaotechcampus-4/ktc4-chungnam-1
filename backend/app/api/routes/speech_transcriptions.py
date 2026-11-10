from typing import Annotated

from fastapi import APIRouter, Depends, File, Request, UploadFile

from app.api.deps import (
    CurrentAccountDep, DbConnectionDep, SettingsDep, get_speech_audio_storage,
)
from app.core.errors import AppError
from app.services.account_slots import account_slot, server_slot
from app.services.audio_storage import AudioStorage
from app.services.speech_transcription import transcribe_short_audio

router = APIRouter(tags=["speech-transcriptions"])


@router.post("/api/v1/speech-transcriptions", summary="프로필 입력용 짧은 녹음을 글로 변환")
async def transcribe(
    account: CurrentAccountDep, connection: DbConnectionDep, settings: SettingsDep,
    request: Request, audio: Annotated[UploadFile, File()],
    storage: Annotated[AudioStorage, Depends(get_speech_audio_storage)],
) -> dict:
    # 한 요청이 STT 응답을 기다리는 동안 DB 연결과 STT 서버를 붙잡으므로, 같은 계정의
    # 동시 요청 수를 설정(기본 2)까지만 받는다(2026-11-09 PM 결정). 앱은 앞 전사가 끝나기
    # 전에 `건너뛰기`로 다음 항목을 녹음해 보낼 수 있어 2건까지 둔다. 넘으면 S3와 STT를
    # 부르지 않고 거절한다.
    async with account_slot(
        connection, scope="short-transcription", account_id=account.account_id,
        limit=settings.short_transcription_concurrency_per_account,
    ) as acquired:
        if not acquired:
            raise AppError(
                status_code=429, error_code="SPEECH_TRANSCRIPTION_IN_PROGRESS",
                message="앞서 보낸 음성을 아직 글로 옮기고 있습니다. 끝난 뒤 다시 보내 주세요.",
                retryable=True,
            )
        # 서버 전체 한도(설정했을 때만). 계정 한도를 통과한 요청만 센다. 다 차 있으면 STT
        # 앞에 줄 세우지 않고 바로 거절해, 앱의 2분 제한 안에 다시 보낼 수 있게 한다.
        async with server_slot(
            connection, scope="short-transcription",
            limit=settings.short_transcription_concurrency_total,
        ) as server_acquired:
            if not server_acquired:
                raise AppError(
                    status_code=503, error_code="SPEECH_TRANSCRIPTION_BUSY",
                    message="지금 음성을 글로 옮기는 요청이 많습니다. 잠시 뒤 다시 보내 주세요.",
                    retryable=True,
                )
            text = await transcribe_short_audio(
                connection, account=account, audio=audio, storage=storage,
                ai_server=request.app.state.ai_server_client,
                object_prefix=settings.speech_audio_s3_prefix,
                retention_seconds=settings.speech_audio_retention_seconds,
                timeout_seconds=min(
                    settings.short_transcription_timeout_seconds,
                    settings.ai_server_timeout_seconds,
                ),
                max_audio_bytes=settings.max_audio_bytes,
            )
    return {"schemaVersion": 1, "text": text}
