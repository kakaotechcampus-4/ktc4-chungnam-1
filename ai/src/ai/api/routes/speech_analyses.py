from fastapi import APIRouter, Request

from ai.api.schemas import SpeechAnalysisRequest
from ai.stt.schemas import SpeechAnalysisResult
from ai.stt.service import SpeechAnalysisService


router = APIRouter(
    prefix="/internal/v1/speech-analyses",
    tags=["speech-analyses"],
)


@router.post(
    "",
    response_model=SpeechAnalysisResult,
    response_model_by_alias=True,
)
def run_stt_pipeline(
    payload: SpeechAnalysisRequest,
    request: Request,
) -> SpeechAnalysisResult:
    """요청의 음성 입력을 준비해 STT와 화자 분리 결과를 반환한다."""

    service: SpeechAnalysisService = request.app.state.speech_analysis_service
    return service.analyze(payload)
