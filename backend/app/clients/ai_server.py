from __future__ import annotations

import asyncio
import logging

import httpx

from app.core.errors import AppError
from app.schemas.speech_analysis import (
    SpeechAnalysisRequest,
    SpeechAnalysisResult,
)


logger = logging.getLogger("saerok.ai_server")


class AiServerClient:
    """내부 AI 서버의 음성 분석 API를 호출한다."""

    def __init__(
        self,
        *,
        base_url: str,
        timeout_seconds: float,
        backup_base_url: str | None = None,
        failover_connect_timeout_seconds: float = 5.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)
        self._timeout_seconds = timeout_seconds
        self._backup_base_url = (
            backup_base_url.strip().rstrip("/") if backup_base_url else None
        )
        if self._backup_base_url:
            try:
                backup = httpx.URL(self._backup_base_url)
                primary = httpx.URL(self._base_url)
            except httpx.InvalidURL:
                raise ValueError("STT 서버 주소 형식을 확인해야 합니다.") from None
            if backup.scheme not in {"http", "https"} or not backup.host:
                raise ValueError("STT 예비 서버에는 HTTP 또는 HTTPS 주소가 필요합니다.")
            if backup == primary:
                raise ValueError("기본 STT 서버와 예비 서버는 달라야 합니다.")
            if backup.userinfo or backup.query or backup.fragment:
                raise ValueError("STT 예비 서버 주소에 인증값, 쿼리나 fragment를 넣지 않습니다.")
        if failover_connect_timeout_seconds <= 0:
            raise ValueError("STT 연결 제한 시간은 양수여야 합니다.")
        self._failover_timeout = httpx.Timeout(
            timeout_seconds,
            connect=min(failover_connect_timeout_seconds, timeout_seconds),
        )
        self._transport = transport

    async def analyze_speech(
        self,
        payload: SpeechAnalysisRequest,
    ) -> SpeechAnalysisResult:
        try:
            if self._backup_base_url:
                # 두 시도가 하나의 제한 시간을 공유한다. worker 임대를 늘리지 않는다.
                async with asyncio.timeout(self._timeout_seconds):
                    try:
                        response = await self._post(
                            self._base_url, payload, self._failover_timeout
                        )
                    except (httpx.ConnectError, httpx.ConnectTimeout):
                        # 요청을 보내기 전 연결 실패만 전환한다. 응답 대기 중 재전송하면
                        # 기본 서버가 같은 음성을 아직 처리하고 있을 수 있다.
                        logger.warning("speech_analysis_backup_used reason=connect_failure")
                        response = await self._post(
                            self._backup_base_url, payload, self._failover_timeout
                        )
            else:
                response = await self._post(self._base_url, payload, self._timeout)
        except (httpx.TimeoutException, TimeoutError) as error:
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

    async def _post(
        self,
        base_url: str,
        payload: SpeechAnalysisRequest,
        timeout: httpx.Timeout,
    ) -> httpx.Response:
        async with httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            transport=self._transport,
        ) as client:
            return await client.post(
                "/internal/v1/speech-analyses",
                json=payload.model_dump(mode="json", by_alias=True, exclude_none=True),
            )
