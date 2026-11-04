import io
import json
import wave
from uuid import UUID

import httpx
import pytest

from scripts.verify_api_cycle import CheckFailed, Cycle, main, read_wav, validate_origin


def uid(number):
    return str(UUID(int=number))


class Clock:
    def __init__(self):
        self.value = 0

    def now(self):
        return self.value

    def sleep(self, duration):
        self.value += duration


class Server:
    """Contract-shaped responses only. Not a replacement for the DB cycle test."""

    def __init__(self, mode="success"):
        self.mode = mode
        self.requests = []
        self.generation = 0
        self.sessions = 0
        self.approved = False
        self.corrected = False
        self.polls = 0
        self.content = "合成-secret-generated-content"

    def handler(self, request):
        self.requests.append(request)
        path, method = request.url.path, request.method
        if self.mode == "network":
            raise httpx.ReadTimeout("private token and url", request=request)
        if path == "/auth/me":
            return httpx.Response(
                200,
                json={
                    "accountId": uid(999) if self.mode == "wrong-account" else uid(1),
                    "consent": {
                        key: {"granted": self.mode != "no-consent"}
                        for key in ("serviceData", "sensitiveData")
                    },
                },
            )
        if self.mode == "redirect":
            return httpx.Response(307, headers={"location": "https://private.invalid"})
        if path == "/api/v1/profiles" and method == "POST":
            return httpx.Response(201, json={"profileId": uid(2)})
        if path == "/api/v1/profiles/" + uid(2):
            facts = (
                [{"factId": uid(6), "content": self.content}] if self.approved else []
            )
            return httpx.Response(200, json={"lifeFacts": facts})
        if path.endswith("/card-generations"):
            self.generation += 1
            self.corrected = False
            return httpx.Response(202, json={"status": "running"})
        if path.endswith("/card-generations/status"):
            state = "running" if self.mode == "timeout" else "ready"
            return httpx.Response(200, json={"status": state})
        if path.endswith("/card-generations/current"):
            cards = [
                {
                    "cardId": uid(1000 * self.generation + i),
                    "topic": {"topicId": uid(1000 * self.generation + 100 + i)},
                }
                for i in range(12)
            ]
            if self.mode == "excluded" and self.generation > 1:
                cards[0]["topic"]["topicId"] = uid(1100)
            if self.mode == "duplicate":
                cards[1]["cardId"] = cards[0]["cardId"]
            return httpx.Response(
                200,
                json={
                    "setId": uid(100 + self.generation),
                    "cards": cards,
                    "needsRefresh": self.corrected,
                },
            )
        if path == "/api/v1/visit-sessions":
            if self.corrected:
                return httpx.Response(409, json={"errorCode": "CARD_SET_NEEDS_REFRESH"})
            self.sessions += 1
            return httpx.Response(201, json={"sessionId": uid(200 + self.sessions)})
        if path.endswith("/evaluation"):
            return httpx.Response(201, json={})
        if path.endswith("/speech-analyses"):
            return httpx.Response(202, json={"analysisId": uid(4)})
        if "/speech-analyses/" in path:
            states = [
                "queued",
                "transcribing",
                "sttCompleted",
                "generatingReport",
                "completed",
            ]
            status = states[min(self.polls, len(states) - 1)]
            self.polls += 1
            if self.mode == "speech-failed":
                status = "failed"
            return httpx.Response(
                200, json={"status": status, "errorCode": "private error"}
            )
        if path.endswith("/report"):
            return httpx.Response(200, json={"body": "private synthetic report"})
        if path.endswith("/proposals"):
            return httpx.Response(
                200,
                json={
                    "lifeFactProposals": []
                    if self.mode == "no-story"
                    else [
                        {
                            "proposalId": uid(5),
                            "title": "synthetic",
                            "content": self.content,
                        }
                    ],
                    "topicProposals": []
                    if self.mode == "no-topics"
                    else [{"proposalId": uid(7), "topic": {"topicId": uid(1100)}}],
                },
            )
        if path.endswith("/proposals/review"):
            body = json.loads(request.content)
            assert body["lifeFacts"][0]["proposalId"] == uid(5)
            self.approved = True
            return httpx.Response(200, json={})
        if "/life-facts/" in path:
            self.corrected = True
            self.content = json.loads(request.content)["content"]
            return httpx.Response(200, json={})
        raise AssertionError(f"Unexpected local test route: {method} {path}")


def execute(mode="success"):
    server, clock = Server(mode), Clock()
    with httpx.Client(
        base_url="https://synthetic.invalid",
        transport=httpx.MockTransport(server.handler),
    ) as client:
        result = Cycle(
            client, wait_seconds=5, poll_seconds=1, clock=clock.now, sleep=clock.sleep
        ).run(uid(1), b"synthetic", 2)
    return server, result


def test_whole_cycle_redacts_content_and_never_deletes():
    server, result = execute()
    assert result["outcome"] == "passed_api_flow"
    assert len(result["stages"]) == 12
    assert result["topicExclusionChecked"] is True
    assert result["resources"]["secondSessionId"] == uid(202)
    encoded = json.dumps(result)
    assert "private" not in encoded and "secret-generated" not in encoded
    assert all(request.method != "DELETE" for request in server.requests)
    assert (
        sum(
            request.url.path.endswith("/proposals/review")
            for request in server.requests
        )
        == 1
    )


