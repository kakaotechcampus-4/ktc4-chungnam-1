"""backend가 넘기는 context로 카드를 만드는 경로. LLM은 부르지 않는다.

- context 조립이 숨길 정보를 넣지 않고, 평가가 끝나지 않은 회차를 빼는지
- 모르는 promptVersion을 INVALID_CONTEXT로 거르는지
"""

from __future__ import annotations

from datetime import datetime, timezone

import psycopg
import pytest
from pydantic import ValidationError

from card_generation.contract import CardContext, CardGenerationError, GenerationRequest
from card_generation.generate import generate_cards
from simulation.backends.context import build_context


def _context(db_url: str, profile_id: str) -> CardContext:
    with psycopg.connect(db_url) as conn:
        return build_context(conn, profile_id)


def test_context_has_no_hidden_profile_fields(db_url, seeded):
    text = _context(db_url, seeded.profile_a).model_dump_json(by_alias=True)
    for word in ("합성이름", "합성 증상 메모", "mildDementia", "합성 평가 메모", "승인 전 제안", "gender", "birth"):
        assert word not in text, word


def test_unevaluated_visit_is_left_out(db_url, seeded):
    before = len(_context(db_url, seeded.profile_a).visits)
    with psycopg.connect(db_url, autocommit=True) as conn:
        sid = conn.execute("INSERT INTO visit_sessions (profile_id, started_at) VALUES (%s, %s) RETURNING session_id",
                           (seeded.profile_a, datetime.now(timezone.utc))).fetchone()[0]
        try:
            assert len(_context(db_url, seeded.profile_a).visits) == before
        finally:
            conn.execute("DELETE FROM visit_sessions WHERE session_id = %s", (sid,))


def _request(db_url, seeded, **change) -> GenerationRequest:
    ctx = _context(db_url, seeded.profile_a).model_dump(by_alias=True)
    data = {"model": "gpt-5.6-luna", "promptVersion": 1, "context": ctx}
    for path, value in change.items():
        data["context"][path] = value(data["context"][path]) if callable(value) else value
    return GenerationRequest.model_validate(data)


def test_unknown_prompt_version_is_rejected(db_url, seeded):
    req = _request(db_url, seeded).model_copy(update={"prompt_version": 9})
    with pytest.raises(CardGenerationError) as e:
        generate_cards(req, api_key="x")
    assert e.value.code == "INVALID_CONTEXT"


def test_unknown_model_is_rejected(db_url, seeded):
    req = _request(db_url, seeded).model_copy(update={"model": "unknown-model"})
    with pytest.raises(CardGenerationError) as e:
        generate_cards(req, api_key="x")
    assert e.value.code == "INVALID_CONTEXT" and "model" in e.value.message


def test_contract_checks_age_range():
    with pytest.raises(ValidationError):
        CardContext.model_validate({"ageRange": "80", "profileFacts": {}})
    ok = CardContext.model_validate({"ageRange": "80s", "profileFacts": {"hobby": "노래"},
                                     "topics": [{"topicId": "t", "title": "a", "description": "b", "evidence": [{"profileField": "hobby"}]}]})
    assert ok.profile_facts.hobby == "노래"
