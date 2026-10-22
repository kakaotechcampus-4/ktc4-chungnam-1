"""리포트 생성기(API 8-3). 음성 worker가 STT 뒤에 부른다.

순서는 요청 조립(읽기만) → 생성 함수 호출(트랜잭션 밖, 별도 스레드) → 응답 검증 →
저장과 작업 완료(한 트랜잭션)이다. 생성 함수는 `ai/`의 리포트·변경 제안 생성 함수를
감싼 것으로 worker가 넣는다(`app.workers.speech_analysis.report_generator`). 실패는
`AppError`로 올리고, 대기열이 그 `error_code`로 작업을 `failed`로 남긴다. 검증에 걸리면
아무것도 저장하지 않는다(부분 저장 없음).

시간 제한과 늦은 결과
- 요청 조립부터 검증까지 전체에 제한 시간(`time_limit_seconds`)을 둔다. 넘기면
  `AI_SERVER_TIMEOUT`이다. 생성 함수는 daemon 스레드에서 돌고, 기다림만 끝낸다.
  동기 함수라 스레드는 멈추지 않지만 그 결과는 아무도 읽지 않고, 생성 함수는 DB를
  쓰지 않는다.
- 결과가 와도 저장 직전에 마감을 다시 확인한다.
- 저장 트랜잭션은 먼저 작업 행을 잠그고 `generatingReport`이며 임대가 남았는지
  확인한다. 아니면(임대 만료로 다른 worker가 실패 처리함) `WORKER_LEASE_EXPIRED`로
  아무것도 저장하지 않는다. 리포트 저장과 작업 `completed`는 같은 트랜잭션이다.

응답 검증 규칙
- `cardSummaries`는 요청 카드 중 `reaction`이 `positive`, `neutral`, `negative`인
  카드만, 카드당 하나다.
- `topicProposals`는 요청 카드 안에서 카드당 최대 1개다.
- 보수적인 임시 정책(AI 담당자와 합의 필요): PM 결정(2026-09-19)은 카드를 쓰지 않았거나
  답하지 않았다는 사실만으로 `less`, `exclude`를 제안하지 않는 것이다. 백엔드는 AI가
  어떤 근거로 제안했는지 알 수 없으므로, `reaction`이 `notUsed`이거나 `null`인 카드의
  `less`, `exclude` 제안을 모두 위반으로 본다. 위반하면 그 제안만 빼지 않고 응답 전체를
  `INVALID_AI_RESPONSE`로 실패시킨다.
"""

import asyncio
import threading
import time
from collections import Counter
from collections.abc import Callable, Mapping
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisResult
from app.services.speech_analysis_jobs import complete_job
from app.schemas.visit_report_generation import (
    ReportCard,
    ReportCardTopic,
    ReportEvaluation,
    ReportLifeFact,
    ReportProfileFacts,
    ReportTranscript,
    ReportTranscriptSegment,
    VisitReportRequest,
    VisitReportResult,
)
from app.workers.base import LEASE_EXPIRED_ERROR

_SUMMARIZED_REACTIONS = {"positive", "neutral", "negative"}
_NOT_EVALUATED_REACTIONS = {"notUsed", None}



class ReportDeadline:
    """리포트 생성 한 번의 마감 시각."""

    def __init__(self, seconds: float) -> None:
        self.seconds = seconds
        self._end = time.monotonic() + seconds

    def left(self) -> float:
        return self._end - time.monotonic()

    def check(self) -> None:
        """마감이 지났으면 `AI_SERVER_TIMEOUT`."""
        if self.left() <= 0:
            raise _timed_out()


# 8-3 요청과 마감을 받아 응답을 돌려주는 동기 함수. 실패는 `AppError`로 올린다.
# 외부 호출 직전마다 `deadline.check()`로 마감을 확인한다.
GenerateReport = Callable[[VisitReportRequest, ReportDeadline], VisitReportResult]

# 생성 함수의 실패 코드를 기존 8-3 작업 실패 코드로 바꾼다(API 계약 유지).
_GENERATION_FAILURES = {
    "LLM_UNAVAILABLE": (503, "AI_SERVER_UNAVAILABLE", True),
    "GENERATION_FAILED": (502, "AI_SERVER_ERROR", False),
    "INVALID_REQUEST": (502, "AI_SERVER_ERROR", False),
}


class VisitReportGenerator:
    """`speech_analysis_pipeline.ReportGenerator`의 구현."""

    def __init__(self, *, generate: GenerateReport, time_limit_seconds: float) -> None:
        self._generate = generate
        self._time_limit_seconds = time_limit_seconds

    async def generate(
        self,
        connection: DbConnection,
        *,
        session_id: str,
        speech: SpeechAnalysisResult,
    ) -> None:
        deadline = ReportDeadline(self._time_limit_seconds)
        session_uuid = UUID(session_id)
        profile_id, request = await build_request(connection, session_uuid, speech)
        result = await _run_until(deadline, lambda: self._generate(request, deadline))
        validate_result(request, result)
        # 마감 직후 도착한 결과도 저장하지 않는다.
        deadline.check()
        await save_report(connection, session_uuid, profile_id, request, result)


