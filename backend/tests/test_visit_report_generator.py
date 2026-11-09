"""리포트 생성기(API 8-3)와 음성 worker 연결 검증.

STT(8-1) AI 서버는 `httpx.MockTransport`로, 리포트 생성 함수는 정해 둔 결과를
돌려주는 가짜 함수로 흉내 낸다. `ai/` 생성 함수를 감싼 연결은 그 함수들을 바꿔 끼워
확인하며 실제 모델은 부르지 않는다. 임시 DB에 최신 migration을 적용해
실행한다(`conftest.py`). 값은 모두 합성 데이터다.
"""

import asyncio
import json
import logging
import re
import threading
import time
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import httpx
import openai
import proposal_generation
import proposal_generation.generate as proposal_generation_module
import pydantic
import pytest
import report_generation
import report_generation.generate as report_generation_module
from common import visit_report as ai_visit_report
from common.llm import ENDPOINTS
from langchain_core.exceptions import OutputParserException

from app.clients.ai_server import AiServerClient
from app.core.config import Settings
from app.core.database import connect
from app.core.errors import AppError
from app.core.logging import SafeJsonFormatter
from app.schemas.speech_analysis import SpeechAnalysisResult
from app.services.audio_storage import AudioDownload
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import SpeechAnalysisQueue, create_speech_worker
from app.schemas.visit_report_generation import VisitReportRequest, VisitReportResult
from app.services.visit_report_generator import (
    ReportDeadline,
    VisitReportGenerator,
    build_request,
    parse_result,
)
from app.workers.speech_analysis import report_generator
from tests.card_fixtures import completed_card_set, with_db
from tests.support import run
from tests.visit_records import Records, Visit

ANALYSIS_ID = "00000000-0000-4000-8000-000000000601"
# 테스트의 리포트 생성 제한 시간(초). 시간 제한 테스트는 따로 짧게 준다.
TIME_LIMIT_SECONDS = 30
HANGUL = re.compile(r"[가-힣]")
# 처리 기록(`speech_analysis_finished`)에서 확인하는 값. 토큰 수는 생성 함수가 알려 줄 때만 있다.
COUNT_KEYS = (
    "outcome",
    "error_code",
    "analysis_id",
    "stt_server",
    "audio_seconds",
    "transcript_segments",
    "transcript_chars",
    "last_segment_end_seconds",
    "speaker_labels",
    "report_body_chars",
    "life_story_proposals_returned",
    "life_story_proposals_kept",
    "story_categories",
    "sensitive_proposals",
    "topic_proposals_returned",
    "topic_proposals_kept",
    "model",
    "prompt_version",
)


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
                },
                {
                    "startMs": 3400, "endMs": 5000,
                    "speakerLabel": "SPEAKER_01",
                    "text": "두 번째 합성 발화 구간", "words": [],
                },
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
        "lifeFactProposals": [_life_fact_proposal()],
        "topicProposals": [
            {"cardId": first, "suggestedAction": "more", "reason": "합성 이유"}
        ],
        **overrides,
    }


def _life_fact_proposal(**overrides) -> dict:
    return {
        "title": "합성 제안",
        "content": "합성 제안 내용",
        "reason": "합성 이유",
        "storyCategory": "work",
        "sensitive": False,
        **overrides,
    }


class FakeAi:
    """STT(8-1)에는 합성 전사 결과를, 리포트 생성 함수에는 정해 둔 결과를 돌려준다.

    결과는 실제 연결과 같은 `parse_result`로 읽으므로 형식 검사도 같다.
    """

    def __init__(self, response: dict | None = None):
        self.response = response
        self.report_requests: list[dict] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/internal/v1/speech-analyses"
        body = json.loads(request.content)
        speech = _speech(body["analysisId"]).model_dump(mode="json", by_alias=True)
        return httpx.Response(200, json=speech)

    def generate(self, request: VisitReportRequest, deadline: ReportDeadline) -> VisitReportResult:
        self.report_requests.append(request.model_dump(mode="json", by_alias=True))
        return parse_result(self.response, request)

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


def _generating_job(records: Records, visit: Visit) -> UUID:
    """생성기를 바로 부르는 테스트용 `generatingReport` 작업(임대 1시간). 이미 있으면 그대로 쓴다."""
    analysis_id = UUID(ANALYSIS_ID)
    if not records.scalar(
        "SELECT count(*) FROM speech_analysis_jobs WHERE analysis_id = %s", (analysis_id,)
    ):
        records.job(visit.session_id, "generatingReport", analysis_id=analysis_id)
    return analysis_id


