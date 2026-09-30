import json

import httpx

from app.clients.ai_server import AiServerClient
from app.main import create_app
from tests.support import request


REQUEST_BODY = {
    "schemaVersion": 1,
    "analysisId": "analysis_test_001",
    "language": "ko",
    "speakerCount": 2,
    "audioSource": {
        "type": "s3PresignedGet",
        "downloadUrl": (
            "https://bucket.s3.ap-northeast-2.amazonaws.com/audio.wav"
            "?X-Amz-Signature=synthetic"
        ),
        "downloadUrlExpiresAt": "2026-09-22T15:10:00+09:00",
        "sizeBytes": 123456,
        "sha256": "a" * 64,
    },
    "dataExpiresAt": "2026-09-22T16:00:00+09:00",
}

AI_RESPONSE_BODY = {
    "schemaVersion": 1,
    "analysisId": "analysis_test_001",
    "language": "ko",
    "durationMs": 3200,
    "text": "합성 전사 결과",
    "segments": [
        {
            "startMs": 0,
            "endMs": 3200,
            "speakerLabel": "SPEAKER_00",
            "text": "합성 전사 결과",
            "words": [
                {
                    "startMs": 0,
                    "endMs": 800,
                    "text": "합성",
                    "probability": 0.93,
                }
            ],
        }
    ],
}


def test_forwards_the_request_and_returns_the_validated_ai_response() -> None:
    def handler(ai_request: httpx.Request) -> httpx.Response:
        assert ai_request.method == "POST"
        assert ai_request.url.path == "/internal/v1/speech-analyses"
        assert json.loads(ai_request.content) == REQUEST_BODY
        return httpx.Response(200, json=AI_RESPONSE_BODY)

    application = create_app()
    application.state.ai_server_client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    response = request(
        application,
        "POST",
        "/api/v1/speech-analyses",
        json=REQUEST_BODY,
    )

    assert response.status_code == 200
    assert response.json() == AI_RESPONSE_BODY


def test_rejects_an_invalid_ai_response_without_exposing_it() -> None:
    invalid_response = {"unexpected": "sensitive-transcript-value"}

    def handler(ai_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=invalid_response, request=ai_request)

    application = create_app()
    application.state.ai_server_client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    response = request(
        application,
        "POST",
        "/api/v1/speech-analyses",
        json=REQUEST_BODY,
    )

    assert response.status_code == 502
    assert response.json()["errorCode"] == "INVALID_AI_RESPONSE"
    assert "sensitive-transcript-value" not in response.text


def test_maps_ai_server_failure_to_a_common_error_response() -> None:
    def handler(ai_request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, request=ai_request)

    application = create_app()
    application.state.ai_server_client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    response = request(
        application,
        "POST",
        "/api/v1/speech-analyses",
        json=REQUEST_BODY,
    )

    assert response.status_code == 502
    assert response.json()["errorCode"] == "AI_SERVER_ERROR"
    assert response.json()["retryable"] is True


def test_rejects_a_response_for_a_different_analysis() -> None:
    mismatched_response = {
        **AI_RESPONSE_BODY,
        "analysisId": "analysis_other_001",
    }

    def handler(ai_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=mismatched_response, request=ai_request)

    application = create_app()
    application.state.ai_server_client = AiServerClient(
        base_url="http://ai-server.test",
        timeout_seconds=10,
        transport=httpx.MockTransport(handler),
    )

    response = request(
        application,
        "POST",
        "/api/v1/speech-analyses",
        json=REQUEST_BODY,
    )

    assert response.status_code == 502
    assert response.json()["errorCode"] == "INVALID_AI_RESPONSE"