async def _run_until(
    deadline: ReportDeadline, work: Callable[[], VisitReportResult]
) -> VisitReportResult:
    """`work`를 daemon 스레드에서 돌리고 마감까지만 기다린다. 넘기면 `AI_SERVER_TIMEOUT`.

    `asyncio.to_thread`는 끝나지 않은 스레드를 이벤트 루프 종료 때 기다려서
    (`--once`가 멈춤) 쓰지 않는다. 마감 뒤 도착한 결과와 예외는 버린다.
    """
    deadline.check()
    loop = asyncio.get_running_loop()
    done: asyncio.Future[VisitReportResult] = loop.create_future()

    def settle(result: VisitReportResult | None, error: BaseException | None) -> None:
        if done.done():  # 이미 시간 초과로 끝남
            return
        if error is not None:
            done.set_exception(error)
        else:
            done.set_result(result)

    def target() -> None:
        try:
            outcome = (work(), None)
        except BaseException as error:
            outcome = (None, error)
        try:
            loop.call_soon_threadsafe(settle, *outcome)
        except RuntimeError:
            pass  # 이벤트 루프가 이미 닫힘(--once 종료 뒤)

    threading.Thread(target=target, name="report-generation", daemon=True).start()
    try:
        return await asyncio.wait_for(done, timeout=max(0.0, deadline.left()))
    except TimeoutError:
        raise _timed_out() from None


async def build_request(
    connection: DbConnection, session_id: UUID, speech: SpeechAnalysisResult
) -> tuple[UUID, VisitReportRequest]:
    """8-3 요청을 만든다. 피보호자의 이름, 성별, 생년월일은 읽지도 넣지도 않는다."""
    cursor = await connection.execute(
        "SELECT profile_id, evaluation_satisfaction, evaluation_reaction, "
        "evaluation_note, evaluated_at, report_generated_at, "
        "(started_at AT TIME ZONE 'Asia/Seoul')::date AS visit_date "
        "FROM visit_sessions WHERE session_id = %s",
        (session_id,),
    )
    session = await cursor.fetchone()
    if session is None or session["evaluated_at"] is None:
        # 6-2가 평가 전 회차를 받지 않으므로 정상 흐름에서는 생기지 않는다.
        raise AppError(
            status_code=409,
            error_code="EVALUATION_REQUIRED",
            message="평가가 없는 면회의 리포트는 만들 수 없습니다.",
        )
    if session["report_generated_at"] is not None:
        raise _already_generated()
    profile_id = session["profile_id"]

    cursor = await connection.execute(
        "SELECT c.card_id, c.card_title, c.topic_id, t.title AS topic_title, "
        "c.review_reaction FROM conversation_cards c "
        "JOIN card_sets s ON s.set_id = c.set_id "
        "JOIN profile_topics t ON t.topic_id = c.topic_id "
        "WHERE s.session_id = %s AND c.selected ORDER BY c.position",
        (session_id,),
    )
    cards = [
        ReportCard(
            card_id=row["card_id"],
            card_title=row["card_title"],
            topic=ReportCardTopic(topic_id=row["topic_id"], title=row["topic_title"]),
            reaction=row["review_reaction"],
        )
        for row in await cursor.fetchall()
    ]

    cursor = await connection.execute(
        "SELECT occupation, hometown, hobby, family FROM profiles "
        "WHERE profile_id = %s",
        (profile_id,),
    )
    profile_facts = ReportProfileFacts(**await cursor.fetchone())

    cursor = await connection.execute(
        "SELECT fact_id, title, content FROM life_facts WHERE profile_id = %s "
        "ORDER BY created_at, fact_id",
        (profile_id,),
    )
    life_facts = [ReportLifeFact(**row) for row in await cursor.fetchall()]

    request = VisitReportRequest(
        analysis_id=speech.analysis_id,
        visit_date=session["visit_date"],
        evaluation=ReportEvaluation(
            conversation_satisfaction=session["evaluation_satisfaction"],
            care_recipient_reaction=session["evaluation_reaction"],
            free_note=session["evaluation_note"],
        ),
        cards=cards,
        profile_facts=profile_facts,
        life_facts=life_facts,
        # 전사문은 8-3 요청에만 쓴다. 단어별 시각과 확률은 넘기지 않는다.
        transcript=ReportTranscript(
            duration_ms=speech.duration_ms,
            segments=[
                ReportTranscriptSegment(
                    start_ms=segment.start_ms,
                    end_ms=segment.end_ms,
                    speaker_label=segment.speaker_label,
                    text=segment.text,
                )
                for segment in speech.segments
            ],
        ),
    )
    return profile_id, request


