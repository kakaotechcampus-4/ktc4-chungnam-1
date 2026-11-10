from __future__ import annotations

import argparse

import proposal_generation
import report_generation
from common import visit_report as ai
from common.llm import ENDPOINTS
from pydantic import ValidationError

from app.clients.ai_server import AiServerClient
from app.clients.fcm import FcmClient, ServiceAccount
from app.core.config import Settings
from app.core.database import connect
from app.schemas.visit_report_generation import (
    GenerationCounts,
    VisitReportRequest,
    VisitReportResult,
)
from app.services.audio_storage import S3AudioStorage
from app.services.report_notifications import PushReportNotifier, ReportNotifier
from app.services.speech_analysis_jobs import (
    PostgresSpeechAnalysisJobRepository,
    SpeechAnalysisJob,
)
from app.services.speech_analysis_pipeline import (
    create_speech_worker,
    remove_stale_work_dirs,
)
from app.services.visit_report_generator import (
    GenerateReport,
    ReportDeadline,
    VisitReportGenerator,
    generation_failed,
    parse_result,
)
from app.workers.base import Worker, run_worker_main

# 리포트 생성 제한 시간이 끝난 뒤 저장과 완료 처리에 남겨 둘 임대 시간.
REPORT_SAVE_MARGIN_SECONDS = 60
# STT 호출 제한 시간이 끝난 뒤 남겨 둘 임대 시간. 30분 조각은 임대를 늘린 뒤 조각 파일 쓰기와
# 업로드(약 57.6 MB), STT 호출, 조각 삭제를 하고, 마지막 조각이면 전사 저장까지 같은 임대 안에서
# 한다. 30분 이하 녹음의 한 번 호출과 전사 저장도 같다.
STT_CALL_MARGIN_SECONDS = 60


def create_worker(
    settings: Settings,
    *,
    stt_only: bool = False,
    generate: GenerateReport | None = None,
) -> Worker[SpeechAnalysisJob]:
    """음성 worker. 기본은 STT 뒤 리포트까지 만들고, `stt_only`면 `sttCompleted`에서 멈춘다.

    `generate`를 넘기지 않으면 `report_generator(settings)`를 쓴다(ML API 키 필요).
    """
    if stt_only and settings.environment not in {"development", "test"}:
        raise RuntimeError("--stt-only는 development/test 환경에서만 사용할 수 있습니다.")
    if not settings.database_url or not settings.speech_audio_s3_bucket:
        raise RuntimeError(
            "음성 worker에는 SAEROK_DATABASE_URL과 "
            "SAEROK_SPEECH_AUDIO_S3_BUCKET이 필요합니다."
        )
    database_url = settings.database_url
    lease_seconds = settings.speech_analysis_lease_seconds
    if settings.ai_server_timeout_seconds + STT_CALL_MARGIN_SECONDS > lease_seconds:
        # 넘으면 제한 시간 안에 온 STT 결과도 임대가 끝나 저장하지 못하고 WORKER_LEASE_EXPIRED가 된다.
        raise RuntimeError(
            "SAEROK_AI_SERVER_TIMEOUT_SECONDS는 "
            "SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS보다 "
            f"{STT_CALL_MARGIN_SECONDS}초 이상 짧아야 합니다."
        )
    report = None
    notifier = None
    if not stt_only:
        time_limit = settings.report_generation_time_limit_seconds
        if time_limit + REPORT_SAVE_MARGIN_SECONDS > lease_seconds:
            raise RuntimeError(
                "SAEROK_REPORT_GENERATION_TIME_LIMIT_SECONDS는 "
                "SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS보다 "
                f"{REPORT_SAVE_MARGIN_SECONDS}초 이상 짧아야 합니다."
            )
        report = VisitReportGenerator(
            generate=generate or report_generator(settings),
            time_limit_seconds=time_limit,
        )
        notifier = report_notifier(settings)
    # 강제 종료로 남은 긴 녹음 사본을 지운다. 작업마다 조각을 나누기 전에도 다시 본다.
    remove_stale_work_dirs(older_than_seconds=3 * lease_seconds)
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
            backup_base_url=settings.ai_server_backup_url,
            failover_connect_timeout_seconds=settings.ai_server_failover_connect_timeout_seconds,
        ),
        open_connection=lambda: connect(database_url),
        lease_seconds=lease_seconds,
        # STT 뒤 같은 작업에서 리포트(8-3)까지 만든다.
        report_generator=report,
        report_notifier=notifier,
    )


