"""FCM HTTP v1 발송 클라이언트 검증.

Google 인증 서버와 FCM 은 `httpx.MockTransport` 로 대신한다. 서비스 계정 키는 테스트에서
새로 만든 합성 RSA 키이고 FID 도 합성이다.
"""

import json
import logging
import time

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.clients.fcm import FCM_SCOPE, FcmClient, SendResult, ServiceAccount
from tests.support import run

FID = "cSyntheticFidAAAAAAAAA"
SESSION_ID = "00000000-0000-4000-8000-000000000001"
ANALYSIS_ID = "00000000-0000-4000-8000-000000000002"
TOKEN_URI = "https://oauth2.example.test/token"
SEND_URL = "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send"

_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PRIVATE_PEM = _KEY.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()
PUBLIC_KEY = _KEY.public_key()


def _account() -> ServiceAccount:
    return ServiceAccount(
        project_id="synthetic-project",
        client_email="push@synthetic-project.iam.example.test",
        private_key=PRIVATE_PEM,
        private_key_id="synthetic-key-id",
        token_uri=TOKEN_URI,
    )


class FakeGoogle:
    """인증 서버와 FCM 을 함께 흉내 낸다. 보낼 응답을 차례로 정할 수 있다."""

    def __init__(self) -> None:
        self.token_requests: list[httpx.Request] = []
        self.sends: list[httpx.Request] = []
        self.send_responses: list[httpx.Response] = []
        self.token_response: httpx.Response | None = None
        self.issued = 0

    def handler(self, request: httpx.Request) -> httpx.Response:
        if str(request.url) == TOKEN_URI:
            self.token_requests.append(request)
            if self.token_response is not None:
                return self.token_response
            self.issued += 1
            return httpx.Response(
                200, json={"access_token": f"access-{self.issued}", "expires_in": 3600}
            )
        assert str(request.url) == SEND_URL
        self.sends.append(request)
        if self.send_responses:
            return self.send_responses.pop(0)
        return httpx.Response(200, json={"name": "projects/synthetic-project/messages/1"})


class Clock:
    def __init__(self) -> None:
        # 서명한 요청을 실제 시각으로 검증하므로 지금에서 시작한다.
        self.now = time.time()

    def __call__(self) -> float:
        return self.now


def _client(google: FakeGoogle, clock: Clock | None = None) -> FcmClient:
    return FcmClient(
        _account(),
        transport=httpx.MockTransport(google.handler),
        clock=clock or Clock(),
    )


def _send(client: FcmClient) -> SendResult:
    return run(
        client.send_report_ready(FID, session_id=SESSION_ID, analysis_id=ANALYSIS_ID)
    )


def _fcm_error(status: int, code: str) -> httpx.Response:
    return httpx.Response(
        status,
        json={
            "error": {
                "code": status,
                "status": "NOT_FOUND" if status == 404 else "INVALID_ARGUMENT",
                "details": [
                    {
                        "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                        "errorCode": code,
                    }
                ],
            }
        },
    )


def test_sends_a_fixed_notification_to_the_fid_with_a_signed_token():
    google = FakeGoogle()

    result = _send(_client(google))

    assert result is SendResult.SENT
    [token_request] = google.token_requests
    form = dict(httpx.QueryParams(token_request.content.decode()))
    assert form["grant_type"] == "urn:ietf:params:oauth:grant-type:jwt-bearer"
    claims = jwt.decode(
        form["assertion"], PUBLIC_KEY, algorithms=["RS256"], audience=TOKEN_URI
    )
    assert claims["iss"] == "push@synthetic-project.iam.example.test"
    assert claims["scope"] == FCM_SCOPE
    assert jwt.get_unverified_header(form["assertion"])["kid"] == "synthetic-key-id"

    [send] = google.sends
    assert send.headers["Authorization"] == "Bearer access-1"
    # 알림에는 고정 문구와 회차·분석 ID 만 담는다.
    assert json.loads(send.content) == {
        "message": {
            "fid": FID,
            "notification": {"title": "새록", "body": "리포트가 준비되었어요"},
            "data": {
                "type": "reportReady",
                "sessionId": SESSION_ID,
                "analysisId": ANALYSIS_ID,
            },
            "android": {"priority": "high"},
        }
    }