def _generate(records: Records, visit: Visit, ai: FakeAi) -> None:
    _generate_with(
        records,
        visit,
        VisitReportGenerator(generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS),
    )


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
            "SELECT title, content, reason, story_category, sensitive, status "
            "FROM life_fact_proposals ORDER BY created_at, title"
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
    assert sent["participantCount"] == 2
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
            {"startMs": 0, "endMs": 3200, "speakerLabel": "SPEAKER_00", "text": "합성 발화 구간"},
            {"startMs": 3400, "endMs": 5000, "speakerLabel": "SPEAKER_01", "text": "두 번째 합성 발화 구간"},
        ],
    }
    # 피보호자의 이름, 성별, 생년월일은 어떤 형태로도 보내지 않는다.
    raw = json.dumps(sent, ensure_ascii=False)
    for identity in ("합성 이름", "female", "1943-03-12", "name", "gender", "birth"):
        assert identity not in raw


def test_request_uses_only_cards_chosen_through_the_session_api(migrated_database_url):
    """5-1, 5-3으로 고른 카드와 6-1 평가가 같은 회차의 8-3 요청이 된다.

    같은 프로필의 다른 회차 카드와 고르지 않은 카드는 섞이지 않는다.
    """
    records = Records(migrated_database_url)
    user_id, profile_id = records.account()
    other = records.visit(profile_id, cards=2, selected=2)
    set_id, cards = with_db(
        migrated_database_url, lambda connection: completed_card_set(connection, profile_id)
    )
    created = records.call(
        user_id,
        "POST",
        "/api/v1/visit-sessions",
        json={"setId": str(set_id), "selectedCardIds": [str(cards[0]), str(cards[2])]},
    )
    session_id = created.json()["sessionId"]
    added = records.call(
        user_id,
        "PATCH",
        f"/api/v1/visit-sessions/{session_id}/cards",
        json={"cardIds": [str(cards[9])]},
    )
    evaluated = records.call(
        user_id,
        "POST",
        f"/api/v1/visit-sessions/{session_id}/evaluation",
        json={
            "conversationSatisfaction": 3,
            "careRecipientReaction": "calm",
            "cardReviews": [
                {"cardId": str(cards[0]), "wasUsed": True, "caregiverReaction": "positive"},
                {"cardId": str(cards[2]), "wasUsed": False, "caregiverReaction": None},
            ],
            "freeNote": "합성 소감",
        },
    )

    async def scenario():
        async with connect(migrated_database_url) as connection:
            return await build_request(connection, UUID(session_id), _speech())

    request_profile_id, request = run(scenario())

    assert (created.status_code, added.status_code, evaluated.status_code) == (201, 200, 201)
    assert request_profile_id == profile_id
    assert [(card.card_id, card.reaction) for card in request.cards] == [
        (cards[0], "positive"),
        (cards[2], "notUsed"),
        (cards[9], None),
    ]
    assert not {card.card_id for card in request.cards} & set(other.card_ids)
    assert request.evaluation.conversation_satisfaction == 3
    assert request.evaluation.free_note == "합성 소감"


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
                "story_category": "work",
                "sensitive": False,
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


