from __future__ import annotations

import argparse
import asyncio
import logging

from app.clients.ai_server import AiServerClient
from app.core.config import Settings, get_settings
from app.core.logging import configure_logging
from app.services.audio_storage import S3AudioStorage
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import SpeechAnalysisWorker


logger = logging.getLogger("saerok.speech_worker")


def create_worker(settings: Settings) -> SpeechAnalysisWorker:
    if not settings.database_url or not settings.speech_audio_s3_bucket:
        raise RuntimeError(
            "음성 worker에는 SAEROK_DATABASE_URL과 "
            "SAEROK_SPEECH_AUDIO_S3_BUCKET이 필요합니다."
        )
    jobs = PostgresSpeechAnalysisJobRepository(settings.database_url)
    storage = S3AudioStorage(
        bucket=settings.speech_audio_s3_bucket,
        region=settings.speech_audio_s3_region,
        presigned_ttl_seconds=settings.speech_audio_presigned_ttl_seconds,
        server_side_encryption=settings.speech_audio_s3_encryption,
    )
    return SpeechAnalysisWorker(
        jobs=jobs,
        audio_storage=storage,
        ai_server=AiServerClient(
            base_url=settings.ai_server_url,
            timeout_seconds=settings.ai_server_timeout_seconds,
        ),
        # STT 연결 범위에서는 결과 수신과 원본 삭제 후 sttCompleted에서 멈춘다.
        # 리포트 계약이 연결되면 같은 worker에 ReportGenerator를 주입한다.
        report_generator=None,
        lease_seconds=settings.speech_analysis_lease_seconds,
    )


async def run_worker(*, once: bool) -> None:
    settings = get_settings()
    configure_logging(settings.log_level)
    worker = create_worker(settings)

    if once:
        processed = await worker.run_once()
        logger.info("speech_worker_once_complete processed=%s", processed)
        return

    logger.info("speech_worker_started")
    while True:
        try:
            processed = await worker.run_once()
        except Exception as error:
            # DB 및 SDK 예외 메시지에는 연결 문자열이나 객체 정보가 섞일 수 있어
            # 안전한 예외 종류만 기록한다.
            logger.error(
                "speech_worker_loop_failed error_type=%s",
                type(error).__name__,
            )
            processed = False
        if not processed:
            await asyncio.sleep(settings.speech_worker_poll_seconds)


def main() -> None:
    parser = argparse.ArgumentParser(description="새록 비동기 STT worker")
    parser.add_argument(
        "--once",
        action="store_true",
        help="대기 중인 작업을 최대 하나 처리하고 종료합니다.",
    )
    args = parser.parse_args()
    asyncio.run(run_worker(once=args.once))


if __name__ == "__main__":
    main()
