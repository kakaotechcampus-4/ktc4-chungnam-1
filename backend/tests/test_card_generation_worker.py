"""4-1 카드 생성 처리 검증. 실제 LLM 대신 결과를 흉내 내는 생성 함수를 씀.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). 값은 모두 합성 데이터.
"""

import json

import card_generation as ai
import card_generation.generate as card_generation_module
import httpx
import openai
import pytest
from common.llm import ENDPOINTS
from langchain_core.exceptions import OutputParserException
from psycopg.types.json import Jsonb

from app.core.config import Settings
from app.core.database import connect
from app.schemas.card_generation import (
    CardContext,
    CardGenerationRequest,
    CardGenerationResult,
    GeneratedCard,
    GeneratedTopic,
)
from app.services.card_generation_jobs import CardGenerationQueue
from app.services.card_sets import (
    CardGenerationError,
    CardGenerationProcessor,
    build_context,
)
from app.workers.card_generation import card_generator, create_worker
from tests.card_fixtures import (
    completed_card_set,
    user_and_profile,
    value,
    visit_with,
    with_db,
)
from tests.support import run

EXTRA = {"kind": "general", "pickReason": "합성 이유"}


def fake_result(request, *, reuse_topic=None, positions=range(1, 13)) -> CardGenerationResult:
    """2번 카드는 세부 정보(취미) 근거. 1번 카드는 `reuse_topic`이 있으면 기존 주제."""
    cards = []
    for position in positions:
        evidence = [{"profileField": "hobby"}] if position == 2 else []
        if reuse_topic and position == 1:
            topic = GeneratedTopic(topic_id=reuse_topic)
        else:
            topic = GeneratedTopic(
                title=f"새 합성 주제 {position}", description="합성 설명", evidence=evidence
            )
        cards.append(
            GeneratedCard(
                position=position,
                topic=topic,
                card_title=f"새 카드 {position}",
                description="합성 설명",
                primary_question="합성 질문이었어요?",
                follow_up_questions=["하나?", "둘?", "셋?"],
                evidence_source="profile" if position == 2 else "none",
                evidence=evidence,
                extra=EXTRA,
            )
        )
    return CardGenerationResult(
        model=request.model,
        prompt_version=request.prompt_version,
        cards=cards,
        log={"candidates": 18},
    )


async def _seed(connection, actions=("more",)):
    """평가까지 끝난 회차(결정 포함)와 평가 전 회차가 있는 프로필에 running 작업 생성.

    결정은 이전 묶음 1번 카드 주제에 대한 `actions`. 두 번째부터는 그 주제를 새 묶음에서 다시
    쓰고 평가까지 끝낸 회차에서 내린 결정이고, `decided_at`도 순서대로 늦어짐."""
    user_id, profile_id = await user_and_profile(connection)
    await connection.execute(
        "UPDATE profiles SET hobby = '합성 취미' WHERE profile_id = %s", (profile_id,)
    )
    await connection.execute(
        "INSERT INTO life_facts (profile_id, title, content) VALUES (%s, '합성 제목', '합성 이야기')",
        (profile_id,),
    )
    await connection.execute(
        "INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, model,"
        " prompt_version) VALUES (%s, %s, '합성 사진 설명', 'completed', 'm', 'p')",
        (profile_id, f"synthetic/{profile_id}/done.jpg"),
    )
    await connection.execute(
        "INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, %s)",
        (profile_id, f"synthetic/{profile_id}/pending.jpg"),
    )
    old_set, old_cards = await completed_card_set(connection, profile_id)
    done = await visit_with(connection, profile_id, old_set, evaluated=True)
    await connection.execute(
        "UPDATE visit_sessions SET evaluation_note = '합성 평가 메모' WHERE session_id = %s",
        (done,),
    )
    topic_id = await value(
        connection, "SELECT topic_id FROM conversation_cards WHERE card_id = %s", (old_cards[0],)
    )
    session_id, card_id = done, old_cards[0]
    for order, action in enumerate(actions):
        if order:
            again_set, again_cards = await completed_card_set(connection, profile_id)
            card_id = again_cards[0]
            await connection.execute(
                "UPDATE conversation_cards SET topic_id = %s WHERE card_id = %s", (topic_id, card_id)
            )
            session_id = await visit_with(connection, profile_id, again_set, evaluated=True)
        proposal_id = await value(
            connection,
            "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id,"
            " suggested_action, reason, status) VALUES (%s, %s, %s, %s, %s, '합성 이유', 'settled')"
            " RETURNING proposal_id",
            (session_id, profile_id, card_id, topic_id, action),
        )
        await connection.execute(
            "INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action, decided_at)"
            " VALUES (%s, %s, %s, %s, now() + make_interval(mins => %s))",
            (profile_id, topic_id, proposal_id, action, order),
        )
    pending_set, _ = await completed_card_set(connection, profile_id)
    await visit_with(connection, profile_id, pending_set, evaluated=False)
    set_id = await value(
        connection,
        "INSERT INTO card_sets (profile_id, status, model, prompt_version)"
        " VALUES (%s, 'running', 'synthetic-model', '2') RETURNING set_id",
        (profile_id,),
    )
    return profile_id, set_id, old_set, topic_id