def test_up_to_30_life_fact_proposals_keep_their_category_and_sensitive_flag(
    migrated_database_url,
):
    """이야기 후보는 30개까지 저장한다. 분류와 아픈 기억 표시도 후보마다 그대로 남는다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    categories = ["family", "hobby", "work", "hometown", "friend", "travel", "other"]
    proposals = [
        _life_fact_proposal(
            title=f"합성 제안 {n:02d}",
            storyCategory=categories[n % len(categories)],
            sensitive=n % 4 == 0,
        )
        for n in range(30)
    ]

    _generate(records, visit, FakeAi(_report(visit, lifeFactProposals=proposals)))

    saved = _saved_rows(records, visit)["life_fact_proposals"]
    assert [(p["title"], p["story_category"], p["sensitive"]) for p in saved] == [
        (p["title"], p["storyCategory"], p["sensitive"]) for p in proposals
    ]


def test_category_and_sensitive_flag_go_from_the_ai_result_to_the_approved_story(
    migrated_database_url,
):
    """AI 결과(8-3) → 저장 → 7-3 → 7-4 승인 → `life_facts.story_category`까지 분류가 이어진다.

    보호자가 분류를 고르지 않은 후보는 AI가 고른 분류로, 고른 후보는 고른 분류로 만든다.
    """
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    proposals = [
        _life_fact_proposal(title="합성 제안 1", storyCategory="hometown"),
        _life_fact_proposal(title="합성 제안 2", storyCategory="family", sensitive=True),
        _life_fact_proposal(title="합성 제안 3", storyCategory="hobby"),
    ]
    _generate(records, visit, FakeAi(_report(visit, lifeFactProposals=proposals, topicProposals=[])))
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    )
    path = f"/api/v1/visit-sessions/{visit.session_id}/proposals"

    listed = records.call(user_id, "GET", path).json()["lifeFactProposals"]
    assert [(p["title"], p["storyCategory"], p["sensitive"]) for p in listed] == [
        ("합성 제안 1", "hometown", False),
        ("합성 제안 2", "family", True),
        ("합성 제안 3", "hobby", False),
    ]
    first, second, third = (p["proposalId"] for p in listed)

    def accept(proposal_id, **extra):
        return {
            "proposalId": proposal_id,
            "reviewStatus": "accepted",
            "title": "합성 최종 제목",
            "content": "합성 최종 내용",
            **extra,
        }

    reviewed = records.call(
        user_id,
        "POST",
        f"{path}/review",
        json={
            "lifeFacts": [
                accept(first),
                accept(second, storyCategory="friend"),
                {"proposalId": third, "reviewStatus": "rejected"},
            ],
            "topics": [],
        },
    )

    assert reviewed.status_code == 200
    stored = records.query(
        "SELECT source_proposal_id::text AS proposal, story_category FROM life_facts"
    )
    assert {row["proposal"]: row["story_category"] for row in stored} == {
        first: "hometown",
        second: "friend",
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
            visit, lifeFactProposals=[_life_fact_proposal(title="가" * 101)]
        ),
        # 일대기 분류는 7개 값 가운데 하나이고 분류와 아픈 기억 표시는 빼먹을 수 없다.
        "unknown_story_category": _report(
            visit, lifeFactProposals=[_life_fact_proposal(storyCategory="occupation")]
        ),
        "missing_story_category": _report(
            visit,
            lifeFactProposals=[
                {k: v for k, v in _life_fact_proposal().items() if k != "storyCategory"}
            ],
        ),
        "missing_sensitive": _report(
            visit,
            lifeFactProposals=[
                {k: v for k, v in _life_fact_proposal().items() if k != "sensitive"}
            ],
        ),
        # AI 쪽이 30개로 자르므로 넘게 오면 형식 오류다.
        "too_many_life_fact_proposals": _report(
            visit,
            lifeFactProposals=[_life_fact_proposal(title=f"합성 {n}") for n in range(31)],
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
    "unknown_story_category",
    "missing_story_category",
    "missing_sensitive",
    "too_many_life_fact_proposals",
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
        report_generator=VisitReportGenerator(
            generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS
        ),
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
        "transcript_deleted": False,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED
    user_id = records.scalar(
        "SELECT user_id FROM profiles WHERE profile_id = %s", (visit.profile_id,)
    )
    sessions = records.call(
        user_id, "GET", f"/api/v1/profiles/{visit.profile_id}/visit-sessions"
    ).json()["sessions"]
    assert sessions[0]["sessionStatus"] == "failed"


# ── ai 패키지 생성 함수 연결(`report_generator`) ─────────────────
# `ai/`의 generate_report, generate_proposals를 바꿔 끼워 연결만 확인한다. 실제 모델은
# 부르지 않는다.


def _ai_report(request: ai_visit_report.VisitReportRequest) -> ai_visit_report.ReportResult:
    first = request.cards[0].card_id
    return ai_visit_report.ReportResult(
        model="gpt-5.6-luna",
        prompt_version="report-1",
        title="합성 리포트 제목",
        body="합성 리포트 본문",
        card_summaries=[ai_visit_report.CardSummaryOut(card_id=first, summary="합성 카드 요약")],
    )


def _ai_proposals(
    request: ai_visit_report.VisitReportRequest, *, action: str = "more"
) -> ai_visit_report.ProposalResult:
    unused = request.cards[1].card_id
    return ai_visit_report.ProposalResult(
        model="gpt-5.6-luna",
        prompt_version="proposals-1",
        life_fact_proposals=[
            ai_visit_report.LifeFactProposalOut(
                title="합성 제안",
                content="합성 제안 내용",
                reason="합성 이유",
                story_category="family",
                sensitive=True,
            )
        ],
        topic_proposals=[
            ai_visit_report.TopicProposalOut(
                card_id=unused, suggested_action=action, reason="합성 이유"
            )
        ],
        life_fact_proposals_returned=2,
        topic_proposals_returned=1,
    )


def _connected(monkeypatch, *, report=_ai_report, proposals=_ai_proposals) -> list[dict]:
    """생성 함수를 바꿔 끼운 `report_generator`. 받은 호출을 기록한다.

    변경 제안은 실제 함수처럼 두 모델 호출(이야기 후보, 주제 조정) 직전마다 `before_call`을 부른다.
    """
    calls: list[dict] = []

    def fake_report(request, *, model, api_key, **kwargs):
        calls.append({"kind": "report", "request": request, "model": model, "api_key": api_key})
        return report(request)

    def fake_proposals(request, *, model, api_key, before_call=None, **kwargs):
        for _ in ("life_facts", "topics"):
            if before_call is not None:
                before_call()
        calls.append({"kind": "proposals", "request": request, "model": model, "api_key": api_key})
        return proposals(request)

    monkeypatch.setattr(report_generation, "generate_report", fake_report)
    monkeypatch.setattr(proposal_generation, "generate_proposals", fake_proposals)
    return calls


def _connected_generator(time_limit_seconds: float = TIME_LIMIT_SECONDS) -> VisitReportGenerator:
    settings = Settings(_env_file=None, ml_api_key="synthetic-key")
    return VisitReportGenerator(
        generate=report_generator(settings), time_limit_seconds=time_limit_seconds
    )


def _generate_with(records: Records, visit: Visit, generator: VisitReportGenerator) -> None:
    _generating_job(records, visit)

    async def scenario():
        async with connect(records.database_url) as connection:
            await generator.generate(
                connection, session_id=str(visit.session_id), speech=_speech()
            )

    run(scenario())


def test_default_report_model_is_one_the_ai_package_can_call():
    assert Settings(_env_file=None).report_generation_model in ENDPOINTS


def test_report_generator_requires_the_ml_api_key():
    with pytest.raises(RuntimeError):
        report_generator(Settings(_env_file=None, ml_api_key=""))


def test_connected_generator_saves_the_combined_ai_result(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    calls = _connected(monkeypatch)

    _generate_with(records, visit, _connected_generator())

    assert [call["kind"] for call in calls] == ["report", "proposals"]
    for call in calls:
        assert isinstance(call["request"], ai_visit_report.VisitReportRequest)
        assert call["model"] == "gpt-6-luna"
        assert call["api_key"] == "synthetic-key"
    sent = calls[0]["request"]
    assert sent.analysis_id == ANALYSIS_ID
    assert [card.card_id for card in sent.cards] == [str(card) for card in visit.selected]
    raw = sent.model_dump_json()
    for identity in ("합성 이름", "female", "1943-03-12", "name", "gender", "birth"):
        assert identity not in raw
    assert _saved_rows(records, visit) == {
        "report": {
            "report_title": "합성 리포트 제목",
            "report_body": "합성 리포트 본문",
            "report_model": "gpt-5.6-luna",
            "report_prompt_version": "report-1+proposals-1",
            "generated": True,
        },
        "summaries": [{"card_id": visit.selected[0], "report_summary": "합성 카드 요약"}],
        "life_fact_proposals": [
            {
                "title": "합성 제안",
                "content": "합성 제안 내용",
                "reason": "합성 이유",
                "story_category": "family",
                "sensitive": True,
                "status": "pending",
            }
        ],
        "topic_proposals": [
            {
                "card_id": visit.selected[1],
                "topic_id": visit.topic_ids[1],
                "suggested_action": "more",
                "status": "pending",
            }
        ],
    }


@pytest.mark.parametrize(
    ("failing", "ai_code", "error_code", "retryable"),
    [
        ("report", "LLM_UNAVAILABLE", "AI_SERVER_UNAVAILABLE", True),
        ("report", "GENERATION_FAILED", "AI_SERVER_ERROR", False),
        ("report", "INVALID_REQUEST", "AI_SERVER_ERROR", False),
        # 리포트는 만들었지만 변경 제안에서 실패해도 아무것도 저장하지 않는다.
        ("proposals", "LLM_UNAVAILABLE", "AI_SERVER_UNAVAILABLE", True),
        ("proposals", "GENERATION_FAILED", "AI_SERVER_ERROR", False),
    ],
)
def test_ai_failure_maps_to_contract_codes_without_partial_save(
    migrated_database_url, monkeypatch, failing, ai_code, error_code, retryable
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)

    def fail(request):
        raise ai_visit_report.VisitReportError(ai_code, "synthetic failure detail")

    _connected(monkeypatch, **{failing: fail})

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert (error.value.error_code, error.value.retryable) == (error_code, retryable)
    assert "synthetic" not in error.value.message
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_ai_result_breaking_backend_rules_is_rejected_without_partial_save(
    migrated_database_url, monkeypatch
):
    """AI 쪽 거르기를 지나도 BE 검증은 그대로 적용한다(notUsed 카드의 less)."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    _connected(monkeypatch, proposals=lambda request: _ai_proposals(request, action="less"))

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert error.value.error_code == "INVALID_AI_RESPONSE"
    assert _saved_rows(records, visit) == NOTHING_SAVED