def test_failure_notification_has_a_fixed_text_and_no_error_detail():
    google = FakeGoogle()
    client = _client(google)

    result = run(
        client.send_report_failed(FID, session_id=SESSION_ID, analysis_id=ANALYSIS_ID)
    )

    assert result is SendResult.SENT
    [send] = google.sends
    # 실패 코드와 이유, 어르신 이름은 담지 않는다.
    assert json.loads(send.content) == {
        "message": {
            "fid": FID,
            "notification": {"title": "새록", "body": "리포트를 만들지 못했어요"},
            "data": {
                "type": "reportFailed",
                "sessionId": SESSION_ID,
                "analysisId": ANALYSIS_ID,
            },
            "android": {"priority": "high"},
        }
    }


def test_reuses_the_access_token_until_it_is_about_to_expire():
    google = FakeGoogle()
    clock = Clock()
    client = _client(google, clock)

    _send(client)
    clock.now += 3600 - 120
    _send(client)
    clock.now += 90  # 만료 60초 전 안쪽
    _send(client)

    assert len(google.token_requests) == 2
    assert [s.headers["Authorization"] for s in google.sends] == [
        "Bearer access-1",
        "Bearer access-1",
        "Bearer access-2",
    ]


def test_only_unregistered_fids_are_reported_as_gone():
    google = FakeGoogle()
    google.send_responses = [
        _fcm_error(404, "UNREGISTERED"),
        # FID 문제일 수도, 본문 문제일 수도 있어 등록을 지우게 하지 않는다.
        _fcm_error(400, "INVALID_ARGUMENT"),
        httpx.Response(500),
        httpx.Response(429),
    ]
    client = _client(google)

    results = [_send(client) for _ in range(4)]

    assert results == [
        SendResult.UNREGISTERED,
        SendResult.FAILED,
        SendResult.FAILED,
        SendResult.FAILED,
    ]


def test_a_rejected_access_token_is_fetched_again_next_time():
    google = FakeGoogle()
    google.send_responses = [httpx.Response(401)]
    client = _client(google)

    first = _send(client)
    second = _send(client)

    assert (first, second) == (SendResult.FAILED, SendResult.SENT)
    assert len(google.token_requests) == 2


def test_token_failure_does_not_send():
    google = FakeGoogle()
    google.token_response = httpx.Response(400, json={"error": "invalid_grant"})

    result = _send(_client(google))

    assert result is SendResult.FAILED
    assert google.sends == []


def test_network_failure_is_a_failed_send():
    def unreachable(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("synthetic connection failure", request=request)

    client = FcmClient(_account(), transport=httpx.MockTransport(unreachable))

    assert _send(client) is SendResult.FAILED


def test_logs_do_not_carry_the_fid_or_tokens(caplog):
    google = FakeGoogle()
    google.send_responses = [_fcm_error(404, "UNREGISTERED")]
    caplog.set_level(logging.DEBUG, logger="saerok.fcm")

    _send(_client(google))

    assert "fcm_send_failed" in caplog.text
    assert FID not in caplog.text
    assert "access-1" not in caplog.text
    for record in caplog.records:
        assert FID not in json.dumps(record.__dict__, default=str)


def test_service_account_file_is_checked_without_echoing_its_values(tmp_path):
    good = tmp_path / "good.json"
    good.write_text(
        json.dumps(
            {
                "type": "service_account",
                "project_id": "synthetic-project",
                "client_email": "push@synthetic-project.iam.example.test",
                "private_key": PRIVATE_PEM,
                "private_key_id": "synthetic-key-id",
                "token_uri": TOKEN_URI,
            }
        ),
        encoding="utf-8",
    )
    missing = tmp_path / "missing.json"
    missing.write_text(
        json.dumps({"type": "service_account", "private_key": PRIVATE_PEM}),
        encoding="utf-8",
    )
    other = tmp_path / "other.json"
    other.write_text(json.dumps({"type": "authorized_user"}), encoding="utf-8")

    assert ServiceAccount.from_file(str(good)).project_id == "synthetic-project"
    with pytest.raises(RuntimeError) as missing_error:
        ServiceAccount.from_file(str(missing))
    assert "project_id" in str(missing_error.value)
    assert "PRIVATE KEY" not in str(missing_error.value)
    with pytest.raises(RuntimeError):
        ServiceAccount.from_file(str(other))
    with pytest.raises(RuntimeError):
        ServiceAccount.from_file(str(tmp_path / "absent.json"))