def _process(database_url, generate, *, actions=("more",)):
    queue = CardGenerationQueue()
    processor = CardGenerationProcessor(queue=queue, generate=generate)

    async def scenario():
        async with connect(database_url) as connection:
            _, set_id, _, _ = await _seed(connection, actions)
            job = await queue.claim(connection, lease_seconds=600)
            await processor(connection, job)
            cursor = await connection.execute("SELECT * FROM card_sets WHERE set_id = %s", (set_id,))
            card_set = await cursor.fetchone()
            cursor = await connection.execute(
                "SELECT * FROM conversation_cards WHERE set_id = %s ORDER BY position", (set_id,)
            )
            return card_set, await cursor.fetchall()

    return run(scenario())


def test_context_has_only_what_card_generation_may_see(migrated_database_url):
    async def build(connection):
        profile_id, _, old_set, topic_id = await _seed(connection)
        return await build_context(connection, profile_id), old_set, topic_id

    context, old_set, topic_id = with_db(migrated_database_url, build)

    text = context.model_dump_json(by_alias=True)
    for hidden in ("합성이름", "합성 증상 메모", "mildDementia", "합성 평가 메모", "합성 이유", "female", "1943"):
        assert hidden not in text, hidden
    assert context.age_range == "80s" and context.profile_facts.hobby == "합성 취미"
    assert [fact.source for fact in context.life_facts] == ["caregiver"]
    assert [photo.description for photo in context.photos] == ["합성 사진 설명"]
    assert [visit.set_id for visit in context.visits] == [old_set]
    assert len(context.past_cards) == 12 and {c.set_id for c in context.past_cards} == {old_set}
    feedback = {topic.topic_id: [f.action for f in topic.feedback] for topic in context.topics}
    assert feedback[topic_id] == ["more"]


