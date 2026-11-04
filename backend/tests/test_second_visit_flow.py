"""실제 API, PostgreSQL, worker로 다음 회차까지 검사한다.

Google 인증, S3와 모델 호출만 합성 자료로 대신한다. 마이크, GPU, 실제 모델의
추출 품질이나 운영 배포를 검증하는 테스트가 아니다.
"""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest

from app.api.deps import get_current_account, get_speech_audio_storage
from app.core.config import Settings
from app.core.database import connect
from app.schemas.card_generation import (
    CardGenerationResult,
    GeneratedCard,
    GeneratedTopic,
)
from app.services.accounts import Account, ConsentRecord
from app.services.card_sets import build_context
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import create_speech_worker
from app.workers.card_generation import create_worker
from tests.card_fixtures import make_app, query, value, with_db
from tests.support import request, run
from tests.test_speech_analyses import FakeAudioStorage, synthetic_wav
from tests.test_visit_report_generator import FakeAi, _connected, _connected_generator


class SecondVisitFlow:
    def __init__(self, database_url):
        self.database_url = database_url
        self.user_id = with_db(
            database_url,
            lambda connection: value(
                connection,
                "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id",
                (f"synthetic-cycle-{uuid4()}",),
            ),
        )
        self.storage = FakeAudioStorage()
        self.card_requests = []
        self.restart_api()
        self.profile_id = self.call(
            "POST",
            "/api/v1/profiles",
            201,
            json={
                "name": "합성 대상자",
                "gender": "female",
                "birthDate": "1943-03-12",
                "condition": {"stage": "unknown"},
            },
        )["profileId"]
        self.base = f"/api/v1/profiles/{self.profile_id}"
        self.call("PATCH", self.base, 200, json={"hobby": "합성 정원 가꾸기"})

    def restart_api(self):
        self.app = make_app(self.database_url, self.user_id)
        granted = ConsentRecord(True, datetime.now(UTC))
        account = Account(
            account_id=str(self.user_id),
            provider="google",
            social_id="synthetic-cycle",
            display_name="합성 보호자",
            email=None,
            consent_version="2026-09-06",
            consents={"serviceData": granted, "sensitiveData": granted},
            created_at=datetime.now(UTC),
        )
        self.app.dependency_overrides[get_current_account] = lambda: account
        self.app.dependency_overrides[get_speech_audio_storage] = lambda: self.storage

    def call(self, method, path, status, **kwargs):
        response = request(self.app, method, path, **kwargs)
        assert response.status_code == status, response.text
        return response.json()

    def generate(self, *, excluded_topic=None):
        self.call("POST", self.base + "/card-generations", 202)

        def synthetic_cards(sent):
            self.card_requests.append(sent)
            facts = sent.context.life_facts
            cards = []
            for position in range(1, 13):
                evidence = (
                    [{"factId": str(facts[0].fact_id)}]
                    if facts and position == 1
                    else []
                )
                topic = GeneratedTopic(
                    title=f"합성 주제 {len(self.card_requests)}-{position}",
                    description="합성 주제 설명",
                    evidence=evidence,
                )
                if excluded_topic and position == 1:
                    topic = GeneratedTopic(topic_id=UUID(excluded_topic))
                cards.append(
                    GeneratedCard(
                        position=position,
                        topic=topic,
                        card_title=f"합성 카드 {position}",
                        description="합성 카드 설명",
                        primary_question=f"{facts[0].content} 더 말씀해 주실래요?"
                        if evidence
                        else "좋아하는 꽃이 있나요?",
                        follow_up_questions=[
                            "어떤 색인가요?",
                            "어디서 보셨나요?",
                            "어떤 느낌인가요?",
                        ],
                        evidence_source="lifeFact" if evidence else "none",
                        evidence=evidence,
                    )
                )
            return CardGenerationResult(
                model=sent.model,
                prompt_version=sent.prompt_version,
                cards=cards,
                log={"source": "synthetic-test"},
            )

        worker = create_worker(
            Settings(
                _env_file=None,
                database_url=self.database_url,
                ml_api_key="synthetic-key",
            ),
            synthetic_cards,
        )
        assert run(worker.run_once()) is True
        assert run(worker.run_once()) is False
        return self.call("GET", self.base + "/card-generations/status", 200)

    def cards(self):
        return self.call("GET", self.base + "/card-generations/current", 200)

    def start(self, cards, expected=201):
        return self.call(
            "POST",
            "/api/v1/visit-sessions",
            expected,
            json={
                "setId": cards["setId"],
                "selectedCardIds": [card["cardId"] for card in cards["cards"][:2]],
            },
        )

    def finish_first_visit(self, monkeypatch):
        self.generate()
        first = self.cards()
        session_id = self.start(first)["sessionId"]
        path = f"/api/v1/visit-sessions/{session_id}"
        self.call(
            "POST",
            path + "/evaluation",
            201,
            json={
                "conversationSatisfaction": 4,
                "careRecipientReaction": "pleased",
                "cardReviews": [
                    {
                        "cardId": first["cards"][0]["cardId"],
                        "wasUsed": True,
                        "caregiverReaction": "positive",
                    },
                    {
                        "cardId": first["cards"][1]["cardId"],
                        "wasUsed": False,
                        "caregiverReaction": None,
                    },
                ],
                "freeNote": "합성 면회 소감",
            },
        )
        upload = lambda: self.call(
            "POST",
            path + "/speech-analyses",
            202,
            data={"participantCount": "2"},
            files={"audio": ("synthetic.wav", synthetic_wav(), "audio/wav")},
        )
        analysis_id = upload()["analysisId"]
        assert upload()["analysisId"] == analysis_id
        calls = _connected(monkeypatch)
        worker = create_speech_worker(
            jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
                connection, lease_seconds=900
            ),
            audio_storage=self.storage,
            ai_server=FakeAi().client(),
            open_connection=lambda: connect(self.database_url),
            lease_seconds=900,
            report_generator=_connected_generator(),
        )
        assert run(worker.run_once()) is True
        assert [item["kind"] for item in calls] == ["report", "proposals"]
        assert (
            self.call("GET", f"/api/v1/speech-analyses/{analysis_id}", 200)["status"]
            == "completed"
        )
        report = self.call("GET", path + "/report", 200)
        assert report["body"] == "합성 리포트 본문"
        self.restart_api()
        assert self.call("GET", path + "/report", 200) == report
        proposals = self.call("GET", path + "/proposals", 200)
        assert len(proposals["lifeFactProposals"]) == 1
        assert self.call("GET", self.base, 200)["lifeFacts"] == []
        assert (
            with_db(
                self.database_url,
                lambda conn: build_context(conn, UUID(self.profile_id)),
            ).life_facts
            == []
        )
        return path, first, proposals


