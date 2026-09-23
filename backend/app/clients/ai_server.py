from __future__ import annotations

import httpx

from app.core.errors import AppError
from app.schemas.speech_analysis import (
    SpeechAnalysisRequest,
    SpeechAnalysisResult,
)


class AiServerClient:
    """내부 AI 서버의 음성 분석 API를 호출한다."""

    def __init__(
        self,
        *,
        base_url: str,
        timeout_seconds: float,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)
        self._transport = transport

    async def analyze_speech(
        self,
        payload: SpeechAnalysisRequest,
    ) -> SpeechAnalysisResult:
        try:
            async with httpx.AsyncClient(
                base_url=self._base_url,
                timeout=self._timeout,
                transport=self._transport,
            ) as client:
                response = await client.post(
                    "/internal/v1/speech-analyses",
                    json=payload.model_dump(
                        mode="json",
                        by_alias=True,
                        exclude_none=True,
                    ),
                )
        except httpx.TimeoutException as error:
            raise AppError(
                status_code=504,
                error_code="AI_SERVER_TIMEOUT",
                message="음성 분석 서버의 응답 시간이 초과되었습니다.",
                retryable=True,
            ) from error
        except httpx.RequestError as error:
            raise AppError(
                status_code=503,
                error_code="AI_SERVER_UNAVAILABLE",
                message="음성 분석 서버에 연결할 수 없습니다.",
                retryable=True,
            ) from error

        if not response.is_success:
            raise AppError(
                status_code=502,
                error_code="AI_SERVER_ERROR",
                message="음성 분석 서버가 요청을 처리하지 못했습니다.",
                retryable=response.status_code >= 500,
            )

        try:
            result = SpeechAnalysisResult.model_validate(response.json())
        except ValueError as error:
            raise AppError(
                status_code=502,
                error_code="INVALID_AI_RESPONSE",
                message="음성 분석 서버의 응답 형식이 올바르지 않습니다.",
            ) from error

        if result.analysis_id != payload.analysis_id:
            raise AppError(
                status_code=502,
                error_code="INVALID_AI_RESPONSE",
                message="음성 분석 서버의 응답 형식이 올바르지 않습니다.",
            )
        return result