def test_context_drops_evidence_of_deleted_life_facts(migrated_database_url):
    """일대기에서 지운 이야기(2-9)를 가리키는 근거는 context에서만 빠짐. 저장된 근거는 그대로."""

    async def build(connection):
        profile_id, _, old_set, topic_id = await _seed(connection)
        kept = await value(
            connection, "SELECT fact_id FROM life_facts WHERE profile_id = %s", (profile_id,)
        )
        deleted = await value(
            connection,
            "INSERT INTO life_facts (profile_id, title, content)"
            " VALUES (%s, '지울 제목', '지울 이야기') RETURNING fact_id",
            (profile_id,),
        )
        await connection.execute(
            "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
            (Jsonb([{"factId": str(deleted)}, {"profileField": "hobby"}]), topic_id),
        )
        await connection.execute(
            "UPDATE conversation_cards SET evidence_source = 'life_fact', evidence = %s"
            " WHERE set_id = %s AND topic_id = %s",
            (Jsonb([{"factId": str(deleted)}, {"factId": str(kept)}]), old_set, topic_id),
        )
        await connection.execute("DELETE FROM life_facts WHERE fact_id = %s", (deleted,))
        context = await build_context(connection, profile_id)
        stored = await value(
            connection, "SELECT evidence FROM profile_topics WHERE topic_id = %s", (topic_id,)
        )
        return context, old_set, topic_id, kept, deleted, stored

    context, old_set, topic_id, kept, deleted, stored = with_db(migrated_database_url, build)

    assert [fact.fact_id for fact in context.life_facts] == [kept]
    topic = next(t for t in context.topics if t.topic_id == topic_id)
    assert topic.evidence == [{"profileField": "hobby"}]
    card = next(c for c in context.past_cards if c.set_id == old_set and c.topic_id == topic_id)
    assert card.evidence == [{"factId": str(kept)}]
    assert str(deleted) not in context.model_dump_json(by_alias=True)
    assert stored == [{"factId": str(deleted)}, {"profileField": "hobby"}]


def test_generated_cards_and_new_topics_are_saved(migrated_database_url):
    seen = {}

    def generate(request):
        seen["request"] = request
        return fake_result(request, reuse_topic=request.context.topics[0].topic_id)

    card_set, cards = _process(migrated_database_url, generate)

    request = seen["request"]
    assert (request.schema_version, request.model, request.prompt_version) == (1, "synthetic-model", 2)
    assert card_set["status"] == "completed" and card_set["lease_expires_at"] is None
    assert card_set["generation_log"]["input"]["ageRange"] == "80s"
    assert card_set["generation_log"]["log"] == {"candidates": 18}
    assert card_set["generation_log"]["cards"][0] == {"position": 1, **EXTRA}
    assert [card["position"] for card in cards] == list(range(1, 13))
    assert cards[0]["topic_id"] == request.context.topics[0].topic_id
    assert (cards[1]["evidence_source"], cards[1]["evidence"]) == (
        "profile",
        [{"profileField": "hobby"}],
    )


def test_generation_error_fails_the_job_with_its_code_and_input(migrated_database_url):
    def generate(request):
        raise CardGenerationError("NOT_ENOUGH_TOPICS", "합성 실패")

    card_set, cards = _process(migrated_database_url, generate)

    assert (card_set["status"], card_set["error_code"]) == ("failed", "NOT_ENOUGH_TOPICS")
    assert card_set["generation_log"]["input"]["ageRange"] == "80s"
    assert cards == []


@pytest.mark.parametrize(
    "break_result",
    [
        lambda result: result.cards.pop(),  # 11장
        lambda result: result.cards[0].follow_up_questions.pop(),  # 꼬리 질문 2개
        lambda result: setattr(result.cards[1], "evidence", [{"profileField": "age"}]),
        lambda result: setattr(result.cards[1], "evidence", []),  # profile인데 근거 없음
        lambda result: setattr(result.cards[2], "evidence_source", "lifeFact")
        or setattr(result.cards[2], "evidence", [{"factId": "00000000-0000-4000-8000-000000000999"}]),
        lambda result: setattr(result.cards[1], "evidence", [{"profileField": "hometown"}]),
        lambda result: setattr(result.cards[2], "evidence_source", "lifeFact")
        or setattr(result.cards[2], "evidence", [{"profileField": "hobby"}]),
        lambda result: setattr(result.cards[3], "card_title", "가" * 101),
        lambda result: setattr(result.cards[4].topic, "title", "   "),
        lambda result: setattr(result.cards[5], "primary_question", " \n"),
        lambda result: result.cards[6].follow_up_questions.__setitem__(1, "  "),
        lambda result: setattr(result.cards[7], "card_title", ""),
        lambda result: setattr(result.cards[8], "description", "\t"),
    ],
    ids=[
        "eleven-cards",
        "two-follow-ups",
        "unknown-profile-field",
        "missing-evidence",
        "unknown-fact",
        "empty-profile-field",
        "evidence-kind-mismatch",
        "long-title",
        "blank-topic-title",
        "blank-primary-question",
        "blank-follow-up",
        "blank-card-title",
        "blank-description",
    ],
)
def test_result_that_breaks_the_contract_is_not_saved(migrated_database_url, break_result):
    def generate(request):
        result = fake_result(request)
        break_result(result)
        return result

    card_set, cards = _process(migrated_database_url, generate)

    assert (card_set["status"], card_set["error_code"]) == ("failed", "INVALID_GENERATION_RESULT")
    assert cards == []