@pytest.mark.parametrize(
    "bad_regeneration", [False, True], ids=["second-visit", "excluded-topic-blocked"]
)
def test_approval_correction_and_next_visit(
    migrated_database_url, monkeypatch, bad_regeneration
):
    flow = SecondVisitFlow(migrated_database_url)
    path, first, proposals = flow.finish_first_visit(monkeypatch)
    story = proposals["lifeFactProposals"][0]
    topic = proposals["topicProposals"][0]
    excluded_id = topic["topic"]["topicId"]
    decisions = {
        "lifeFacts": [
            {
                "proposalId": story["proposalId"],
                "reviewStatus": "accepted",
                "title": "합성 마을",
                "content": "합성 마을에서 꽃을 길렀어요.",
            }
        ],
        "topics": [
            {
                "proposalId": topic["proposalId"],
                "reviewStatus": "accepted",
                "action": "exclude",
            }
        ],
    }
    flow.call("POST", path + "/proposals/review", 200, json=decisions)
    assert (
        flow.call("POST", path + "/proposals/review", 409, json=decisions)["errorCode"]
        == "PROPOSAL_ALREADY_REVIEWED"
    )
    fact = flow.call("GET", flow.base, 200)["lifeFacts"][0]
    assert fact["content"] == decisions["lifeFacts"][0]["content"]
    flow.generate()
    prepared = flow.cards()
    assert len(prepared["cards"]) == 12 and not prepared["needsRefresh"]
    sent = flow.card_requests[-1].context
    assert sent.life_facts[0].source == "visit"
    excluded = next(item for item in sent.topics if str(item.topic_id) == excluded_id)
    assert [item.action for item in excluded.feedback] == ["exclude"]
    assert (
        next(
            item
            for item in sent.past_cards
            if str(item.card_id) == first["cards"][1]["cardId"]
        ).review_reaction
        == "notUsed"
    )
    # 미사용 카드도 보호자가 직접 제외를 선택한 경우에만 제외한다.
    corrected = "합성 강가에서 꽃을 길렀어요."
    flow.call(
        "PATCH",
        f"/api/v1/life-facts/{fact['factId']}",
        200,
        json={"content": corrected},
    )
    flow.restart_api()
    assert flow.cards()["needsRefresh"] is True
    assert flow.start(prepared, 409)["errorCode"] == "CARD_SET_NEEDS_REFRESH"
    status = flow.generate(excluded_topic=excluded_id if bad_regeneration else None)
    refreshed_context = flow.card_requests[-1].context
    assert [item.content for item in refreshed_context.life_facts] == [corrected]
    if bad_regeneration:
        assert status["status"] == "failed"
        assert (
            query(
                migrated_database_url,
                "SELECT error_code FROM card_sets WHERE status = 'failed'",
            )[0]["error_code"]
            == "INVALID_GENERATION_RESULT"
        )
        assert (
            query(
                migrated_database_url,
                "SELECT count(*) AS n FROM conversation_cards c JOIN card_sets s ON s.set_id=c.set_id WHERE s.status='failed'",
            )[0]["n"]
            == 0
        )
        assert flow.start(prepared, 409)["errorCode"] == "CARD_SET_NEEDS_REFRESH"
        return
    assert status["status"] == "ready" and not status["needsRefresh"]
    final = flow.cards()
    assert final["setId"] != prepared["setId"]
    assert len(final["cards"]) == 12
    assert all(card["topic"]["topicId"] != excluded_id for card in final["cards"])
    assert corrected in final["cards"][0]["primaryQuestion"]
    flow.restart_api()
    second = flow.start(flow.cards())
    assert second["sessionStatus"] == "evaluationPending"
    assert second["sessionId"] != path.split("/")[-1]
    sessions = flow.call("GET", flow.base + "/visit-sessions", 200)["sessions"]
    assert len(sessions) == 2 and sessions[1]["sessionStatus"] == "completed"
