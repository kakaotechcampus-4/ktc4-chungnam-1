"""4-1 카드 생성 처리 검증. 실제 LLM 대신 결과를 흉내 내는 생성 함수를 씀.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). 값은 모두 합성 데이터.
"""

import pytest

from app.core.config import Settings
from app.core.database import connect
from app.schemas.card_generation import (
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


async def _seed(connection):
    """평가까지 끝난 회차(결정 하나 포함)와 평가 전 회차가 있는 프로필에 running 작업 생성."""
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
    pending_set, _ = await completed_card_set(connection, profile_id)
    await visit_with(connection, profile_id, pending_set, evaluated=False)
    topic_id = await value(
        connection, "SELECT topic_id FROM conversation_cards WHERE card_id = %s", (old_cards[0],)
    )
    proposal_id = await value(
        connection,
        "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id,"
        " suggested_action, reason, status) VALUES (%s, %s, %s, %s, 'more', '합성 이유', 'settled')"
        " RETURNING proposal_id",
        (done, profile_id, old_cards[0], topic_id),
    )
    await connection.execute(
        "INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action)"
        " VALUES (%s, %s, %s, 'more')",
        (profile_id, topic_id, proposal_id),
    )
    set_id = await value(
        connection,
        "INSERT INTO card_sets (profile_id, status, model, prompt_version)"
        " VALUES (%s, 'running', 'synthetic-model', '2') RETURNING set_id",
        (profile_id,),
    )
    return profile_id, set_id, old_set, topic_id


def _process(database_url, generate):
    queue = CardGenerationQueue()
    processor = CardGenerationProcessor(queue=queue, generate=generate)

    async def scenario():
        async with connect(database_url) as connection:
            _, set_id, _, _ = await _seed(connection)
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
        lambda result: setattr(result.cards[3], "card_title", "가" * 101),
        lambda result: setattr(result.cards[4].topic, "title", "   "),
    ],
    ids=[
        "eleven-cards",
        "two-follow-ups",
        "unknown-profile-field",
        "missing-evidence",
        "unknown-fact",
        "long-title",
        "blank-topic-title",
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


def test_worker_needs_database_and_ml_key():
    with pytest.raises(RuntimeError):
        create_worker(Settings(_env_file=None, database_url="postgresql://x/y"), fake_result)
    with pytest.raises(RuntimeError):
        card_generator(Settings(_env_file=None))
