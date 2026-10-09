"""임시 DB를 쓰는 API 테스트의 공통 준비.

계정은 DB에 직접 만들고, 세션은 테스트 서명 키로 발급해 실제 인증 경로(`CurrentAccountDep`)를
그대로 거친다. 값은 모두 합성 데이터다.
"""

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from fastapi import FastAPI
from httpx import Response

from app.api.deps import get_session_revocations, get_token_issuer
from app.core.config import Settings, get_settings
from app.core.database import connect
from app.main import create_app
from app.services.accounts import Account, ConsentRecord, PostgresAccountRepository
from app.services.session_revocations import InMemorySessionRevocationStore
from tests.support import request, run

SESSION_SECRET = "test-session-secret-value-32bytes-long"
CONSENT_VERSION = "2026-09-06"
SIGNED_UP_AT = datetime(2026, 8, 21, 2, 40, tzinfo=UTC)


class DbApi:
    def __init__(self, database_url: str) -> None:
        self.database_url = database_url
        self.settings = Settings(
            _env_file=None,
            session_secret=SESSION_SECRET,
            consent_version=CONSENT_VERSION,
            database_url=database_url,
        )
        self.app: FastAPI = create_app()
        self.app.dependency_overrides[get_settings] = lambda: self.settings
        revocations = InMemorySessionRevocationStore()
        self.app.dependency_overrides[get_session_revocations] = lambda: revocations
        self._issuer = get_token_issuer(self.settings)

    def create_account(self, social_id: str | None = None) -> "Caregiver":
        """필수 동의를 마친 계정을 만들고 그 계정의 세션을 발급한다."""
        account = Account(
            account_id=str(uuid4()),
            provider="google",
            social_id=social_id or f"synthetic-sub-{uuid4().hex[:8]}",
            display_name="합성 보호자",
            email=None,
            consent_version=CONSENT_VERSION,
            consents={
                "serviceData": ConsentRecord(granted=True, granted_at=SIGNED_UP_AT),
                "sensitiveData": ConsentRecord(granted=True, granted_at=SIGNED_UP_AT),
                "serviceImprovement": ConsentRecord(granted=False, granted_at=None),
                "pushNotification": ConsentRecord(
                    granted=True, granted_at=SIGNED_UP_AT
                ),
            },
            created_at=SIGNED_UP_AT,
        )

        async def create() -> None:
            async with connect(self.database_url) as connection:
                await PostgresAccountRepository(
                    connection, default_display_name="보호자"
                ).create(account)

        run(create())
        token = self._issuer.issue_session(account.account_id).value
        return Caregiver(self, account.account_id, token)

    def query(self, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
        async def execute() -> list[dict[str, Any]]:
            async with connect(self.database_url) as connection:
                cursor = await connection.execute(sql, params)
                return await cursor.fetchall() if cursor.description else []

        return run(execute())


class Caregiver:
    """세션을 가진 보호자 한 명. 요청에 그 세션을 붙인다."""

    def __init__(self, api: DbApi, account_id: str, token: str) -> None:
        self.api = api
        self.account_id = account_id
        self.token = token

    def call(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
    ) -> Response:
        return request(
            self.api.app,
            method,
            path,
            json=json,
            headers={"Authorization": f"Bearer {self.token}"},
        )

    def create_profile(self, **overrides: Any) -> dict[str, Any]:
        response = self.call("POST", "/api/v1/profiles", json=profile_body(**overrides))
        assert response.status_code == 201, response.text
        return response.json()


def profile_body(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "name": "합성 어르신",
        "gender": "female",
        "birthDate": "1943-03-12",
        "condition": {"stage": "mildCognitiveImpairment", "symptomNote": None},
    }
    body.update(overrides)
    return body
