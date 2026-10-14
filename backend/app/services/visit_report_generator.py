"""리포트 생성기(API 8-3). 음성 worker가 STT 뒤에 부른다.

순서는 요청 조립(읽기만) → AI 서버 호출(트랜잭션 밖) → 응답 검증 → 저장(한
트랜잭션)이다. 실패는 `AppError`로 올리고, 대기열이 그 `error_code`로 작업을
`failed`로 남긴다. 검증에 걸리면 아무것도 저장하지 않는다(부분 저장 없음).

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

from collections import Counter
from uuid import UUID

from app.clients.ai_server import AiServerClient
from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisResult
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

_SUMMARIZED_REACTIONS = {"positive", "neutral", "negative"}
_NOT_EVALUATED_REACTIONS = {"notUsed", None}


class VisitReportGenerator:
    """`speech_analysis_pipeline.ReportGenerator`의 구현."""

    def __init__(self, *, ai_server: AiServerClient) -> None:
        self._ai_server = ai_server

    async def generate(
        self,
        connection: DbConnection,
        *,
        session_id: str,
        speech: SpeechAnalysisResult,
    ) -> None:
        session_uuid = UUID(session_id)
        profile_id, request = await build_request(connection, session_uuid, speech)
        result = await self._ai_server.generate_visit_report(request)
        validate_result(request, result)
        await save_report(connection, session_uuid, profile_id, request, result)


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
    """리포트, 카드 요약과 변경 제안을 한 트랜잭션에서 저장한다.

    작업의 `completed`와 전사문 삭제는 worker의 `mark_completed`가 한다.
    """
    topic_ids = {card.card_id: card.topic.topic_id for card in request.cards}
    async with connection.transaction():
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


def _invalid_response() -> AppError:
    return AppError(
        status_code=502,
        error_code="INVALID_AI_RESPONSE",
        message="리포트 생성 서버의 응답 형식이 올바르지 않습니다.",
    )


def _already_generated() -> AppError:
    return AppError(
        status_code=409,
        error_code="REPORT_ALREADY_GENERATED",
        message="이 면회의 리포트가 이미 만들어졌습니다.",
    )
