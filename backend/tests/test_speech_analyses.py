import asyncio
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from io import BytesIO
import json
import wave

import httpx
import pytest

from app.api.deps import get_current_account
from app.clients.ai_server import AiServerClient
from app.core.errors import AppError
from app.main import create_app
from app.schemas.speech_analysis import SpeechAnalysisRequest, SpeechAnalysisResult
from app.services.accounts import Account, ConsentRecord
from app.services.audio_storage import AudioDownload
from app.services.speech_analysis_jobs import (
    InMemorySpeechAnalysisJobRepository,
    SpeechAnalysisStatus,
)
from app.services.speech_analysis_pipeline import (
    SpeechAnalysisSubmissionService,
    SpeechAnalysisWorker,
)
from tests.support import request


ACCOUNT = Account(
    account_id="00000000-0000-0000-0000-000000000001",
    provider="google",
    social_id="synthetic-sub",
    display_name="보호자",
    email=None,
    consent_version="2026-09-06",
    consents={
        "serviceData": ConsentRecord(True, datetime.now(UTC)),
        "sensitiveData": ConsentRecord(True, datetime.now(UTC)),
    },
    created_at=datetime.now(UTC),
)
SESSION_ID = "00000000-0000-0000-0000-000000000002"


def synthetic_wav() -> bytes:
    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(b"\x00\x00" * 1600)
    return output.getvalue()


class FakeAudioStorage:
    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.deleted: list[str] = []

    async def upload(self, *, object_key: str, file) -> None:
        file.seek(0)
        self.objects[object_key] = file.read()

    async def create_download(
        self,
        *,
        object_key: str,
        expires_at: datetime,
    ) -> AudioDownload:
        assert object_key in self.objects
        return AudioDownload(
            url="https://bucket.s3.ap-northeast-2.amazonaws.com/synthetic.wav",
            expires_at=min(expires_at, datetime.now(UTC) + timedelta(minutes=10)),
        )

    async def delete(self, *, object_key: str) -> None:
        self.objects.pop(object_key, None)
        self.deleted.append(object_key)


class FailingAudioStorage(FakeAudioStorage):
    async def upload(self, *, object_key: str, file) -> None:
        del object_key, file
        raise RuntimeError("synthetic storage failure")


class FakeAiServer:
    def __init__(self) -> None:
        self.payloads = []

    async def analyze_speech(self, payload):
        self.payloads.append(payload)
        return SpeechAnalysisResult(
            schemaVersion=1,
            analysisId=payload.analysis_id,
            language="ko",
            durationMs=100,
            text="합성 전사 결과",
            segments=[],
        )


class FakeReportGenerator:
    def __init__(self) -> None:
        self.sessions: list[str] = []

    async def generate(self, *, session_id: str, speech) -> None:
        assert speech.text == "합성 전사 결과"
        self.sessions.append(session_id)


def harness():
    application = create_app()
    jobs = InMemorySpeechAnalysisJobRepository()
    jobs.allow_session(account_id=ACCOUNT.account_id, session_id=SESSION_ID)
    storage = FakeAudioStorage()
    service = SpeechAnalysisSubmissionService(
        jobs=jobs,
        audio_storage=storage,
        max_audio_bytes=1024 * 1024,
        retention_seconds=86400,
        object_prefix="temporary/speech",
    )
    application.state.speech_analysis_submission = service

    async def current_account():
        return ACCOUNT

    application.dependency_overrides[get_current_account] = current_account
    return application, jobs, storage, service


def submit(application, *, participant_count: str = "2", audio: bytes | None = None):
    return request(
        application,
        "POST",
        f"/api/v1/visit-sessions/{SESSION_ID}/speech-analyses",
        data={"participantCount": participant_count},
        files={"audio": ("synthetic.wav", audio or synthetic_wav(), "audio/wav")},
    )


