import asyncio
from datetime import UTC, datetime, timedelta
import json
import logging

import httpx
import pytest

from app.clients.ai_server import AiServerClient
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisRequest


@pytest.fixture
def payload() -> SpeechAnalysisRequest:
    now = datetime.now(UTC)
    return SpeechAnalysisRequest(
        schemaVersion=1,
        analysisId="synthetic_failover_analysis",
        language="ko",
        speakerCount=2,
        audioSource={
            "type": "s3PresignedGet",
            "downloadUrl": "https://bucket.s3.amazonaws.com/synthetic.wav?signature=synthetic",
            "downloadUrlExpiresAt": now + timedelta(minutes=10),
            "sizeBytes": 1024,
            "sha256": "a" * 64,
        },
        dataExpiresAt=now + timedelta(hours=1),
    )


def success(payload: SpeechAnalysisRequest) -> httpx.Response:
    return httpx.Response(200, json={
        "schemaVersion": 1,
        "analysisId": payload.analysis_id,
        "language": "ko",
        "durationMs": 1000,
        "text": "합성 전사",
        "segments": [],
    })


def client(handler, **kwargs) -> AiServerClient:
    return AiServerClient(
        base_url="http://primary.test",
        backup_base_url="http://backup.test",
        timeout_seconds=kwargs.pop("timeout_seconds", 10),
        transport=httpx.MockTransport(handler),
        **kwargs,
    )


def test_healthy_primary_does_not_call_backup(payload) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        return success(payload)

    result = asyncio.run(client(handler).analyze_speech(payload))
    assert result.analysis_id == payload.analysis_id
    assert calls == ["primary.test"]


@pytest.mark.parametrize("error_type", [httpx.ConnectError, httpx.ConnectTimeout])
def test_connection_failure_calls_backup_once_with_unchanged_payload(payload, error_type) -> None:
    calls = []
    bodies = []

    def handler(request):
        calls.append(request.url.host)
        bodies.append(json.loads(request.content))
        assert request.extensions["timeout"]["connect"] == 5
        if request.url.host == "primary.test":
            raise error_type("synthetic private detail", request=request)
        return success(payload)

    result = asyncio.run(client(handler).analyze_speech(payload))
    assert result.analysis_id == payload.analysis_id
    assert calls == ["primary.test", "backup.test"]
    assert bodies == [payload.model_dump(mode="json", by_alias=True)] * 2


def test_next_job_starts_with_primary_again(payload) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        if calls == ["primary.test"]:
            raise httpx.ConnectError("synthetic", request=request)
        return success(payload)

    async def analyze_twice():
        instance = client(handler)
        await instance.analyze_speech(payload)
        await instance.analyze_speech(payload)

    asyncio.run(analyze_twice())
    assert calls == ["primary.test", "backup.test", "primary.test"]


@pytest.mark.parametrize("error_type, code", [
    (httpx.ReadTimeout, "AI_SERVER_TIMEOUT"),
    (httpx.WriteTimeout, "AI_SERVER_TIMEOUT"),
    (httpx.RemoteProtocolError, "AI_SERVER_UNAVAILABLE"),
])
def test_ambiguous_inflight_failure_is_not_retransmitted(payload, error_type, code) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        raise error_type("synthetic", request=request)

    with pytest.raises(AppError) as error:
        asyncio.run(client(handler).analyze_speech(payload))
    assert error.value.error_code == code
    assert calls == ["primary.test"]


@pytest.mark.parametrize("status", [400, 429, 500, 503])
def test_application_error_does_not_trigger_backup(payload, status) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        return httpx.Response(status)

    with pytest.raises(AppError) as error:
        asyncio.run(client(handler).analyze_speech(payload))
    assert error.value.error_code == "AI_SERVER_ERROR"
    assert calls == ["primary.test"]


@pytest.mark.parametrize("wrong_id", [False, True])
def test_bad_response_is_not_hidden_by_a_backup_result(payload, wrong_id) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        if wrong_id:
            body = json.loads(success(payload).content)
            body["analysisId"] = "another_synthetic_analysis"
            return httpx.Response(200, json=body)
        return httpx.Response(200, json={"unexpected": "synthetic"})

    with pytest.raises(AppError) as error:
        asyncio.run(client(handler).analyze_speech(payload))
    assert error.value.error_code == "INVALID_AI_RESPONSE"
    assert calls == ["primary.test"]


