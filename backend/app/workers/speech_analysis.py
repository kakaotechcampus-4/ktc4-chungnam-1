from __future__ import annotations

import proposal_generation
import report_generation
from common import visit_report as ai
from pydantic import ValidationError

from app.clients.ai_server import AiServerClient
from app.core.config import Settings
from app.core.database import connect
from app.schemas.visit_report_generation import VisitReportRequest, VisitReportResult
from app.services.audio_storage import S3AudioStorage
from app.services.speech_analysis_jobs import (
    PostgresSpeechAnalysisJobRepository,
    SpeechAnalysisJob,
)
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import (
    GenerateReport,
    VisitReportGenerator,
    generation_failed,
    parse_result,
)
from app.workers.base import Worker, run_worker_main


def create_worker(settings: Settings, generate: GenerateReport) -> Worker[SpeechAnalysisJob]:
    if not settings.database_url or not settings.speech_audio_s3_bucket:
        raise RuntimeError(
            "음성 worker에는 SAEROK_DATABASE_URL과 "
            "SAEROK_SPEECH_AUDIO_S3_BUCKET이 필요합니다."
        )
    database_url = settings.database_url
    lease_seconds = settings.speech_analysis_lease_seconds
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
        ai_server=AiServerClient(
            base_url=settings.ai_server_url,
            timeout_seconds=settings.ai_server_timeout_seconds,
        ),
        open_connection=lambda: connect(database_url),
        lease_seconds=lease_seconds,
        # STT 뒤 같은 작업에서 리포트(8-3)까지 만든다.
        report_generator=VisitReportGenerator(generate=generate),
    )


def report_generator(settings: Settings) -> GenerateReport:
    """ai 패키지의 리포트·변경 제안 생성 함수를 8-3 형식으로 감싼 생성 함수.

    리포트와 변경 제안을 차례로 만들고 `combine`으로 8-3 응답 하나로 합친다.
    """
    api_key = settings.ml_api_key.get_secret_value()
    if not api_key:
        raise RuntimeError("리포트 생성에는 SAEROK_ML_API_KEY가 필요합니다.")
    model = settings.report_generation_model

    def generate(request: VisitReportRequest) -> VisitReportResult:
        # 두 쪽 형식은 JSON 이름이 같음. UUID는 JSON에서 문자열로 바뀜
        try:
            sent = ai.VisitReportRequest.model_validate(
                request.model_dump(mode="json", by_alias=True)
            )
        except ValidationError as error:
            raise generation_failed("INVALID_REQUEST") from error
        try:
            report = report_generation.generate_report(sent, model=model, api_key=api_key)
            proposals = proposal_generation.generate_proposals(
                sent, model=model, api_key=api_key
            )
        except ai.VisitReportError as error:
            raise generation_failed(error.code) from error
        result = ai.combine(sent.analysis_id, report, proposals)
        return parse_result(result.model_dump(mode="json", by_alias=True), request)

    return generate


def main() -> None:
    run_worker_main(
        description="새록 비동기 STT worker",
        create_worker=lambda settings: create_worker(settings, report_generator(settings)),
        poll_seconds=lambda settings: settings.speech_worker_poll_seconds,
    )


if __name__ == "__main__":
    main()