def validate_result(request: VisitReportRequest, result: VisitReportResult) -> None:
    """카드와 제안 규칙을 확인한다. 하나라도 어기면 응답 전체를 거절한다."""
    reactions = {card.card_id: card.reaction for card in request.cards}

    summary_cards = [summary.card_id for summary in result.card_summaries]
    if any(count > 1 for count in Counter(summary_cards).values()) or any(
        reactions.get(card_id, "absent") not in _SUMMARIZED_REACTIONS
        for card_id in summary_cards
    ):
        raise _invalid_response()

    proposal_cards = [proposal.card_id for proposal in result.topic_proposals]
    if any(count > 1 for count in Counter(proposal_cards).values()):
        raise _invalid_response()
    for proposal in result.topic_proposals:
        if proposal.card_id not in reactions:
            raise _invalid_response()
        # 보수적인 임시 정책. 모듈 설명 참고(AI 담당자와 합의 필요).
        if (
            proposal.suggested_action in {"less", "exclude"}
            and reactions[proposal.card_id] in _NOT_EVALUATED_REACTIONS
        ):
            raise _invalid_response()


async def save_report(
    connection: DbConnection,
    session_id: UUID,
    profile_id: UUID,
    request: VisitReportRequest,
    result: VisitReportResult,
) -> None:
    """리포트, 카드 요약, 변경 제안과 작업 `completed`(전사문 삭제)를 한 트랜잭션에서 한다.

    먼저 작업 행을 잠가, 임대가 남은 `generatingReport` 작업일 때만 저장한다. 잠금을
    잡고 있는 동안 임대 만료 정리(`expire_leases`)는 기다렸다가 끝난 작업을 건너뛴다.
    """
    topic_ids = {card.card_id: card.topic.topic_id for card in request.cards}
    async with connection.transaction():
        cursor = await connection.execute(
            "SELECT 1 FROM speech_analysis_jobs WHERE analysis_id = %s "
            "AND status = 'generatingReport' AND lease_expires_at > now() FOR UPDATE",
            (request.analysis_id,),
        )
        if await cursor.fetchone() is None:
            raise _lease_lost()
        cursor = await connection.execute(
            "UPDATE visit_sessions SET report_title = %s, report_body = %s, "
            "report_model = %s, report_prompt_version = %s, "
            "report_generated_at = now() "
            "WHERE session_id = %s AND report_generated_at IS NULL",
            (
                result.title,
                result.body,
                result.model,
                result.prompt_version,
                session_id,
            ),
        )
        if cursor.rowcount == 0:
            raise _already_generated()
        for summary in result.card_summaries:
            await connection.execute(
                "UPDATE conversation_cards SET report_summary = %s WHERE card_id = %s",
                (summary.summary, summary.card_id),
            )
        for proposal in result.life_fact_proposals:
            await connection.execute(
                "INSERT INTO life_fact_proposals "
                "(session_id, profile_id, title, content, reason) "
                "VALUES (%s, %s, %s, %s, %s)",
                (
                    session_id,
                    profile_id,
                    proposal.title,
                    proposal.content,
                    proposal.reason,
                ),
            )
        for proposal in result.topic_proposals:
            await connection.execute(
                "INSERT INTO topic_proposals "
                "(session_id, profile_id, card_id, topic_id, suggested_action, reason) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                (
                    session_id,
                    profile_id,
                    proposal.card_id,
                    topic_ids[proposal.card_id],
                    proposal.suggested_action,
                    proposal.reason,
                ),
            )
        await complete_job(connection, analysis_id=str(request.analysis_id))


def parse_result(data: Mapping[str, Any], request: VisitReportRequest) -> VisitReportResult:
    """생성 함수 결과(JSON 형식)를 8-3 응답으로 읽는다.

    형식이 틀리거나 다른 작업의 결과면 `INVALID_AI_RESPONSE`다.
    """
    try:
        result = VisitReportResult.model_validate(data)
    except ValidationError as error:
        raise _invalid_response() from error
    if result.analysis_id != request.analysis_id:
        raise _invalid_response()
    return result


def generation_failed(code: str) -> AppError:
    """생성 함수의 실패 코드에 맞는 작업 실패. 모르는 코드는 `AI_SERVER_ERROR`다.

    생성 함수가 남긴 메시지는 담지 않는다.
    """
    status_code, error_code, retryable = _GENERATION_FAILURES.get(
        code, (502, "AI_SERVER_ERROR", False)
    )
    return AppError(
        status_code=status_code,
        error_code=error_code,
        message="리포트를 만들지 못했습니다.",
        retryable=retryable,
    )


def _invalid_response() -> AppError:
    return AppError(
        status_code=502,
        error_code="INVALID_AI_RESPONSE",
        message="리포트 생성 결과의 형식이 올바르지 않습니다.",
    )


def _timed_out() -> AppError:
    return AppError(
        status_code=504,
        error_code="AI_SERVER_TIMEOUT",
        message="리포트 생성 시간이 제한을 넘었습니다.",
    )


def _lease_lost() -> AppError:
    return AppError(
        status_code=409,
        error_code=LEASE_EXPIRED_ERROR,
        message="작업 임대가 끝나 리포트를 저장하지 않았습니다.",
    )


def _already_generated() -> AppError:
    return AppError(
        status_code=409,
        error_code="REPORT_ALREADY_GENERATED",
        message="이 면회의 리포트가 이미 만들어졌습니다.",
    )
