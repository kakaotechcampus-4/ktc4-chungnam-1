"""FCM HTTP v1 로 리포트 완료 푸시를 보낸다.

Firebase 서비스 계정 키로 Google OAuth 접근 토큰을 받고(JWT bearer 방식),
`projects/{projectId}/messages:send` 에 기기의 FID 를 대상으로 보낸다. FCM 은 기기
토큰(`token`) 대신 FID(`fid`)로 보내도록 바꿨다.

키 파일, 접근 토큰과 FID 는 로그와 예외 메시지에 남기지 않는다. 실패는 HTTP 상태와
FCM 오류 코드만 남긴다.
"""

from __future__ import annotations

import enum
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
import jwt

logger = logging.getLogger("saerok.fcm")

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_SEND_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
JWT_BEARER_GRANT = "urn:ietf:params:oauth:grant-type:jwt-bearer"
# 접근 토큰이 이 시간 안에 만료되면 새로 받는다.
TOKEN_REFRESH_MARGIN_SECONDS = 60
# 서명한 인증 요청의 수명. Google 은 1시간까지 받는다.
ASSERTION_LIFETIME_SECONDS = 3600


class SendResult(enum.Enum):
    SENT = "sent"
    # 이 FID 는 더 이상 받을 수 없다(404 UNREGISTERED). 저장한 등록을 지운다.
    UNREGISTERED = "unregistered"
    # 그 밖의 실패. 등록은 그대로 두고 이번 알림만 포기한다.
    FAILED = "failed"


@dataclass(frozen=True)
class ServiceAccount:
    """Firebase 콘솔에서 받은 서비스 계정 키의 필요한 값."""

    project_id: str
    client_email: str
    private_key: str
    private_key_id: str | None
    token_uri: str

    @classmethod
    def from_file(cls, path: str) -> ServiceAccount:
        """키 파일을 읽는다. 형식이 맞지 않으면 값은 담지 않고 빠진 항목만 알린다."""
        try:
            raw = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise RuntimeError(
                f"FCM 서비스 계정 키 파일을 읽지 못했습니다: {type(error).__name__}"
            ) from None
        if not isinstance(raw, dict) or raw.get("type") != "service_account":
            raise RuntimeError("FCM 키 파일이 서비스 계정 키 형식이 아닙니다.")
        missing = [
            name
            for name in ("project_id", "client_email", "private_key", "token_uri")
            if not isinstance(raw.get(name), str) or not raw[name]
        ]
        if missing:
            raise RuntimeError(f"FCM 서비스 계정 키에 없는 항목: {missing}")
        return cls(
            project_id=raw["project_id"],
            client_email=raw["client_email"],
            private_key=raw["private_key"],
            private_key_id=raw.get("private_key_id"),
            token_uri=raw["token_uri"],
        )


class FcmClient:
    """리포트 완료 알림을 FID 하나에 보낸다. 접근 토큰은 만료 전까지 다시 쓴다."""

    def __init__(
        self,
        account: ServiceAccount,
        *,
        timeout_seconds: float = 10.0,
        transport: httpx.AsyncBaseTransport | None = None,
        clock: Any = time.time,
    ) -> None:
        self._account = account
        self._timeout = httpx.Timeout(timeout_seconds)
        self._transport = transport
        self._clock = clock
        self._token: str | None = None
        self._token_expires_at = 0.0
        self._send_url = FCM_SEND_URL.format(project_id=account.project_id)

    async def send_report_ready(
        self, fid: str, *, session_id: str, analysis_id: str
    ) -> SendResult:
        """리포트가 준비됐다고 알린다.

        알림에는 고정 문구와 회차·분석 ID 만 담는다. 어르신 이름과 리포트 내용은 담지
        않는다. 앱은 회차 ID 로 리포트(7-2)를 다시 읽는다.
        """
        message = {
            "message": {
                "fid": fid,
                "notification": {"title": "새록", "body": "리포트가 준비되었어요"},
                "data": {
                    "type": "reportReady",
                    "sessionId": session_id,
                    "analysisId": analysis_id,
                },
                "android": {"priority": "high"},
            }
        }
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout, transport=self._transport
            ) as client:
                token = await self._access_token(client)
                response = await client.post(
                    self._send_url,
                    json=message,
                    headers={"Authorization": f"Bearer {token}"},
                )
        except (httpx.HTTPError, _TokenError) as error:
            logger.warning("fcm_send_failed", extra={"reason": type(error).__name__})
            return SendResult.FAILED
        if response.is_success:
            return SendResult.SENT
        error_code = _fcm_error_code(response)
        if response.status_code == 401:
            # 받아 둔 토큰이 거절됐다. 다음 발송에서 새로 받는다.
            self._token = None
        logger.warning(
            "fcm_send_failed",
            extra={"status_code": response.status_code, "fcm_error": error_code},
        )
        # 404 UNREGISTERED 만 등록이 끝났다고 본다. 400 INVALID_ARGUMENT 는 FID 문제일
        # 수도 있지만 알림 본문 문제일 수도 있어 등록을 지우지 않는다(FCM 등록 관리 안내).
        if response.status_code == 404 and error_code == "UNREGISTERED":
            return SendResult.UNREGISTERED
        return SendResult.FAILED

    async def _access_token(self, client: httpx.AsyncClient) -> str:
        now = self._clock()
        if self._token and now < self._token_expires_at - TOKEN_REFRESH_MARGIN_SECONDS:
            return self._token
        account = self._account
        headers = {"kid": account.private_key_id} if account.private_key_id else None
        try:
            assertion = jwt.encode(
                {
                    "iss": account.client_email,
                    "scope": FCM_SCOPE,
                    "aud": account.token_uri,
                    "iat": int(now),
                    "exp": int(now) + ASSERTION_LIFETIME_SECONDS,
                },
                account.private_key,
                algorithm="RS256",
                headers=headers,
            )
        except (ValueError, TypeError, jwt.PyJWTError) as error:
            raise _TokenError(type(error).__name__) from None
        response = await client.post(
            account.token_uri,
            data={"grant_type": JWT_BEARER_GRANT, "assertion": assertion},
        )
        if not response.is_success:
            raise _TokenError(f"token_status_{response.status_code}")
        try:
            body = response.json()
            token = body["access_token"]
            expires_in = float(body.get("expires_in", 3600))
        except (ValueError, KeyError, TypeError):
            raise _TokenError("token_response") from None
        if not isinstance(token, str) or not token:
            raise _TokenError("token_response")
        self._token = token
        self._token_expires_at = now + expires_in
        return token


class _TokenError(Exception):
    """접근 토큰을 받지 못했다. 메시지에는 원인 종류만 담는다."""


def _fcm_error_code(response: httpx.Response) -> str | None:
    """FCM 오류 응답의 `details[].errorCode`. 없으면 `error.status`."""
    try:
        error = response.json()["error"]
    except (ValueError, KeyError, TypeError):
        return None
    if not isinstance(error, dict):
        return None
    for detail in error.get("details") or []:
        if isinstance(detail, dict) and isinstance(detail.get("errorCode"), str):
            return detail["errorCode"]
    status = error.get("status")
    return status if isinstance(status, str) else None
