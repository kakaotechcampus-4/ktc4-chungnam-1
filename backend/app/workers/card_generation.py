from __future__ import annotations

from app.core.config import Settings
from app.core.database import connect
from app.services.card_generation_jobs import CardGenerationJob, CardGenerationQueue
from app.services.card_sets import CardGenerationProcessor, Generate
from app.workers.base import Worker, run_worker_main


def create_worker(settings: Settings, generate: Generate) -> Worker[CardGenerationJob]:
    if not settings.database_url or not settings.ml_api_key.get_secret_value():
        raise RuntimeError(
            "카드 생성 worker에는 SAEROK_DATABASE_URL과 SAEROK_ML_API_KEY가 필요합니다."
        )
    database_url = settings.database_url
    queue = CardGenerationQueue()
    return Worker(
        queue=queue,
        process=CardGenerationProcessor(queue=queue, generate=generate),
        open_connection=lambda: connect(database_url),
        lease_seconds=settings.card_generation_lease_seconds,
    )


def card_generator(settings: Settings) -> Generate:
    # 생성 함수(local_ai 카드 생성 패키지)는 AI 패키지 PR에서 연결
    raise RuntimeError("카드 생성 함수가 아직 연결되지 않았습니다.")


def main() -> None:
    run_worker_main(
        description="새록 카드 생성 worker",
        create_worker=lambda settings: create_worker(settings, card_generator(settings)),
        poll_seconds=lambda settings: settings.card_worker_poll_seconds,
    )


if __name__ == "__main__":
    main()