def test_accepts_wav_and_returns_durable_job_identifier() -> None:
    application, jobs, storage, _ = harness()

    response = submit(application)

    assert response.status_code == 202
    body = response.json()
    assert body["sessionId"] == SESSION_ID
    assert body["status"] == "queued"
    job = asyncio.run(
        jobs.get_for_account(
            analysis_id=body["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job is not None
    assert job.participant_count == 2
    assert job.size_bytes == len(synthetic_wav())
    assert storage.objects[job.object_key] == synthetic_wav()


def test_repeated_submission_reuses_the_active_job_without_second_upload() -> None:
    application, _, storage, _ = harness()

    first = submit(application)
    second = submit(application)

    assert first.status_code == 202
    assert second.status_code == 202
    assert second.json()["analysisId"] == first.json()["analysisId"]
    assert len(storage.objects) == 1


def test_rejects_invalid_participant_count_before_upload() -> None:
    application, _, storage, _ = harness()

    response = submit(application, participant_count="9")

    assert response.status_code == 422
    assert response.json()["errorCode"] == "INVALID_REQUEST"
    assert storage.objects == {}


def test_rejects_a_file_that_is_not_the_required_wav_format() -> None:
    application, _, storage, _ = harness()

    response = submit(application, audio=b"not-a-wave-file")

    assert response.status_code == 422
    assert response.json()["errorCode"] == "INVALID_AUDIO_FORMAT"
    assert storage.objects == {}


def test_failed_upload_is_not_accepted_and_can_be_submitted_again() -> None:
    application, jobs, _, _ = harness()
    failing = FailingAudioStorage()
    application.state.speech_analysis_submission = SpeechAnalysisSubmissionService(
        jobs=jobs,
        audio_storage=failing,
        max_audio_bytes=1024 * 1024,
        retention_seconds=86400,
        object_prefix="temporary/speech",
    )

    failed = submit(application)

    assert failed.status_code == 503
    assert failed.json()["errorCode"] == "AUDIO_STORAGE_UNAVAILABLE"

    healthy = FakeAudioStorage()
    application.state.speech_analysis_submission = SpeechAnalysisSubmissionService(
        jobs=jobs,
        audio_storage=healthy,
        max_audio_bytes=1024 * 1024,
        retention_seconds=86400,
        object_prefix="temporary/speech",
    )
    retried = submit(application)
    assert retried.status_code == 202


def test_status_is_visible_only_to_the_owning_account() -> None:
    application, _, _, _ = harness()
    accepted = submit(application).json()

    response = request(
        application,
        "GET",
        f"/api/v1/speech-analyses/{accepted['analysisId']}",
    )

    assert response.status_code == 200
    assert response.json()["status"] == "queued"

    async def another_account():
        return replace(
            ACCOUNT,
            account_id="00000000-0000-0000-0000-000000000099",
        )

    application.dependency_overrides[get_current_account] = another_account
    hidden = request(
        application,
        "GET",
        f"/api/v1/speech-analyses/{accepted['analysisId']}",
    )
    assert hidden.status_code == 404
    assert hidden.json()["errorCode"] == "SPEECH_ANALYSIS_NOT_FOUND"


def test_worker_maps_participant_count_and_completes_after_report() -> None:
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    ai = FakeAiServer()
    reports = FakeReportGenerator()
    worker = SpeechAnalysisWorker(
        jobs=jobs,
        audio_storage=storage,
        ai_server=ai,
        report_generator=reports,
        lease_seconds=900,
    )

    assert asyncio.run(worker.run_once()) is True

    job = asyncio.run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job is not None
    assert job.status == SpeechAnalysisStatus.COMPLETED
    assert job.audio_deleted_at is not None
    assert ai.payloads[0].speaker_count == 2
    assert reports.sessions == [SESSION_ID]
    assert storage.objects == {}


def test_worker_finishes_stt_without_claiming_report_completion() -> None:
    application, jobs, storage, _ = harness()
    accepted = submit(application).json()
    worker = SpeechAnalysisWorker(
        jobs=jobs,
        audio_storage=storage,
        ai_server=FakeAiServer(),
        report_generator=None,
        lease_seconds=900,
    )

    asyncio.run(worker.run_once())

    job = asyncio.run(
        jobs.get_for_account(
            analysis_id=accepted["analysisId"], account_id=ACCOUNT.account_id
        )
    )
    assert job is not None
    assert job.status == SpeechAnalysisStatus.STT_COMPLETED
    assert job.stt_completed_at is not None
    assert job.error_code is None
    assert job.audio_deleted_at is not None


def test_ai_client_forwards_internal_request_and_validates_response() -> None:
    now = datetime.now(UTC)
    request_body = {
        "schemaVersion": 1,
        "analysisId": "analysis_test_001",
        "language": "ko",
        "speakerCount": 2,
        "audioSource": {
            "type": "s3PresignedGet",
            "downloadUrl": "https://bucket.s3.amazonaws.com/audio.wav",
            "downloadUrlExpiresAt": (now + timedelta(minutes=10)).isoformat(),
            "sizeBytes": 123456,
            "sha256": "a" * 64,
        },
        "dataExpiresAt": (now + timedelta(hours=1)).isoformat(),
    }
    response_body = {
        "schemaVersion": 1,
        "analysisId": "analysis_test_001",
        "language": "ko",
        "durationMs": 3200,
        "text": "합성 전사 결과",
        "segments": [],
    }

    def handler(ai_request: httpx.Request) -> httpx.Response:
        assert ai_request.url.path == "/internal/v1/speech-analyses"
        sent = json.loads(ai_request.content)
        assert sent["analysisId"] == request_body["analysisId"]
        assert sent["speakerCount"] == request_body["speakerCount"]
        assert sent["audioSource"]["sha256"] == request_body["audioSource"]["sha256"]
        return httpx.Response(200, json=response_body)

    client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )
    result = asyncio.run(
        client.analyze_speech(SpeechAnalysisRequest.model_validate(request_body))
    )

    assert result.text == "합성 전사 결과"


def _internal_request() -> SpeechAnalysisRequest:
    now = datetime.now(UTC)
    return SpeechAnalysisRequest(
        schemaVersion=1,
        analysisId="analysis_test_001",
        language="ko",
        speakerCount=2,
        audioSource={
            "type": "s3PresignedGet",
            "downloadUrl": "https://bucket.s3.amazonaws.com/audio.wav",
            "downloadUrlExpiresAt": now + timedelta(minutes=10),
            "sizeBytes": 123456,
            "sha256": "a" * 64,
        },
        dataExpiresAt=now + timedelta(hours=1),
    )


@pytest.mark.parametrize(
    ("response", "expected_code"),
    [
        (httpx.Response(500), "AI_SERVER_ERROR"),
        (httpx.Response(200, json={"unexpected": "synthetic"}), "INVALID_AI_RESPONSE"),
    ],
)
def test_ai_client_maps_failure_without_exposing_response(
    response: httpx.Response,
    expected_code: str,
) -> None:
    def handler(ai_request: httpx.Request) -> httpx.Response:
        response.request = ai_request
        return response

    client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(AppError) as captured:
        asyncio.run(client.analyze_speech(_internal_request()))

    assert captured.value.error_code == expected_code
    assert "synthetic" not in captured.value.message


def test_ai_client_rejects_a_response_for_another_analysis() -> None:
    def handler(ai_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            request=ai_request,
            json={
                "schemaVersion": 1,
                "analysisId": "analysis_other",
                "language": "ko",
                "durationMs": 1,
                "text": "합성",
                "segments": [],
            },
        )

    client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(AppError) as captured:
        asyncio.run(client.analyze_speech(_internal_request()))

    assert captured.value.error_code == "INVALID_AI_RESPONSE"
