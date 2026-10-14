"""리포트 생성기(API 8-3)와 음성 worker 연결 검증.

AI 서버는 `httpx.MockTransport`로 흉내 낸다. 임시 DB에 최신 migration을 적용해
실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import httpx
import pytest

from app.clients.ai_server import AiServerClient
from app.core.database import connect
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisResult
from app.services.audio_storage import AudioDownload
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import create_speech_worker
from app.services.visit_report_generator import VisitReportGenerator
from tests.support import run
from tests.visit_records import Records, Visit

ANALYSIS_ID = "00000000-0000-4000-8000-000000000601"


def _speech(analysis_id: str = ANALYSIS_ID) -> SpeechAnalysisResult:
    return SpeechAnalysisResult.model_validate(
        {
            "schemaVersion": 1,
            "analysisId": analysis_id,
            "language": "ko",
            "durationMs": 15200,
            "text": "합성 전사 결과",
            "segments": [
                {
                    "startMs": 0,
                    "endMs": 3200,
                    "speakerLabel": "SPEAKER_00",
                    "text": "합성 발화 구간",
                    "words": [
                        {"startMs": 0, "endMs": 800, "text": "합성", "probability": 0.9}
                    ],
                }
            ],
        }
    )


def _report(visit: Visit, analysis_id: str = ANALYSIS_ID, **overrides) -> dict:
    first = str(visit.selected[0])
    return {
        "schemaVersion": 1,
        "analysisId": analysis_id,
        "model": "synthetic-model",
        "promptVersion": "report-v1",
        "title": "합성 리포트 제목",
        "body": "합성 리포트 본문",
        "cardSummaries": [{"cardId": first, "summary": "합성 카드 요약"}],
        "lifeFactProposals": [
            {"title": "합성 제안", "content": "합성 제안 내용", "reason": "합성 이유"}
        ],
        "topicProposals": [
            {"cardId": first, "suggestedAction": "more", "reason": "합성 이유"}
        ],
        **overrides,
    }


class FakeAi:
    """8-3 요청을 기록하고 정해 둔 응답을 돌려준다."""

    def __init__(self, response: dict | None = None, *, status_code: int = 200):
        self.response = response
        self.status_code = status_code
        self.report_requests: list[dict] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if request.url.path == "/internal/v1/speech-analyses":
            speech = _speech(body["analysisId"]).model_dump(mode="json", by_alias=True)
            return httpx.Response(200, json=speech)
        assert request.url.path == "/internal/v1/visit-reports"
        self.report_requests.append(body)
        return httpx.Response(self.status_code, json=self.response)

    def client(self) -> AiServerClient:
        return AiServerClient(
            base_url="http://ai.internal",
            timeout_seconds=5,
            transport=httpx.MockTransport(self.handler),
        )


def _evaluated(records: Records) -> Visit:
    """카드 3장 중 앞의 2장을 고르고 첫 장은 positive, 둘째 장은 notUsed로 평가한 회차."""
    _, profile_id = records.account()
    visit = records.visit(profile_id, cards=3, selected=2)
    records.evaluate(
        visit, reactions={visit.selected[0]: "positive", visit.selected[1]: "notUsed"}
    )
    return visit


def _generate(records: Records, visit: Visit, ai: FakeAi) -> None:
    async def scenario():
        async with connect(records.database_url) as connection:
            await VisitReportGenerator(ai_server=ai.client()).generate(
                connection, session_id=str(visit.session_id), speech=_speech()
            )

    run(scenario())


def _saved_rows(records: Records, visit: Visit) -> dict:
    return {
        "report": records.query(
            "SELECT report_title, report_body, report_model, report_prompt_version, "
            "report_generated_at IS NOT NULL AS generated "
            "FROM visit_sessions WHERE session_id = %s",
            (visit.session_id,),
        )[0],
        "summaries": records.query(
            "SELECT card_id, report_summary FROM conversation_cards "
            "WHERE set_id = %s AND report_summary IS NOT NULL",
            (visit.set_id,),
        ),
        "life_fact_proposals": records.query(
            "SELECT title, content, reason, status FROM life_fact_proposals"
        ),
        "topic_proposals": records.query(
            "SELECT card_id, topic_id, suggested_action, status FROM topic_proposals"
        ),
    }


NOTHING_SAVED = {
    "report": {
        "report_title": None,
        "report_body": None,
        "report_model": None,
        "report_prompt_version": None,
        "generated": False,
    },
    "summaries": [],
    "life_fact_proposals": [],
    "topic_proposals": [],
}


def test_request_has_evaluation_cards_facts_and_transcript_without_identity(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    fact_id = records.scalar(
        "INSERT INTO life_facts (profile_id, title, content) "
        "VALUES (%s, '합성 생애 제목', '합성 생애 내용') RETURNING fact_id",
        (visit.profile_id,),
    )
    ai = FakeAi(_report(visit))

    _generate(records, visit, ai)

    [sent] = ai.report_requests
    assert sent["schemaVersion"] == 1
    assert sent["analysisId"] == ANALYSIS_ID
    assert sent["evaluation"] == {
        "conversationSatisfaction": 4,
        "careRecipientReaction": "pleased",
        "freeNote": None,
    }
    assert sent["cards"] == [
        {
            "cardId": str(visit.selected[0]),
            "cardTitle": "합성 카드 1",
            "topic": {"topicId": str(visit.topic_ids[0]), "title": "합성 주제 1"},
            "reaction": "positive",
        },
        {
            "cardId": str(visit.selected[1]),
            "cardTitle": "합성 카드 2",
            "topic": {"topicId": str(visit.topic_ids[1]), "title": "합성 주제 2"},
            "reaction": "notUsed",
        },
    ]
    assert sent["profileFacts"] == {
        "occupation": "합성 직업 이야기",
        "hometown": None,
        "hobby": "합성 취미 이야기",
        "family": None,
    }
    assert sent["lifeFacts"] == [
        {"factId": str(fact_id), "title": "합성 생애 제목", "content": "합성 생애 내용"}
    ]
    assert sent["transcript"] == {
        "durationMs": 15200,
        "segments": [
            {"startMs": 0, "endMs": 3200, "speakerLabel": "SPEAKER_00", "text": "합성 발화 구간"}
        ],
    }
    # 피보호자의 이름, 성별, 생년월일은 어떤 형태로도 보내지 않는다.
    raw = json.dumps(sent, ensure_ascii=False)
    for identity in ("합성 이름", "female", "1943-03-12", "name", "gender", "birth"):
        assert identity not in raw


def test_generated_report_and_proposals_are_saved(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)

    _generate(records, visit, FakeAi(_report(visit)))

    assert _saved_rows(records, visit) == {
        "report": {
            "report_title": "합성 리포트 제목",
            "report_body": "합성 리포트 본문",
            "report_model": "synthetic-model",
            "report_prompt_version": "report-v1",
            "generated": True,
        },
        "summaries": [{"card_id": visit.selected[0], "report_summary": "합성 카드 요약"}],
        "life_fact_proposals": [
            {
                "title": "합성 제안",
                "content": "합성 제안 내용",
                "reason": "합성 이유",
                "status": "pending",
            }
        ],
        "topic_proposals": [
            {
                "card_id": visit.selected[0],
                "topic_id": visit.topic_ids[0],
                "suggested_action": "more",
                "status": "pending",
            }
        ],
    }


def test_more_for_an_unused_card_is_allowed(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    unused = str(visit.selected[1])
    report = _report(
        visit,
        topicProposals=[{"cardId": unused, "suggestedAction": "more", "reason": "합성 이유"}],
    )

    _generate(records, visit, FakeAi(report))

    assert records.scalar("SELECT count(*) FROM topic_proposals") == 1


def _violations(visit: Visit) -> dict[str, dict]:
    first, unused = (str(card_id) for card_id in visit.selected)
    not_selected = str(visit.card_ids[2])
    unknown = str(uuid4())

    def topic(card_id, action="more"):
        return {"cardId": card_id, "suggestedAction": action, "reason": "합성 이유"}

    def summary(card_id):
        return {"cardId": card_id, "summary": "합성 카드 요약"}

    return {
        "summary_for_unused_card": _report(visit, cardSummaries=[summary(unused)]),
        "summary_for_unselected_card": _report(visit, cardSummaries=[summary(not_selected)]),
        "summary_for_unknown_card": _report(visit, cardSummaries=[summary(unknown)]),
        "two_summaries_for_one_card": _report(
            visit, cardSummaries=[summary(first), summary(first)]
        ),
        "proposal_for_unknown_card": _report(visit, topicProposals=[topic(unknown)]),
        "proposal_for_unselected_card": _report(visit, topicProposals=[topic(not_selected)]),
        "two_proposals_for_one_card": _report(
            visit, topicProposals=[topic(first), topic(first, "less")]
        ),
        # 보수적인 임시 정책(AI 담당자와 합의 필요).
        "less_for_unused_card": _report(visit, topicProposals=[topic(unused, "less")]),
        "exclude_for_unused_card": _report(visit, topicProposals=[topic(unused, "exclude")]),
        "other_analysis": _report(visit, analysis_id=str(uuid4())),
        "blank_title": _report(visit, title=" "),
        "long_title": _report(visit, title="가" * 201),
        "blank_summary": _report(visit, cardSummaries=[{"cardId": first, "summary": " "}]),
        "long_life_fact_title": _report(
            visit,
            lifeFactProposals=[{"title": "가" * 101, "content": "합성", "reason": "합성"}],
        ),
        "unknown_action": _report(visit, topicProposals=[topic(first, "remove")]),
        "missing_field": {k: v for k, v in _report(visit).items() if k != "body"},
        "extra_field": _report(visit, mood="good"),
    }


VIOLATIONS = [
    "summary_for_unused_card",
    "summary_for_unselected_card",
    "summary_for_unknown_card",
    "two_summaries_for_one_card",
    "proposal_for_unknown_card",
    "proposal_for_unselected_card",
    "two_proposals_for_one_card",
    "less_for_unused_card",
    "exclude_for_unused_card",
    "other_analysis",
    "blank_title",
    "long_title",
    "blank_summary",
    "long_life_fact_title",
    "unknown_action",
    "missing_field",
    "extra_field",
]


@pytest.mark.parametrize("violation", VIOLATIONS)
def test_invalid_response_fails_without_partial_save(migrated_database_url, violation):
    records = Records(migrated_database_url)
    visit = _evaluated(records)

    with pytest.raises(AppError) as error:
        _generate(records, visit, FakeAi(_violations(visit)[violation]))

    assert error.value.error_code == "INVALID_AI_RESPONSE"
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_less_for_an_unanswered_card_is_rejected(migrated_database_url):
    records = Records(migrated_database_url)
    _, profile_id = records.account()
    visit = records.visit(profile_id, cards=2, selected=2)
    # 둘째 카드는 답하지 않았다(review_reaction null).
    records.evaluate(visit, reactions={visit.selected[0]: "positive"})
    report = _report(
        visit,
        topicProposals=[
            {"cardId": str(visit.selected[1]), "suggestedAction": "less", "reason": "합성"}
        ],
    )

    with pytest.raises(AppError) as error:
        _generate(records, visit, FakeAi(report))

    assert error.value.error_code == "INVALID_AI_RESPONSE"
    assert _saved_rows(records, visit) == NOTHING_SAVED


@pytest.mark.parametrize(
    ("status_code", "error_code"),
    [(500, "AI_SERVER_ERROR"), (422, "AI_SERVER_ERROR")],
)
def test_ai_server_failure_saves_nothing(migrated_database_url, status_code, error_code):
    records = Records(migrated_database_url)
    visit = _evaluated(records)

    with pytest.raises(AppError) as error:
        _generate(records, visit, FakeAi({"detail": "synthetic"}, status_code=status_code))

    assert error.value.error_code == error_code
    assert "synthetic" not in error.value.message
    assert _saved_rows(records, visit) == NOTHING_SAVED


@pytest.mark.parametrize(
    ("failure", "error_code"),
    [
        (httpx.ReadTimeout("synthetic"), "AI_SERVER_TIMEOUT"),
        (httpx.ConnectError("synthetic"), "AI_SERVER_UNAVAILABLE"),
    ],
)
def test_ai_server_transport_failure_saves_nothing(
    migrated_database_url, failure, error_code
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)

    def handler(request: httpx.Request) -> httpx.Response:
        raise failure

    async def scenario():
        client = AiServerClient(
            base_url="http://ai.internal",
            timeout_seconds=5,
            transport=httpx.MockTransport(handler),
        )
        async with connect(records.database_url) as connection:
            await VisitReportGenerator(ai_server=client).generate(
                connection, session_id=str(visit.session_id), speech=_speech()
            )

    with pytest.raises(AppError) as error:
        run(scenario())

    assert error.value.error_code == error_code
    assert error.value.retryable is True
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_report_is_not_generated_twice(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _generate(records, visit, FakeAi(_report(visit)))
    ai = FakeAi(_report(visit))

    with pytest.raises(AppError) as error:
        _generate(records, visit, ai)

    assert error.value.error_code == "REPORT_ALREADY_GENERATED"
    assert ai.report_requests == []
    assert records.scalar("SELECT count(*) FROM life_fact_proposals") == 1


class FakeAudioStorage:
    def __init__(self) -> None:
        self.deleted: list[str] = []

    async def create_download(
        self, *, object_key: str, expires_at: datetime
    ) -> AudioDownload:
        return AudioDownload(
            url="https://bucket.s3.ap-northeast-2.amazonaws.com/synthetic.wav",
            expires_at=min(expires_at, datetime.now(UTC) + timedelta(minutes=10)),
        )

    async def delete(self, *, object_key: str) -> None:
        self.deleted.append(object_key)


def _run_worker(records: Records, ai: FakeAi) -> None:
    worker = create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=900
        ),
        audio_storage=FakeAudioStorage(),
        ai_server=ai.client(),
        open_connection=lambda: connect(records.database_url),
        lease_seconds=900,
        report_generator=VisitReportGenerator(ai_server=ai.client()),
    )
    assert run(worker.run_once()) is True


def _job(records: Records, analysis_id: UUID) -> dict:
    return records.query(
        "SELECT status, error_code, transcript IS NULL AS transcript_deleted "
        "FROM speech_analysis_jobs WHERE analysis_id = %s",
        (analysis_id,),
    )[0]


def test_worker_completes_the_job_after_saving_the_report(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")

    _run_worker(records, FakeAi(_report(visit, analysis_id=str(analysis_id))))

    assert _job(records, analysis_id) == {
        "status": "completed",
        "error_code": None,
        "transcript_deleted": True,
    }
    assert records.scalar(
        "SELECT report_generated_at IS NOT NULL FROM visit_sessions WHERE session_id = %s",
        (visit.session_id,),
    )
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    )
    sessions = records.call(
        user_id, "GET", f"/api/v1/profiles/{visit.profile_id}/visit-sessions"
    ).json()["sessions"]
    assert sessions[0]["sessionStatus"] == "completed"


def test_worker_fails_the_job_on_an_invalid_report_without_partial_save(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    report = _violations(visit)["less_for_unused_card"] | {"analysisId": str(analysis_id)}

    _run_worker(records, FakeAi(report))

    assert _job(records, analysis_id) == {
        "status": "failed",
        "error_code": "INVALID_AI_RESPONSE",
        "transcript_deleted": True,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    )
    sessions = records.call(
        user_id, "GET", f"/api/v1/profiles/{visit.profile_id}/visit-sessions"
    ).json()["sessions"]
    assert sessions[0]["sessionStatus"] == "failed"
