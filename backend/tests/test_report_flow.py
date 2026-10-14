"""회차 생성부터 리포트 조회까지 이어지는 흐름 검증(5-1 → 6-1 → 6-2 → worker → 6-3, 7-x, 5-4).

API는 실제 라우터와 임시 DB를 쓰고, S3와 STT AI 서버, `ai/`의 리포트 생성 함수만 합성
결과로 바꿔 끼운다. 실제 모델은 부르지 않는다. 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime
from uuid import UUID

from app.api.deps import get_current_account, get_speech_audio_storage
from app.core.database import connect
from app.services.accounts import Account, ConsentRecord
from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
from app.services.speech_analysis_pipeline import create_speech_worker
from common import visit_report as ai_visit_report
from tests.card_fixtures import completed_card_set, with_db
from tests.support import request, run
from tests.test_speech_analyses import FakeAudioStorage, synthetic_wav
from tests.test_visit_report_generator import FakeAi, _connected, _connected_generator
from tests.visit_records import Records


class Flow:
    """한 보호자가 앱에서 부르는 순서대로 API를 부른다. 다른 계정으로도 부를 수 있다."""

    def __init__(self, database_url: str) -> None:
        self.records = Records(database_url)
        self.storage = FakeAudioStorage()
        self.user_id, self.profile_id = self.records.account()
        self.set_id, self.cards = with_db(
            database_url, lambda connection: completed_card_set(connection, self.profile_id)
        )
        self._caller = self.user_id
        app = self.records.app
        app.dependency_overrides[get_speech_audio_storage] = lambda: self.storage

        async def current_account() -> Account:
            granted = ConsentRecord(True, datetime.now(UTC))
            return Account(
                account_id=str(self._caller),
                provider="google",
                social_id="synthetic-sub",
                display_name="합성 보호자",
                email=None,
                consent_version="2026-09-06",
                consents={"serviceData": granted, "sensitiveData": granted},
                created_at=datetime(2026, 8, 1, tzinfo=UTC),
            )

        app.dependency_overrides[get_current_account] = current_account

    def call(self, method: str, path: str, *, as_user: UUID | None = None, **kwargs):
        self._caller = as_user or self.user_id
        return request(self.records.app, method, path, **kwargs)

    def start_visit(self) -> str:
        """5-1로 1, 2번 카드를 골라 회차를 만들고 6-1로 소감을 저장한다."""
        created = self.call(
            "POST",
            "/api/v1/visit-sessions",
            json={
                "setId": str(self.set_id),
                "selectedCardIds": [str(self.cards[0]), str(self.cards[1])],
            },
        )
        assert created.status_code == 201
        session_id = created.json()["sessionId"]
        evaluated = self.call(
            "POST",
            f"/api/v1/visit-sessions/{session_id}/evaluation",
            json={
                "conversationSatisfaction": 4,
                "careRecipientReaction": "pleased",
                "cardReviews": [
                    {"cardId": str(self.cards[0]), "wasUsed": True, "caregiverReaction": "positive"},
                    {"cardId": str(self.cards[1]), "wasUsed": False, "caregiverReaction": None},
                ],
                "freeNote": "합성 소감",
            },
        )
        assert evaluated.status_code == 201
        return session_id

    def submit_audio(self, session_id: str):
        return self.call(
            "POST",
            f"/api/v1/visit-sessions/{session_id}/speech-analyses",
            data={"participantCount": "2"},
            files={"audio": ("synthetic.wav", synthetic_wav(), "audio/wav")},
        )

    def run_worker(self) -> None:
        database_url = self.records.database_url
        worker = create_speech_worker(
            jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
                connection, lease_seconds=900
            ),
            audio_storage=self.storage,
            ai_server=FakeAi().client(),
            open_connection=lambda: connect(database_url),
            lease_seconds=900,
            report_generator=_connected_generator(),
        )
        assert run(worker.run_once()) is True

    def latest_session(self) -> dict:
        response = self.call("GET", f"/api/v1/profiles/{self.profile_id}/visit-sessions")
        return response.json()["sessions"][0]


def test_visit_flow_ends_with_a_saved_report(migrated_database_url, monkeypatch):
    flow = Flow(migrated_database_url)
    calls = _connected(monkeypatch)
    session_id = flow.start_visit()

    accepted = flow.submit_audio(session_id)
    analysis_id = accepted.json()["analysisId"]
    again = flow.submit_audio(session_id)
    while_processing = {
        "status": flow.call("GET", f"/api/v1/speech-analyses/{analysis_id}").json()["status"],
        "report": flow.call("GET", f"/api/v1/visit-sessions/{session_id}/report").json()[
            "errorCode"
        ],
        "session": flow.latest_session()["sessionStatus"],
    }

    flow.run_worker()

    assert accepted.status_code == 202 and accepted.json()["sessionId"] == session_id
    # 처리 중에 다시 보내면 같은 작업을 돌려준다.
    assert again.status_code == 202 and again.json()["analysisId"] == analysis_id
    assert while_processing == {
        "status": "queued",
        "report": "REPORT_NOT_FOUND",
        "session": "processing",
    }
    # 리포트 생성 함수는 같은 작업의 요청을 받았다.
    assert calls[0]["request"].analysis_id == analysis_id
    assert flow.call("GET", f"/api/v1/speech-analyses/{analysis_id}").json() == {
        "schemaVersion": 1,
        "analysisId": analysis_id,
        "sessionId": session_id,
        "status": "completed",
        "errorCode": None,
    }
    report = flow.call("GET", f"/api/v1/visit-sessions/{session_id}/report").json()
    assert (report["sessionId"], report["title"], report["body"]) == (
        session_id,
        "합성 리포트 제목",
        "합성 리포트 본문",
    )
    assert report["cardSummaries"] == [
        {"cardId": str(flow.cards[0]), "cardTitle": "합성 카드 1", "summary": "합성 카드 요약"}
    ]
    proposals = flow.call("GET", f"/api/v1/visit-sessions/{session_id}/proposals").json()
    assert [p["reviewStatus"] for p in proposals["lifeFactProposals"]] == ["pending"]
    assert [(p["cardId"], p["suggestedAction"]) for p in proposals["topicProposals"]] == [
        (str(flow.cards[1]), "more")
    ]
    reports = flow.call("GET", f"/api/v1/profiles/{flow.profile_id}/reports").json()["reports"]
    assert [r["sessionId"] for r in reports] == [session_id]
    assert flow.storage.objects == {}
    # 앱을 다시 켠 것처럼 목록에서 회차를 찾아 같은 결과를 다시 읽는다.
    restored = flow.latest_session()
    assert (restored["sessionId"], restored["sessionStatus"], restored["analysisId"]) == (
        session_id,
        "completed",
        analysis_id,
    )
    assert flow.call("GET", f"/api/v1/visit-sessions/{session_id}/report").json() == report
    assert flow.submit_audio(session_id).json()["errorCode"] == "ANALYSIS_ALREADY_COMPLETED"


def test_failed_report_generation_is_shown_as_failed(migrated_database_url, monkeypatch):
    flow = Flow(migrated_database_url)

    def fail(request):
        raise ai_visit_report.VisitReportError("LLM_UNAVAILABLE", "synthetic failure detail")

    _connected(monkeypatch, report=fail)
    session_id = flow.start_visit()
    analysis_id = flow.submit_audio(session_id).json()["analysisId"]

    flow.run_worker()

    assert flow.call("GET", f"/api/v1/speech-analyses/{analysis_id}").json() == {
        "schemaVersion": 1,
        "analysisId": analysis_id,
        "sessionId": session_id,
        "status": "failed",
        "errorCode": "AI_SERVER_UNAVAILABLE",
    }
    assert flow.call("GET", f"/api/v1/visit-sessions/{session_id}/report").json()[
        "errorCode"
    ] == "REPORT_NOT_FOUND"
    assert flow.latest_session()["sessionStatus"] == "failed"
    assert flow.records.scalar(
        "SELECT (SELECT count(*) FROM life_fact_proposals)"
        " + (SELECT count(*) FROM topic_proposals)"
    ) == 0
    assert flow.submit_audio(session_id).json()["errorCode"] == "ANALYSIS_ALREADY_FAILED"


def test_another_account_cannot_follow_the_flow(migrated_database_url, monkeypatch):
    flow = Flow(migrated_database_url)
    _connected(monkeypatch)
    other_user, _ = flow.records.account()
    session_id = flow.start_visit()
    analysis_id = flow.submit_audio(session_id).json()["analysisId"]
    flow.run_worker()

    codes = [
        flow.call("GET", path, as_user=other_user).json()["errorCode"]
        for path in (
            f"/api/v1/speech-analyses/{analysis_id}",
            f"/api/v1/visit-sessions/{session_id}/report",
            f"/api/v1/visit-sessions/{session_id}/evaluation",
        )
    ]
    other_audio = flow.call(
        "POST",
        f"/api/v1/visit-sessions/{session_id}/speech-analyses",
        as_user=other_user,
        data={"participantCount": "2"},
        files={"audio": ("synthetic.wav", synthetic_wav(), "audio/wav")},
    )

    assert codes == ["SPEECH_ANALYSIS_NOT_FOUND", "VISIT_SESSION_NOT_FOUND", "VISIT_SESSION_NOT_FOUND"]
    assert other_audio.status_code == 404
