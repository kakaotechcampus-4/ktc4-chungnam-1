from fastapi import FastAPI

from app.api.router import api_router
from app.clients.ai_server import AiServerClient
from app.core.config import get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, install_request_logging
from app.services.audio_storage import S3AudioStorage
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import SpeechAnalysisSubmissionService


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    application = FastAPI(
        title=settings.service_name,
        version=settings.service_version,
        description="Flutter 연동과 Python 처리 파이프라인 검증을 위한 로컬 기준 환경",
    )
    register_exception_handlers(application)
    install_request_logging(application)
    application.state.ai_server_client = AiServerClient(
        base_url=settings.ai_server_url,
        timeout_seconds=settings.ai_server_timeout_seconds,
    )
    application.state.speech_analysis_submission = None
    application.state.speech_analysis_jobs = None
    application.state.speech_audio_storage = None
    if settings.database_url and settings.speech_audio_s3_bucket:
        jobs = PostgresSpeechAnalysisJobRepository(settings.database_url)
        audio_storage = S3AudioStorage(
            bucket=settings.speech_audio_s3_bucket,
            region=settings.speech_audio_s3_region,
            presigned_ttl_seconds=settings.speech_audio_presigned_ttl_seconds,
            server_side_encryption=settings.speech_audio_s3_encryption,
        )
        application.state.speech_analysis_jobs = jobs
        application.state.speech_audio_storage = audio_storage
        application.state.speech_analysis_submission = (
            SpeechAnalysisSubmissionService(
                jobs=jobs,
                audio_storage=audio_storage,
                max_audio_bytes=settings.max_audio_bytes,
                retention_seconds=settings.speech_audio_retention_seconds,
                object_prefix=settings.speech_audio_s3_prefix,
            )
        )
    application.include_router(api_router)
    return application


app = create_app()