def test_two_unreachable_servers_end_after_two_attempts(payload) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        raise httpx.ConnectError("synthetic", request=request)

    with pytest.raises(AppError) as error:
        asyncio.run(client(handler).analyze_speech(payload))
    assert error.value.error_code == "AI_SERVER_UNAVAILABLE"
    assert error.value.retryable is True
    assert calls == ["primary.test", "backup.test"]


def test_primary_and_backup_share_one_deadline(payload) -> None:
    calls = []

    async def handler(request):
        calls.append(request.url.host)
        if request.url.host == "primary.test":
            await asyncio.sleep(0.02)
            raise httpx.ConnectError("synthetic", request=request)
        await asyncio.sleep(1)
        return success(payload)

    with pytest.raises(AppError) as error:
        asyncio.run(client(handler, timeout_seconds=0.1).analyze_speech(payload))
    assert error.value.error_code == "AI_SERVER_TIMEOUT"
    assert calls == ["primary.test", "backup.test"]


def test_external_cancellation_does_not_start_backup(payload) -> None:
    calls = []

    async def handler(request):
        calls.append(request.url.host)
        raise asyncio.CancelledError()

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(client(handler).analyze_speech(payload))
    assert calls == ["primary.test"]


def test_backup_log_contains_no_request_or_connection_details(payload, caplog) -> None:
    def handler(request):
        if request.url.host == "primary.test":
            raise httpx.ConnectError("synthetic private detail", request=request)
        return success(payload)

    with caplog.at_level(logging.WARNING, logger="saerok.ai_server"):
        asyncio.run(client(handler).analyze_speech(payload))
    events = [r.getMessage() for r in caplog.records if r.name == "saerok.ai_server"]
    assert events == ["speech_analysis_backup_used reason=connect_failure"]


@pytest.mark.parametrize("backup_url", [
    "http://primary.test/", "file:///tmp/model", "not-a-url",
    "http://user:password@backup.test", "http://backup.test?secret=value",
])
def test_rejects_duplicate_or_unsafe_backup_urls(backup_url) -> None:
    with pytest.raises(ValueError):
        AiServerClient(base_url="http://primary.test", timeout_seconds=10,
                       backup_base_url=backup_url)


def test_backup_is_disabled_by_default_and_preserves_connection_timeout(payload) -> None:
    calls = []

    def handler(request):
        calls.append(request.url.host)
        assert request.extensions["timeout"]["connect"] == 10
        raise httpx.ConnectError("synthetic", request=request)

    instance = AiServerClient(base_url="http://primary.test", timeout_seconds=10,
                              transport=httpx.MockTransport(handler))
    with pytest.raises(AppError):
        asyncio.run(instance.analyze_speech(payload))
    assert calls == ["primary.test"]


def test_api_factory_passes_backup_settings(monkeypatch) -> None:
    from app import main
    from app.core.config import Settings

    settings = Settings(_env_file=None, ai_server_backup_url="http://backup.test",
                        ai_server_failover_connect_timeout_seconds=3)
    monkeypatch.setattr(main, "get_settings", lambda: settings)
    instance = main.create_app().state.ai_server_client
    assert instance._base_url == settings.ai_server_url
    assert instance._backup_base_url == settings.ai_server_backup_url
    assert instance._failover_timeout.connect == 3


def test_speech_worker_factory_passes_backup_settings_without_connecting(monkeypatch) -> None:
    from app.core.config import Settings
    from app.workers import speech_analysis

    settings = Settings(_env_file=None, environment="test",
                        database_url="postgresql://synthetic.test/synthetic",
                        speech_audio_s3_bucket="synthetic-bucket",
                        ai_server_backup_url="http://backup.test",
                        ai_server_failover_connect_timeout_seconds=3)
    monkeypatch.setattr(speech_analysis, "S3AudioStorage", lambda **kwargs: object())
    monkeypatch.setattr(speech_analysis, "create_speech_worker", lambda **kwargs: kwargs)
    configured = speech_analysis.create_worker(settings, stt_only=True)
    instance = configured["ai_server"]
    assert instance._base_url == settings.ai_server_url
    assert instance._backup_base_url == settings.ai_server_backup_url
    assert instance._failover_timeout.connect == 3
