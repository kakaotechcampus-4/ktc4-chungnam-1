from typing import Annotated

from fastapi import APIRouter, File, Form, Path, UploadFile, status

from app.api.deps import CurrentAccountDep, SpeechSubmissionDep
from app.core.errors import AppError
from app.schemas.speech_analysis import (
    SpeechAnalysisAccepted,
    SpeechAnalysisStatusResponse,
)
from app.services.speech_analysis_jobs import SpeechAnalysisStatus


router = APIRouter(tags=["speech-analyses"])


@router.post(
    "/api/v1/visit-sessions/{session_id}/speech-analyses",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=SpeechAnalysisAccepted,
    response_model_by_alias=True,
)
async def submit_speech_analysis(
    account: CurrentAccountDep,
    submission: SpeechSubmissionDep,
    session_id: Annotated[str, Path(min_length=1, max_length=128)],
    audio: Annotated[UploadFile, File()],
    participant_count: Annotated[
        int,
        Form(alias="participantCount", ge=1, le=8),
    ],
) -> SpeechAnalysisAccepted:
    """면회 WAV를 안전하게 인수하고 비동기 분석 작업을 등록한다."""

    job = await submission.submit(
        account=account,
        session_id=session_id,
        participant_count=participant_count,
        audio=audio,
    )
    return SpeechAnalysisAccepted(
        analysisId=job.analysis_id,
        sessionId=job.session_id,
        status=job.status.value,
    )


@router.get(
    "/api/v1/speech-analyses/{analysis_id}",
    response_model=SpeechAnalysisStatusResponse,
    response_model_by_alias=True,
)
async def get_speech_analysis(
    account: CurrentAccountDep,
    submission: SpeechSubmissionDep,
    analysis_id: Annotated[str, Path(min_length=1, max_length=128)],
) -> SpeechAnalysisStatusResponse:
    """요청 계정이 소유한 음성 분석 작업의 안전한 상태만 반환한다."""

    job = await submission.get(
        account=account,
        analysis_id=analysis_id,
    )
    if job.status == SpeechAnalysisStatus.UPLOADING:
        # analysisId는 202 이전에 외부로 제공하지 않으므로 정상 공개 상태가 아니다.
        raise AppError(
            status_code=409,
            error_code="ANALYSIS_SUBMISSION_IN_PROGRESS",
            message="음성 분석 작업을 접수하고 있습니다.",
            retryable=True,
        )
    return SpeechAnalysisStatusResponse(
        analysisId=job.analysis_id,
        sessionId=job.session_id,
        status=job.status.value,
        errorCode=job.error_code,
    )
