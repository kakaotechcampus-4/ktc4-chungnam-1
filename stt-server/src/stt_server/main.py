import os
from pathlib import Path

from fastapi import FastAPI
import uvicorn

from stt_server.progress import configure_logging, progress

configure_logging()

from stt_server.api.router import api_router
from stt_server.audio.providers import (
    DEFAULT_LOCAL_AUDIO_DIRECTORY,
    AudioSourceResolver,
    LocalAudioProvider,
    S3AudioProvider,
)
from stt_server.stt.diarization import DiarizationRuntime
from stt_server.stt.runtime import AsrRuntime
from stt_server.stt.service import SpeechAnalysisService

os.environ["PYANNOTE_METRICS_ENABLED"] = "0"

import torch
from pyannote.audio import Pipeline


SERVICE_NAME = "saerok-stt-server"
SERVICE_VERSION = "0.1.0"

# asr_runtime is a singleton instance of AsrRuntime that is initialized when the FastAPI app starts.
asr_runtime: AsrRuntime | None = None


def _get_asr_runtime() -> AsrRuntime:
    """Returns a singleton instance of AsrRuntime. If it doesn't exist, it creates one."""

    global asr_runtime

    if asr_runtime is None:
        with progress("asr_model_load"):
            asr_runtime = AsrRuntime()

    return asr_runtime

diarization_pipeline: Pipeline | None = None


def _get_diarization_pipeline() -> Pipeline:
    """Returns a singleton instance of the pyannote.audio Pipeline for speaker diarization."""

    global diarization_pipeline
    if diarization_pipeline is None:
        with progress("diarization_model_load"):
            diarization_pipeline = Pipeline.from_pretrained(
                "pyannote/speaker-diarization-community-1",
            )
            device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
            diarization_pipeline.to(device)

    return diarization_pipeline

def _read_bool_environment(name: str, default: bool) -> bool:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _read_allowed_s3_host_suffixes() -> tuple[str, ...]:
    raw_value = os.getenv("SAEROK_S3_ALLOWED_HOST_SUFFIXES", "amazonaws.com")
    values = tuple(value.strip() for value in raw_value.split(",") if value.strip())
    if not values:
        raise RuntimeError("SAEROK_S3_ALLOWED_HOST_SUFFIXES가 비어 있습니다.")
    return values


def _create_audio_source_resolver() -> AudioSourceResolver:
    environment = os.getenv("SAEROK_ENVIRONMENT", "development").strip().lower()
    local_default = environment in {"development", "test"}
    allow_local_audio = _read_bool_environment(
        "SAEROK_ALLOW_LOCAL_AUDIO",
        local_default,
    )
    local_audio_directory = Path(
        os.getenv(
            "SAEROK_LOCAL_AUDIO_DIRECTORY",
            str(DEFAULT_LOCAL_AUDIO_DIRECTORY),
        )
    )
    max_audio_bytes = int(
        os.getenv("SAEROK_MAX_AUDIO_BYTES", str(512 * 1024 * 1024))
    )

    return AudioSourceResolver(
        {
            "s3PresignedGet": S3AudioProvider(
                allowed_host_suffixes=_read_allowed_s3_host_suffixes(),
                max_size_bytes=max_audio_bytes,
            ),
            "localFile": LocalAudioProvider(
                local_audio_directory,
                enabled=allow_local_audio,
            ),
        }
    )


def _create_app() -> FastAPI:
    app = FastAPI(
        title=SERVICE_NAME,
        version=SERVICE_VERSION,
        description="새록의 STT와 화자 분리 파이프라인을 실행하는 내부 서버",
    )
    app.include_router(api_router)
    application_asr_runtime = _get_asr_runtime()
    application_diarization_runtime = DiarizationRuntime(
        _get_diarization_pipeline()
    )
    app.state.speech_analysis_service = SpeechAnalysisService(
        audio_sources=_create_audio_source_resolver(),
        asr=application_asr_runtime,
        diarization=application_diarization_runtime,
    )
    return app


app = _create_app()


def run() -> None:
    uvicorn.run(
        "stt_server.main:app",
        host="127.0.0.1",
        port=8001,
        workers=1,
        access_log=False,
    )