@pytest.mark.parametrize(
    "actions, status",
    [
        (("exclude",), "failed"),
        (("more", "exclude"), "failed"),
        (("more",), "completed"),
    ],
    ids=["excluded", "excluded-later", "not-excluded"],
)
def test_excluded_topic_is_not_saved(migrated_database_url, actions, status):
    seen = {}

    def generate(request):
        seen["topic"] = request.context.topics[0]
        return fake_result(request, reuse_topic=request.context.topics[0].topic_id)

    card_set, cards = _process(migrated_database_url, generate, actions=actions)

    assert [feedback.action for feedback in seen["topic"].feedback] == list(actions)
    assert card_set["status"] == status
    assert len(cards) == (12 if status == "completed" else 0)


def test_worker_needs_database_and_ml_key():
    with pytest.raises(RuntimeError):
        create_worker(Settings(_env_file=None, database_url="postgresql://x/y"), fake_result)
    with pytest.raises(RuntimeError):
        card_generator(Settings(_env_file=None))


def fake_ai_result(request: ai.GenerationRequest) -> ai.GenerationResult:
    """`fake_result`와 같은 카드를 ai 카드 생성 패키지의 결과 형식으로."""
    be_request = CardGenerationRequest.model_validate(request.model_dump(mode="json", by_alias=True))
    result = fake_result(be_request, reuse_topic=be_request.context.topics[0].topic_id)
    data = result.model_dump(mode="json", by_alias=True)
    for card in data["cards"]:
        card["extra"] = {
            "kind": "general",
            "bucket": "new",
            "angle": "겨울날 아랫목에서 쉬던 때",
            "pickReason": "새 이야기 자리",
            "agentReason": "아직 다루지 않은 계절 이야기",
            "matchReason": "같은 이야기의 기존 주제가 없음",
        }
    return ai.GenerationResult.model_validate(data)


def _ai_generator(monkeypatch, generate_cards):
    monkeypatch.setattr(ai, "generate_cards", generate_cards)
    return card_generator(Settings(_env_file=None, ml_api_key="synthetic-key"))


def test_card_generator_saves_what_the_ai_package_returns(migrated_database_url, monkeypatch):
    seen = {}

    def generate_cards(request, *, api_key):
        seen["request"], seen["api_key"] = request, api_key
        return fake_ai_result(request)

    card_set, cards = _process(migrated_database_url, _ai_generator(monkeypatch, generate_cards))

    request = seen["request"]
    assert isinstance(request, ai.GenerationRequest) and seen["api_key"] == "synthetic-key"
    assert request.context.age_range == "80s" and request.context.profile_facts.hobby == "합성 취미"
    assert card_set["status"] == "completed"
    assert set(card_set["generation_log"]["cards"][0]) == {
        "position", "kind", "bucket", "angle", "pickReason", "agentReason", "matchReason"
    }
    assert len(cards) == 12 and str(cards[0]["topic_id"]) == request.context.topics[0].topic_id


def test_card_generator_keeps_the_ai_failure_code(migrated_database_url, monkeypatch):
    def generate_cards(request, *, api_key):
        raise ai.CardGenerationError("NOT_ENOUGH_TOPICS", "다시 찾아도 주제가 모자람")

    card_set, cards = _process(migrated_database_url, _ai_generator(monkeypatch, generate_cards))

    assert (card_set["status"], card_set["error_code"]) == ("failed", "NOT_ENOUGH_TOPICS")
    assert cards == []


