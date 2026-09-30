from fastapi import APIRouter, Request

from app.clients.ai_server import AiServerClient
from app.schemas.speech_analysis import (
    SpeechAnalysisRequest,
    SpeechAnalysisResult,
)


router = APIRouter(
    prefix="/api/v1/speech-analyses",
    tags=["speech-analyses"],
)


@router.post(
    "",
    response_model=SpeechAnalysisResult,
    response_model_by_alias=True,
)
async def analyze_speech(
    payload: SpeechAnalysisRequest,
    request: Request,
) -> SpeechAnalysisResult:
    """요청을 AI 서버에 전달하고 검증된 분석 결과를 반환한다."""

    client: AiServerClient = request.app.state.ai_server_client
    return await client.analyze_speech(payload)
