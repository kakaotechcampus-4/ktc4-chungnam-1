from __future__ import annotations

from contextlib import ExitStack
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Lock
from typing import Protocol
from uuid import uuid4

from stt_server.progress import progress

from stt_server.api.schemas import SpeechAnalysisRequest
from stt_server.audio.providers import AudioSourceError, AudioSourceResolver
from stt_server.audio.validation import validate_wav
from stt_server.stt.alignment import align_asr_and_diarization
from stt_server.stt.schemas import AsrResult, DiarizationResult, SpeechAnalysisResult


class AsrEngine(Protocol):
    def transcribe(
        self,
        analysis_id: str,
        audio_path: Path,
        language: str,
    ) -> AsrResult:
        ...


class DiarizationEngine(Protocol):
    def diarize(
        self,
        audio_path: Path,
        speaker_count: int,
    ) -> DiarizationResult:
        ...


@dataclass(frozen=True)
class SpeechAnalysisArtifacts:
    """로컬 fixture 생성에서 재사용할 모델별 결과와 결합 결과."""

    asr: AsrResult
    diarization: DiarizationResult
    combined: SpeechAnalysisResult


class SpeechAnalysisService:
    """음성 준비부터 두 모델 실행과 결과 결합까지 조율한다."""

    def __init__(
        self,
        *,
        audio_sources: AudioSourceResolver,
        asr: AsrEngine,
        diarization: DiarizationEngine,
    ) -> None:
        self._audio_sources = audio_sources
        self._asr = asr
        self._diarization = diarization
        self._inference_lock = Lock()

    def analyze(self, payload: SpeechAnalysisRequest) -> SpeechAnalysisResult:
        return self.analyze_with_artifacts(payload).combined

    def analyze_with_artifacts(
        self,
        payload: SpeechAnalysisRequest,
    ) -> SpeechAnalysisArtifacts:
        trace = uuid4().hex
        with progress("pipeline", trace):
            return self._analyze_with_artifacts(payload, trace)

    def _analyze_with_artifacts(
        self, payload: SpeechAnalysisRequest, trace: str,
    ) -> SpeechAnalysisArtifacts:
        now = datetime.now(timezone.utc)
        if (
            payload.data_expires_at is not None
            and payload.data_expires_at <= now
        ):
            raise AudioSourceError("음성 데이터의 처리 기한이 만료되었습니다.")
        if (
            payload.data_expires_at is not None
            and payload.data_expires_at > now + timedelta(hours=24)
        ):
            raise AudioSourceError(
                "음성 데이터의 처리 기한은 24시간을 넘을 수 없습니다."
            )

        with ExitStack() as resources:
            with progress("audio_prepare", trace):
                audio_path = resources.enter_context(
                    self._audio_sources.materialize(payload.audio_source)
                )
                validate_wav(audio_path)

            # 두 런타임은 같은 GPU와 모델 인스턴스를 공유하므로
            # 한 번에 한 요청만 실행한다.
            with progress("inference_wait", trace):
                resources.enter_context(self._inference_lock)
            with progress("asr", trace):
                asr_result = self._asr.transcribe(
                    analysis_id=payload.analysis_id,
                    audio_path=audio_path,
                    language=payload.language,
                )
            with progress("diarization", trace):
                diarization_result = self._diarization.diarize(
                    audio_path=audio_path,
                    speaker_count=payload.speaker_count,
                )

        with progress("alignment", trace):
            combined_result = align_asr_and_diarization(
                asr_result,
                diarization_result,
            )
        return SpeechAnalysisArtifacts(
            asr=asr_result,
            diarization=diarization_result,
            combined=combined_result,
        )
