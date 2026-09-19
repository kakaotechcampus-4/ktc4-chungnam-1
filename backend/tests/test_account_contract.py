"""공통 계정 목 데이터가 실제 인증 응답 모델로 읽히는지 확인한다."""

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.auth import AccountResponse


def _account_fixture() -> dict[str, object]:
    repo = Path(__file__).resolve().parents[2]
    source = repo / "docs/architecture/mock/account.json"
    copy = repo / "app/assets/mock/account.json"
    source_payload = json.loads(source.read_text(encoding="utf-8"))
    assert source_payload == json.loads(copy.read_text(encoding="utf-8"))
    return source_payload["account"]


def test_shared_account_fixture_matches_auth_response() -> None:
    payload = _account_fixture()
    assert "loginId" not in payload
    assert payload["email"] is None

    account = AccountResponse.model_validate(payload)

    assert account.account_id == "account_demo_001"
    assert account.auth_provider == "google"
    assert account.email is None


@pytest.mark.parametrize("email", [None, "demo@example.com"])
def test_account_email_accepts_null_or_string(email: str | None) -> None:
    payload = _account_fixture()
    payload["email"] = email

    assert AccountResponse.model_validate(payload).email == email


def test_missing_account_email_stays_absent() -> None:
    payload = _account_fixture()
    del payload["email"]

    assert AccountResponse.model_validate(payload).email is None


def test_account_email_rejects_invalid_type() -> None:
    payload = _account_fixture()
    payload["email"] = 42

    with pytest.raises(ValidationError):
        AccountResponse.model_validate(payload)
