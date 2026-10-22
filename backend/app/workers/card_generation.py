from __future__ import annotations

import card_generation as ai
from pydantic import ValidationError

from app.core.config import Settings
from app.core.database import connect
from app.schemas.card_generation import CardGenerationRequest, CardGenerationResult
from app.services.card_generation_jobs import CardGenerationJob, CardGenerationQueue
from app.services.card_sets import CardGenerationError, CardGenerationProcessor, Generate
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
    """ai 카드 생성 패키지(`ai/card_generation`)의 `generate_cards`를 BE 형식으로 감싼 생성 함수."""
    api_key = settings.ml_api_key.get_secret_value()
    if not api_key:
        raise RuntimeError("카드 생성에는 SAEROK_ML_API_KEY가 필요합니다.")

    def generate(request: CardGenerationRequest) -> CardGenerationResult:
        # 두 쪽 형식은 JSON 이름이 같음. UUID는 JSON에서 문자열로 바뀜
        try:
            sent = ai.GenerationRequest.model_validate(request.model_dump(mode="json", by_alias=True))
        except ValidationError as error:
            raise CardGenerationError("INVALID_CONTEXT", "생성 함수가 요청 형식을 받지 않음") from error
        try:
            result = ai.generate_cards(sent, api_key=api_key)
        except ai.CardGenerationError as error:
            # 실패 코드를 card_sets.error_code에 그대로 남김
            raise CardGenerationError(error.code, error.message) from error
        try:
            return CardGenerationResult.model_validate(result.model_dump(mode="json", by_alias=True))
        except ValidationError as error:
            raise CardGenerationError("INVALID_GENERATION_RESULT", "생성 결과가 BE 형식과 다름") from error

    return generate


def main() -> None:
    run_worker_main(
        description="새록 카드 생성 worker",
        create_worker=lambda settings: create_worker(settings, card_generator(settings)),
        poll_seconds=lambda settings: settings.card_worker_poll_seconds,
    )


if __name__ == "__main__":
    main()