# ── 생성 오류 구분(#143) ─────────────────────────────────────
# 후보가 없는 정상 응답과 호출 실패, 잘린 응답이나 JSON 오류를 기존 실패 코드로 나누는지
# 확인한다. 예외는 `ai/`의 실제 생성 함수 안에서 모델 호출(`invoke_structured`) 자리에
# 넣는다. 실제 출력 한도에 닿았을 때 SDK가 어떤 예외를 던지는지는 실측하지 않았다.


def test_no_candidates_is_a_normal_completion(migrated_database_url, monkeypatch):
    """카드 요약, 이야기 후보와 주제 조정이 모두 비어도 리포트를 저장하고 작업을 끝낸다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")

    def report(request):
        return _ai_report(request).model_copy(update={"card_summaries": []})

    def proposals(request):
        return _ai_proposals(request).model_copy(
            update={"life_fact_proposals": [], "topic_proposals": []}
        )

    _connected(monkeypatch, report=report, proposals=proposals)

    _run_worker_with(records, FakeAi(), _connected_generator())

    assert _job(records, analysis_id) == {
        "status": "completed",
        "error_code": None,
        "transcript_deleted": True,
    }
    assert _saved_rows(records, visit) == {
        **NOTHING_SAVED,
        "report": {
            "report_title": "합성 리포트 제목",
            "report_body": "합성 리포트 본문",
            "report_model": "gpt-5.6-luna",
            "report_prompt_version": "report-1+proposals-1",
            "generated": True,
        },
    }


def _synthetic_request() -> httpx.Request:
    return httpx.Request("POST", "https://synthetic.invalid/v1/responses")


def _validation_error() -> Exception:
    class Shape(pydantic.BaseModel):
        title: str

    try:
        Shape.model_validate({})
    except pydantic.ValidationError as error:
        return error
    raise AssertionError("검증 오류가 나야 함")


# (모델 호출에서 난 예외, 작업 실패 코드, 재시도 가능)
_CALL_ERRORS = {
    "connection": (
        lambda: openai.APIConnectionError(request=_synthetic_request()),
        "AI_SERVER_UNAVAILABLE",
        True,
    ),
    "timeout": (
        lambda: openai.APITimeoutError(request=_synthetic_request()),
        "AI_SERVER_UNAVAILABLE",
        True,
    ),
    "bad_request": (
        lambda: openai.BadRequestError(
            "synthetic 합성 발화 구간",
            response=httpx.Response(400, request=_synthetic_request()),
            body=None,
        ),
        "AI_SERVER_ERROR",
        False,
    ),
    "truncated_json": (
        lambda: OutputParserException('synthetic {"title": "합성 발화 구간'),
        "AI_SERVER_ERROR",
        False,
    ),
    "json_decode": (
        lambda: json.JSONDecodeError("Unterminated string", '{"title": "합성 발화 구간', 10),
        "AI_SERVER_ERROR",
        False,
    ),
    "schema_mismatch": (_validation_error, "AI_SERVER_ERROR", False),
}


@pytest.mark.parametrize("failing", ["report", "proposals"])
@pytest.mark.parametrize("case", list(_CALL_ERRORS))
def test_model_call_errors_map_to_contract_codes_without_partial_save(
    migrated_database_url, monkeypatch, failing, case
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    make_error, error_code, retryable = _CALL_ERRORS[case]
    called = []

    def fail(*args, **kwargs):
        called.append(failing)
        raise make_error()

    # 실패하는 쪽만 `ai/`의 실제 생성 함수를 부르고, 다른 쪽은 정상 결과를 돌려준다.
    _connected(monkeypatch, **{failing: _real_ai_function(failing)})
    module = report_generation_module if failing == "report" else proposal_generation_module
    monkeypatch.setattr(module, "invoke_structured", fail)

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    # 변경 제안은 이야기 후보와 주제 조정을 따로 부른다(2026-11-09). 두 호출이 함께 나가면 둘 다
    # 실패하므로 호출 수는 판에 따라 1~2번이다. 다른 쪽 생성 함수는 부르지 않는다.
    assert called and set(called) == {failing}
    assert (error.value.error_code, error.value.retryable) == (error_code, retryable)
    # 모델이나 SDK가 남긴 메시지(전사문 일부일 수 있음)는 작업 실패에 담지 않는다.
    assert "합성" not in error.value.message and "synthetic" not in error.value.message
    assert _saved_rows(records, visit) == NOTHING_SAVED
    assert _job(records, UUID(ANALYSIS_ID))["status"] == "generatingReport"


def _real_ai_function(kind: str):
    """`_connected`에 넣을 `ai/`의 실제 생성 함수. 모델 호출은 테스트가 바꿔 끼운다."""
    real = (
        report_generation_module.generate_report
        if kind == "report"
        else proposal_generation_module.generate_proposals
    )

    def call(request):
        return real(request, model="gpt-5.6-luna", api_key="synthetic-key")

    return call


def test_worker_completes_with_the_connected_generator(migrated_database_url, monkeypatch):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    calls = _connected(monkeypatch)
    worker = create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=900
        ),
        audio_storage=FakeAudioStorage(),
        ai_server=FakeAi().client(),
        open_connection=lambda: connect(records.database_url),
        lease_seconds=900,
        report_generator=_connected_generator(),
    )

    assert run(worker.run_once()) is True

    assert calls[0]["request"].analysis_id == str(analysis_id)
    assert _job(records, analysis_id) == {
        "status": "completed",
        "error_code": None,
        "transcript_deleted": True,
    }


# ── 전체 시간 제한과 늦은 결과(#123 리뷰) ─────────────────────
# 생성 함수가 마감을 넘기거나, 임대가 끝난 뒤 결과를 돌려주는 상황을 가짜 함수로 만든다.

SHORT_LIMIT_SECONDS = 0.3


class SlowAi(FakeAi):
    """`release`가 풀릴 때까지 결과를 돌려주지 않는 생성 함수."""

    def __init__(self, response: dict | None = None):
        super().__init__(response)
        self.release = threading.Event()

    def generate(self, request: VisitReportRequest, deadline: ReportDeadline) -> VisitReportResult:
        assert self.release.wait(10)
        return super().generate(request, deadline)


class HookAi(FakeAi):
    """결과를 돌려주기 직전에 `before_return`을 부르는 생성 함수."""

    def __init__(self, response: dict, before_return) -> None:
        super().__init__(response)
        self.before_return = before_return

    def generate(self, request: VisitReportRequest, deadline: ReportDeadline) -> VisitReportResult:
        self.before_return()
        return super().generate(request, deadline)


def _finish_generation_threads() -> None:
    """마감 뒤에도 남은 생성 스레드가 끝날 때까지 기다린다."""
    for thread in threading.enumerate():
        if thread.name == "report-generation":
            thread.join(5)
            assert not thread.is_alive()


def _run_worker_with(records: Records, ai: FakeAi, generator: VisitReportGenerator) -> None:
    worker = create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=900
        ),
        audio_storage=FakeAudioStorage(),
        ai_server=ai.client(),
        open_connection=lambda: connect(records.database_url),
        lease_seconds=900,
        report_generator=generator,
    )
    assert run(worker.run_once()) is True


def test_generation_over_the_time_limit_times_out_and_the_late_result_is_not_saved(
    migrated_database_url,
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    ai = SlowAi(_report(visit))
    generator = VisitReportGenerator(generate=ai.generate, time_limit_seconds=SHORT_LIMIT_SECONDS)

    started = time.monotonic()
    with pytest.raises(AppError) as error:
        _generate_with(records, visit, generator)
    waited = time.monotonic() - started
    # 결과가 늦게 도착한다.
    ai.release.set()
    _finish_generation_threads()

    assert error.value.error_code == "AI_SERVER_TIMEOUT"
    assert waited < 5
    assert len(ai.report_requests) == 1
    assert _saved_rows(records, visit) == NOTHING_SAVED
    assert _job(records, UUID(ANALYSIS_ID))["status"] == "generatingReport"


def test_worker_fails_a_timed_out_job_and_ignores_the_late_result(migrated_database_url):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    ai = SlowAi(_report(visit, analysis_id=str(analysis_id)))
    generator = VisitReportGenerator(generate=ai.generate, time_limit_seconds=SHORT_LIMIT_SECONDS)

    _run_worker_with(records, ai, generator)
    after_timeout = _job(records, analysis_id)
    ai.release.set()
    _finish_generation_threads()

    expected = {"status": "failed", "error_code": "AI_SERVER_TIMEOUT", "transcript_deleted": False}
    assert after_timeout == expected
    assert _job(records, analysis_id) == expected
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_cancelled_deadline_fails_the_check_before_the_time_runs_out():
    deadline = ReportDeadline(60)
    deadline.cancel()

    with pytest.raises(AppError) as error:
        deadline.check()

    assert error.value.error_code == "AI_SERVER_TIMEOUT"


@pytest.mark.parametrize("clock", ["real", "not_yet_past"])
def test_connected_generator_stops_before_the_proposal_call_after_the_time_limit(
    migrated_database_url, monkeypatch, clock
):
    """마감 뒤 남은 스레드가 변경 제안을 위해 전사문을 다시 보내지 않는다.

    `not_yet_past`는 이벤트 루프가 시간 초과를 확정했는데 스레드가 읽는 시계로는 아직
    마감 전인 경우다(Windows의 시계 해상도에서 생김). 시계와 관계없이 멈춰야 한다.
    """
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    report_started = threading.Event()
    release = threading.Event()

    def slow_report(request):
        report_started.set()
        assert release.wait(10)
        return _ai_report(request)

    calls = _connected(monkeypatch, report=slow_report)
    if clock == "not_yet_past":
        monkeypatch.setattr(ReportDeadline, "left", lambda self: self.seconds)

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator(SHORT_LIMIT_SECONDS))
    # 시간 초과가 확정된 뒤에 첫 리포트 응답이 도착한다.
    assert report_started.wait(5)
    release.set()
    _finish_generation_threads()

    assert error.value.error_code == "AI_SERVER_TIMEOUT"
    assert [call["kind"] for call in calls] == ["report"]
    assert _saved_rows(records, visit) == NOTHING_SAVED


def _expire_lease(records: Records, analysis_id: UUID) -> None:
    records.execute(
        "UPDATE speech_analysis_jobs SET lease_expires_at = now() - interval '1 second' "
        "WHERE analysis_id = %s",
        (analysis_id,),
    )


def test_result_after_another_worker_expired_the_lease_is_not_saved(migrated_database_url):
    """생성 중 임대가 끝나 다른 worker가 실패 처리한 작업에 늦은 결과를 저장하지 않는다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")

    def expired_by_another_worker() -> None:
        _expire_lease(records, analysis_id)

        async def expire() -> int:
            async with connect(records.database_url) as connection:
                queue = SpeechAnalysisQueue(
                    jobs_for=lambda c: PostgresSpeechAnalysisJobRepository(c, lease_seconds=900),
                    audio_storage=FakeAudioStorage(),
                )
                return await queue.expire_leases(connection)

        assert run(expire()) == 1

    ai = HookAi(_report(visit, analysis_id=str(analysis_id)), expired_by_another_worker)
    generator = VisitReportGenerator(generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS)

    _run_worker_with(records, ai, generator)

    # 먼저 남은 실패 코드를 덮지 않는다.
    assert _job(records, analysis_id) == {
        "status": "failed",
        "error_code": "WORKER_LEASE_EXPIRED",
        "transcript_deleted": False,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_result_after_the_lease_ended_is_not_saved_before_cleanup(migrated_database_url):
    """임대가 끝났지만 아직 아무도 정리하지 않은 경계에서도 저장하지 않는다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    ai = HookAi(
        _report(visit, analysis_id=str(analysis_id)), lambda: _expire_lease(records, analysis_id)
    )
    generator = VisitReportGenerator(generate=ai.generate, time_limit_seconds=TIME_LIMIT_SECONDS)

    _run_worker_with(records, ai, generator)

    assert _job(records, analysis_id) == {
        "status": "failed",
        "error_code": "WORKER_LEASE_EXPIRED",
        "transcript_deleted": False,
    }
    assert _saved_rows(records, visit) == NOTHING_SAVED


def test_late_result_does_not_overwrite_a_saved_report(migrated_database_url):
    """같은 작업의 생성이 둘 겹쳐도 하나만 저장하고 먼저 저장한 결과를 덮지 않는다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = _generating_job(records, visit)
    first = FakeAi(_report(visit))
    second = FakeAi(_report(visit, title="늦은 합성 리포트 제목"))
    second_may_return = threading.Event()

    def generate_second(request, deadline):
        assert second_may_return.wait(10)
        return second.generate(request, deadline)

    async def scenario():
        async def generate(fn):
            async with connect(records.database_url) as connection:
                await VisitReportGenerator(
                    generate=fn, time_limit_seconds=TIME_LIMIT_SECONDS
                ).generate(connection, session_id=str(visit.session_id), speech=_speech())

        late = asyncio.create_task(generate(generate_second))
        await generate(first.generate)
        second_may_return.set()
        return await asyncio.gather(late, return_exceptions=True)

    (late_outcome,) = run(scenario())

    assert isinstance(late_outcome, AppError)
    assert late_outcome.error_code in {"WORKER_LEASE_EXPIRED", "REPORT_ALREADY_GENERATED"}
    assert _saved_rows(records, visit)["report"]["report_title"] == "합성 리포트 제목"
    assert records.scalar("SELECT count(*) FROM life_fact_proposals") == 1
    assert records.scalar("SELECT count(*) FROM topic_proposals") == 1
    assert _job(records, analysis_id) == {
        "status": "completed",
        "error_code": None,
        "transcript_deleted": True,
    }


# ── 변경 제안의 두 호출과 처리 기록(2026-11-09 PM 결정) ─────────────


def test_connected_generator_checks_the_job_before_each_proposal_call(
    migrated_database_url, monkeypatch
):
    """변경 제안은 이야기 후보와 주제 조정을 따로 부른다. 두 호출 직전마다 작업을 다시 확인해,
    이야기 후보 호출 뒤 임대가 끝났으면 주제 조정 호출에 전사문을 보내지 않는다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    sent: list[str] = []

    def proposals(request, *, model, api_key, before_call=None, **kwargs):
        before_call()
        sent.append("life_facts")
        _expire_lease(records, UUID(ANALYSIS_ID))
        before_call()
        sent.append("topics")
        return _ai_proposals(request)

    _connected(monkeypatch)
    monkeypatch.setattr(proposal_generation, "generate_proposals", proposals)

    with pytest.raises(AppError) as error:
        _generate_with(records, visit, _connected_generator())

    assert error.value.error_code == "WORKER_LEASE_EXPIRED"
    assert sent == ["life_facts"]
    assert _saved_rows(records, visit) == NOTHING_SAVED


def _capture_speech_logs(caplog) -> None:
    # `Records`가 앱을 만들 때 루트 로그 핸들러를 지우므로 caplog 핸들러를 다시 단다.
    logging.getLogger().addHandler(caplog.handler)
    caplog.set_level(logging.INFO, logger="saerok.speech_analysis")


def _finished_log(caplog) -> dict:
    """`speech_analysis_finished` 한 줄을 운영과 같은 형식(JSON)으로 읽는다. 글이 없는지도 본다."""
    records = [r for r in caplog.records if r.getMessage() == "speech_analysis_finished"]
    assert len(records) == 1
    formatted = SafeJsonFormatter().format(records[0])
    # 합성 전사, 리포트, 제목, 이유는 모두 한글이다. 처리 기록에는 한 글자도 없어야 한다.
    assert not HANGUL.search(formatted), formatted
    return json.loads(formatted)


def test_worker_logs_processing_counts_without_conversation_text(
    migrated_database_url, monkeypatch, caplog
):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    _connected(monkeypatch)
    _capture_speech_logs(caplog)

    _run_worker_with(records, FakeAi(), _connected_generator())

    speech = _speech()
    log = _finished_log(caplog)
    assert {key: log[key] for key in COUNT_KEYS} == {
        "outcome": "completed",
        "error_code": None,
        "analysis_id": str(analysis_id),
        "stt_server": "primary",
        "audio_seconds": 15.2,
        "transcript_segments": 2,
        "transcript_chars": sum(len(segment.text) for segment in speech.segments),
        "last_segment_end_seconds": 5.0,
        "speaker_labels": 2,
        "report_body_chars": len("합성 리포트 본문"),
        "life_story_proposals_returned": 2,
        "life_story_proposals_kept": 1,
        "story_categories": {"family": 1},
        "sensitive_proposals": 1,
        "topic_proposals_returned": 1,
        "topic_proposals_kept": 1,
        "model": "gpt-5.6-luna",
        "prompt_version": "report-1+proposals-1",
    }


def test_failed_job_log_keeps_the_counts_of_the_rejected_result(migrated_database_url, caplog):
    """검증에서 거절한 결과도 받은 숫자는 남긴다. 모델이 낸 수는 생성 함수가 알려 줄 때만 있다."""
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    report = _violations(visit)["less_for_unused_card"] | {"analysisId": str(analysis_id)}
    _capture_speech_logs(caplog)

    _run_worker(records, FakeAi(report))

    log = _finished_log(caplog)
    assert (log["outcome"], log["error_code"]) == ("failed", "INVALID_AI_RESPONSE")
    assert (log["life_story_proposals_returned"], log["life_story_proposals_kept"]) == (None, 1)
    assert (log["story_categories"], log["sensitive_proposals"]) == ({"work": 1}, 0)
    assert log["transcript_segments"] == 2


def test_stt_failure_log_has_no_report_counts(migrated_database_url, caplog):
    records = Records(migrated_database_url)
    visit = _evaluated(records)
    analysis_id = records.job(visit.session_id, "queued")
    _capture_speech_logs(caplog)

    class NoStt(FakeAi):
        def handler(self, request: httpx.Request) -> httpx.Response:
            return httpx.Response(503, json={"errorCode": "SYNTHETIC"})

    _run_worker(records, NoStt(_report(visit, analysis_id=str(analysis_id))))

    log = _finished_log(caplog)
    assert (log["outcome"], log["error_code"]) == ("failed", "AI_SERVER_ERROR")
    # 예비 서버가 없으니 기본 서버가 실패했다. 실패해도 어느 서버였는지 남긴다.
    assert log["stt_server"] == "primary" and log["transcript_segments"] is None
    assert log["report_body_chars"] is None and log["story_categories"] is None
