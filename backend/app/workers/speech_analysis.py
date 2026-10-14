from __future__ import annotations

from app.clients.ai_server import AiServerClient
from app.core.config import Settings
from app.core.database import connect
from app.services.audio_storage import S3AudioStorage
from app.services.speech_analysis_jobs import (
    PostgresSpeechAnalysisJobRepository,
    SpeechAnalysisJob,
)
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import VisitReportGenerator
from app.workers.base import Worker, run_worker_main


def create_worker(settings: Settings) -> Worker[SpeechAnalysisJob]:
    if not settings.database_url or not settings.speech_audio_s3_bucket:
        raise RuntimeError(
            "음성 worker에는 SAEROK_DATABASE_URL과 "
            "SAEROK_SPEECH_AUDIO_S3_BUCKET이 필요합니다."
        )
    database_url = settings.database_url
    lease_seconds = settings.speech_analysis_lease_seconds
    ai_server = AiServerClient(
        base_url=settings.ai_server_url,
        timeout_seconds=settings.ai_server_timeout_seconds,
    )
    return create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=lease_seconds
        ),
        audio_storage=S3AudioStorage(
            bucket=settings.speech_audio_s3_bucket,
            region=settings.speech_audio_s3_region,
            presigned_ttl_seconds=settings.speech_audio_presigned_ttl_seconds,
            server_side_encryption=settings.speech_audio_s3_encryption,
        ),
        ai_server=ai_server,
        open_connection=lambda: connect(database_url),
        lease_seconds=lease_seconds,
        # STT 뒤 같은 작업에서 리포트(8-3)까지 만든다.
        report_generator=VisitReportGenerator(ai_server=ai_server),
    )


def main() -> None:
    run_worker_main(
        description="새록 비동기 STT worker",
        create_worker=create_worker,
        poll_seconds=lambda settings: settings.speech_worker_poll_seconds,
    )


if __name__ == "__main__":
    main()