def test_card_generator_refuses_to_start_with_a_model_the_ai_package_cannot_call():
    """4-1이 저장할 모델이 ENDPOINTS에 없으면 작업마다 실패하므로 worker를 시작하지 않는다."""
    assert Settings(_env_file=None).card_generation_model in ENDPOINTS
    with pytest.raises(RuntimeError, match="SAEROK_CARD_GENERATION_MODEL"):
        card_generator(
            Settings(_env_file=None, ml_api_key="synthetic-key", card_generation_model="synthetic-model")
        )


# ── 생성 오류 구분(#143) ─────────────────────────────────────
# `ai/`의 실제 generate_cards 안에서 모델을 부르는 단계(recommend)에 예외를 넣는다.
# _seed의 작업은 합성 모델 이름이라 ENDPOINTS에 있는 모델과 있는 판으로 바꿔 부른다.

_SYNTHETIC_REQUEST = httpx.Request("POST", "https://synthetic.invalid/v1/responses")
_CARD_CALL_ERRORS = {
    "connection": (lambda: openai.APIConnectionError(request=_SYNTHETIC_REQUEST), "LLM_UNAVAILABLE"),
    "timeout": (lambda: openai.APITimeoutError(request=_SYNTHETIC_REQUEST), "LLM_UNAVAILABLE"),
    "bad_request": (
        lambda: openai.BadRequestError(
            "synthetic", response=httpx.Response(400, request=_SYNTHETIC_REQUEST), body=None
        ),
        "CARD_GENERATION_FAILED",
    ),
    "truncated_json": (
        lambda: OutputParserException('synthetic {"cards": [{"cardTitle": "합성'),
        "CARD_GENERATION_FAILED",
    ),
    "json_decode": (
        lambda: json.JSONDecodeError("Unterminated string", '{"cards": [{"cardTitle": "합성', 10),
        "CARD_GENERATION_FAILED",
    ),
    # 후보를 하나도 못 찾으면 카드 12장을 채울 수 없어 실패다(카드에는 0장 정상 완료가 없음).
    "no_candidates": (lambda: card_generation_module.RecommendFailed("synthetic"), "NOT_ENOUGH_TOPICS"),
}


@pytest.mark.parametrize("case", list(_CARD_CALL_ERRORS))
def test_card_model_call_errors_keep_the_ai_failure_code(migrated_database_url, monkeypatch, case):
    make_error, error_code = _CARD_CALL_ERRORS[case]
    called = []
    real_generate_cards = ai.generate_cards

    def fail(*args, **kwargs):
        called.append(case)
        raise make_error()

    def generate_cards(request, *, api_key):
        sent = request.model_copy(update={"model": next(iter(ENDPOINTS)), "prompt_version": 1})
        return real_generate_cards(sent, api_key=api_key, time_limit=5)

    monkeypatch.setattr(card_generation_module, "recommend", fail)
    card_set, cards = _process(migrated_database_url, _ai_generator(monkeypatch, generate_cards))

    assert called == [case]
    assert (card_set["status"], card_set["error_code"]) == ("failed", error_code)
    assert cards == []


def test_card_generator_turns_a_context_the_ai_package_rejects_into_invalid_context(monkeypatch):
    def generate_cards(request, *, api_key):
        raise AssertionError("형식이 틀리면 부르지 않아야 함")

    request = CardGenerationRequest(
        model="synthetic-model",
        prompt_version=1,
        context=CardContext.model_validate(
            {
                "ageRange": "여든",
                "profileFacts": {"occupation": None, "hometown": None, "hobby": None, "family": None},
                "lifeFacts": [],
                "photos": [],
                "topics": [],
                "visits": [],
                "pastCards": [],
            }
        ),
    )
    with pytest.raises(CardGenerationError) as error:
        _ai_generator(monkeypatch, generate_cards)(request)
    assert error.value.code == "INVALID_CONTEXT"
