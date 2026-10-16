from __future__ import annotations

import argparse

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


def create_worker(settings: Settings, *, stt_only: bool = False) -> Worker[SpeechAnalysisJob]:
    if stt_only and settings.environment not in {"development", "test"}:
        raise RuntimeError("--stt-only는 development/test 환경에서만 사용할 수 있습니다.")
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
        report_generator=None if stt_only else VisitReportGenerator(ai_server=ai_server),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="새록 비동기 STT worker")
    parser.add_argument(
        "--stt-only", action="store_true",
        help="개발·테스트용: 리포트를 생성하지 않고 sttCompleted에서 멈춥니다.",
    )
    # 공통 진입점이 --once를 추가하고 동일한 Namespace에 인수를 파싱한다.
    arguments = argparse.Namespace()
    run_worker_main(
        description="새록 비동기 STT worker",
        create_worker=lambda settings: create_worker(settings, stt_only=arguments.stt_only),
        poll_seconds=lambda settings: settings.speech_worker_poll_seconds,
        parser=parser,
        namespace=arguments,
    )


if __name__ == "__main__":
    main()