@pytest.mark.parametrize(
    "mode,code",
    [
        ("wrong-account", "TEST_ACCOUNT_MISMATCH"),
        ("no-consent", "REQUIRED_CONSENT_MISSING"),
        ("network", "NETWORK_ERROR"),
        ("redirect", "UNEXPECTED_HTTP_307"),
        ("timeout", "POLL_TIMEOUT"),
        ("duplicate", "DUPLICATE_CARD_ID"),
        ("speech-failed", "JOB_NOT_SUCCESSFUL"),
        ("no-story", "NO_STORY_CANDIDATE_CYCLE_NOT_VERIFIED"),
        ("excluded", "EXCLUDED_TOPIC_RETURNED"),
    ],
)
def test_incomplete_is_not_success(mode, code):
    server, result = execute(mode)
    assert result["outcome"] == "incomplete"
    assert result["stages"][-1]["code"] == code
    if mode in {"wrong-account", "no-consent", "network"}:
        assert all(request.method == "GET" for request in server.requests)
    if mode == "no-story":
        assert not any(
            request.url.path.endswith("/proposals/review")
            for request in server.requests
        )
    assert "private" not in json.dumps(result)


def test_no_topic_proposals_marks_exclusion_not_tested():
    _, result = execute("no-topics")
    assert result["outcome"] == "passed_api_flow"
    assert result["topicExclusionChecked"] is False


def test_default_plan_does_not_open_client(monkeypatch, capsys):
    def forbidden(*args, **kwargs):
        pytest.fail("Network client opened in plan mode")

    monkeypatch.setattr(httpx, "Client", forbidden)
    assert main([]) == 0
    assert json.loads(capsys.readouterr().out)["requestsSent"] == 0


@pytest.mark.parametrize(
    "url,remote,code",
    [
        ("https://server.invalid", False, "REMOTE_EXECUTION_NOT_ACKNOWLEDGED"),
        ("http://server.invalid", True, "REMOTE_HTTPS_REQUIRED"),
        ("https://token@server.invalid", True, "INVALID_BASE_URL"),
        ("https://server.invalid?secret=1", True, "INVALID_BASE_URL"),
        ("https://server.invalid/path", True, "INVALID_BASE_URL"),
        ("https://server.invalid:bad", True, "INVALID_BASE_URL"),
    ],
)
def test_origin_gate(url, remote, code):
    with pytest.raises(CheckFailed, match=code):
        validate_origin(url, remote)


def test_local_url_and_explicit_remote_allowed():
    assert validate_origin("http://127.0.0.1:8000/", False) == "http://127.0.0.1:8000"
    assert validate_origin("https://server.invalid/", True) == "https://server.invalid"


def test_wav_header_and_truncation(tmp_path):
    stream = io.BytesIO()
    with wave.open(stream, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16000)
        audio.writeframes(b"\x00\x00" * 1600)
    path = tmp_path / "synthetic.wav"
    path.write_bytes(stream.getvalue())
    assert read_wav(path) == stream.getvalue()
    path.write_bytes(stream.getvalue()[:-100])
    with pytest.raises(CheckFailed, match="SYNTHETIC_WAV_TRUNCATED"):
        read_wav(path)


def test_unreadable_input_has_no_path_or_token(capsys):
    assert (
        main(
            [
                "--execute-synthetic-test",
                "--token-file",
                "missing-private-token-file",
                "--test-account-id",
                uid(1),
                "--synthetic-wav",
                "missing.wav",
            ]
        )
        == 1
    )
    output = capsys.readouterr().out
    assert "LOCAL_INPUT_UNREADABLE" in output
    assert "missing-private-token-file" not in output


def test_runner_against_actual_routes_database_and_workers(
    migrated_database_url, monkeypatch
):
    from app.core.database import connect
    from app.services.speech_analysis_jobs import PostgresSpeechAnalysisJobRepository
    from app.services.speech_analysis_pipeline import create_speech_worker
    from tests.support import run
    from tests.test_second_visit_flow import SecondVisitFlow
    from tests.test_speech_analyses import synthetic_wav
    from tests.test_visit_report_generator import (
        FakeAi,
        _connected,
        _connected_generator,
    )

    flow = SecondVisitFlow(migrated_database_url)
    _connected(monkeypatch)
    speech_worker = create_speech_worker(
        jobs_for=lambda connection: PostgresSpeechAnalysisJobRepository(
            connection, lease_seconds=900
        ),
        audio_storage=flow.storage,
        ai_server=FakeAi().client(),
        open_connection=lambda: connect(migrated_database_url),
        lease_seconds=900,
        report_generator=_connected_generator(),
    )

    def send(request):
        async def forward():
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=flow.app),
                base_url="http://testserver",
            ) as app_client:
                return await app_client.request(
                    request.method,
                    request.url.path,
                    content=request.content,
                    headers=request.headers,
                )

        response = run(forward())
        if response.status_code < 300 and request.method == "POST":
            if request.url.path == "/api/v1/profiles":
                flow.profile_id = response.json()["profileId"]
                flow.base = f"/api/v1/profiles/{flow.profile_id}"
            elif request.url.path.endswith("/card-generations"):
                flow.generate()
            elif request.url.path.endswith("/speech-analyses"):
                assert run(speech_worker.run_once())
        return httpx.Response(
            response.status_code, content=response.content, headers=response.headers
        )

    with httpx.Client(
        base_url="http://testserver", transport=httpx.MockTransport(send)
    ) as client:
        result = Cycle(client).run(str(flow.user_id), synthetic_wav(), 2)
    assert result["outcome"] == "passed_api_flow", result
    assert result["topicExclusionChecked"] is True
    assert len(flow.card_requests) == 3
    assert (
        flow.card_requests[-1]
        .context.life_facts[0]
        .content.startswith("합성 시험의 정정:")
    )