def report_notifier(settings: Settings) -> ReportNotifier | None:
    """리포트 완료와 실패 푸시. 키 파일 경로가 비어 있으면 보내지 않는다.

    경로를 넣었는데 키 파일을 읽지 못하면 worker를 시작하지 않는다. 설정한 푸시가
    조용히 꺼진 채로 도는 일을 막는다.
    """
    if not settings.fcm_credentials_path:
        return None
    account = ServiceAccount.from_file(settings.fcm_credentials_path)
    return PushReportNotifier(
        FcmClient(account, timeout_seconds=settings.fcm_timeout_seconds)
    )


def report_generator(settings: Settings) -> GenerateReport:
    """ai 패키지의 리포트·변경 제안 생성 함수를 8-3 형식으로 감싼 생성 함수.

    리포트와 변경 제안을 차례로 만들고 `combine`으로 8-3 응답 하나로 합친다. 각 호출
    직전에 마감과 취소 상태를 확인해, 제한 시간이 지난 뒤 남은 스레드가 외부 ML API로
    전사문을 다시 보내지 않게 한다. 변경 제안은 이야기 후보와 주제 조정을 따로 부르므로
    (2026-11-09 PM 결정) 두 호출 직전마다(`before_call`) DB의 작업 행도 다시 읽어, 그 사이
    계정, 프로필이나 회차가 지워졌거나 작업이 끝났거나 전사 기한이 지났으면 보내지 않는다.
    이미 시작한 호출은 생성 함수 쪽에서 끊을 수 없다.

    모델이 낸 후보 수와 토큰 수는 8-3 응답에 없으므로 결과에 따로 붙인다(`GenerationCounts`).
    처리 기록 한 줄에만 쓴다.
    """
    api_key = settings.ml_api_key.get_secret_value()
    if not api_key:
        raise RuntimeError("리포트 생성에는 SAEROK_ML_API_KEY가 필요합니다.")
    model = settings.report_generation_model
    # ENDPOINTS에 없는 모델은 작업마다 INVALID_REQUEST로 실패하므로 시작할 때 막는다.
    if model not in ENDPOINTS:
        raise RuntimeError(
            f"SAEROK_REPORT_GENERATION_MODEL({model})은 ai/common/llm.py의 ENDPOINTS에 있어야 합니다."
        )

    def generate(request: VisitReportRequest, deadline: ReportDeadline) -> VisitReportResult:
        # 두 쪽 형식은 JSON 이름이 같음. UUID는 JSON에서 문자열로 바뀜
        try:
            sent = ai.VisitReportRequest.model_validate(
                request.model_dump(mode="json", by_alias=True)
            )
        except ValidationError as error:
            raise generation_failed("INVALID_REQUEST") from error
        try:
            deadline.check()
            report = report_generation.generate_report(sent, model=model, api_key=api_key)
            # 리포트 응답이 시간 초과 확정 뒤에 와도 변경 제안 호출을 시작하지 않는다.
            # 작업이 지워졌거나 끝났거나 전사 기한이 지났어도 전사문을 다시 보내지 않는다.
            proposals = proposal_generation.generate_proposals(
                sent, model=model, api_key=api_key, before_call=deadline.check_job
            )
        except ai.VisitReportError as error:
            failed = generation_failed(error.code)
            # 끊긴 응답(incomplete_responses)도 숫자로 남기려고 생성 함수의 토큰 수를 옮긴다.
            failed.token_usage = getattr(error, "token_usage", None)  # type: ignore[attr-defined]
            raise failed from error
        result = ai.combine(sent.analysis_id, report, proposals)
        parsed = parse_result(result.model_dump(mode="json", by_alias=True), request)
        return parsed.with_counts(
            GenerationCounts(
                life_fact_proposals_returned=proposals.life_fact_proposals_returned,
                topic_proposals_returned=proposals.topic_proposals_returned,
                token_usage=_add_usage(report.token_usage, proposals.token_usage),
            )
        )

    return generate


def _add_usage(*usages: dict[str, int]) -> dict[str, int]:
    """리포트와 변경 제안 호출의 토큰 수를 이름별로 더한다."""
    total: dict[str, int] = {}
    for usage in usages:
        for name, count in usage.items():
            total[name] = total.get(name, 0) + count
    return total


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
