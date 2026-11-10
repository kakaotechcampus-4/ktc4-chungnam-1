"""4-1 카드 생성 처리 검증. 실제 LLM 대신 결과를 흉내 내는 생성 함수를 씀.

임시 DB에 최신 migration을 적용해 실행(`conftest.py`). 값은 모두 합성 데이터.
"""

import asyncio
import json
import logging
import re
from types import SimpleNamespace

import card_generation as ai
import card_generation.generate as card_generation_module
import httpx
import openai
import psycopg
import pytest
from common.llm import ENDPOINTS
from langchain_core.exceptions import OutputParserException
from psycopg.types.json import Jsonb

from app.core.config import Settings
from app.core.database import connect, psycopg_dsn
from app.core.logging import SafeJsonFormatter
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
    result_problems,
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
HANGUL = re.compile(r"[가-힣]")
SENSITIVE_POSITIONS = {2, 7}


def assert_no_text(generation_log) -> None:
    """기록에 이야기, 세부 정보, 사진 설명, 주제와 카드 문구가 없음. 합성 글은 모두 한글임."""
    assert not HANGUL.search(json.dumps(generation_log, ensure_ascii=False)), generation_log


def sent_ids(context: CardContext) -> dict:
    """생성에 보낸 context 가운데 기록(`generation_log.input`)에 남아야 하는 값."""
    return {
        "ageRange": context.age_range,
        "profileFields": [
            field
            for field in ("occupation", "hometown", "hobby", "family")
            if getattr(context.profile_facts, field)
        ],
        "lifeFactIds": [str(fact.fact_id) for fact in context.life_facts],
        "photoIds": [str(photo.photo_id) for photo in context.photos],
        "topicIds": [str(topic.topic_id) for topic in context.topics],
        "visitSessionIds": [str(visit.session_id) for visit in context.visits],
        "pastCardIds": [str(card.card_id) for card in context.past_cards],
    }


def fake_result(request, *, reuse_topic=None, positions=range(1, 13)) -> CardGenerationResult:
    """2번 카드는 세부 정보(취미) 근거. 1번 카드는 `reuse_topic`이 있으면 기존 주제.

    `SENSITIVE_POSITIONS`의 카드는 아픈 경험을 다루는 카드로 표시한다.
    """
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
                sensitive=position in SENSITIVE_POSITIONS,
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
        # 허용한 생성 시각에 생년과 같은 숫자가 있어도 개인정보 유출은 아니다.
        await connection.execute(
            "UPDATE profile_topics SET created_at = '2026-11-03T00:00:00.541943Z' "
            "WHERE profile_id = %s", (profile_id,),
        )
        return await build_context(connection, profile_id), old_set, topic_id

    context, old_set, topic_id = with_db(migrated_database_url, build)

    text = context.model_dump_json(by_alias=True)
    for hidden in ("합성이름", "합성 증상 메모", "mildDementia", "합성 평가 메모", "합성 이유", "female", "1943-04-01"):
        assert hidden not in text, hidden
    assert set(context.model_dump(by_alias=True)) == {
        "ageRange", "profileFacts", "lifeFacts", "photos", "topics", "visits", "pastCards",
    }
    assert set(context.profile_facts.model_dump(by_alias=True)) == {
        "occupation", "hometown", "hobby", "family",
    }
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


def test_context_drops_stories_and_photos_behind_excluded_topics(migrated_database_url):
    """보호자가 제외한 주제의 근거 이야기와 사진은 다음 생성 입력에서 빠짐.

    같은 이야기로 이름만 다른 새 주제가 다시 나오지 않게 함. 세부 정보 칸, 다른 이야기,
    제외한 주제 자체와 결정, 저장된 근거는 그대로."""

    async def build(connection):
        profile_id, _, old_set, topic_id = await _seed(connection, ("exclude",))
        refused = await value(
            connection, "SELECT fact_id FROM life_facts WHERE profile_id = %s", (profile_id,)
        )
        photo = await value(
            connection,
            "SELECT photo_id FROM photos WHERE profile_id = %s AND analysis_status = 'completed'",
            (profile_id,),
        )
        other = await value(
            connection,
            "INSERT INTO life_facts (profile_id, title, content)"
            " VALUES (%s, '다른 제목', '다른 이야기') RETURNING fact_id",
            (profile_id,),
        )
        excluded_evidence = [{"factId": str(refused)}, {"photoId": str(photo)}, {"profileField": "hobby"}]
        await connection.execute(
            "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
            (Jsonb(excluded_evidence), topic_id),
        )
        # 제외하지 않은 다른 주제가 같은 이야기와 다른 이야기를 함께 근거로 씀
        kept_topic = await value(
            connection,
            "SELECT topic_id FROM conversation_cards WHERE set_id = %s AND position = 2",
            (old_set,),
        )
        await connection.execute(
            "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
            (Jsonb([{"factId": str(refused)}, {"factId": str(other)}]), kept_topic),
        )
        await connection.execute(
            "UPDATE conversation_cards SET evidence_source = 'life_fact', evidence = %s"
            " WHERE set_id = %s AND topic_id = %s",
            (Jsonb([{"factId": str(refused)}]), old_set, topic_id),
        )
        context = await build_context(connection, profile_id)
        stored = await value(
            connection, "SELECT evidence FROM profile_topics WHERE topic_id = %s", (topic_id,)
        )
        return context, old_set, topic_id, kept_topic, refused, photo, other, stored, excluded_evidence

    context, old_set, topic_id, kept_topic, refused, photo, other, stored, excluded_evidence = with_db(
        migrated_database_url, build
    )

    assert [fact.fact_id for fact in context.life_facts] == [other]
    assert context.photos == []
    assert context.profile_facts.hobby == "합성 취미"
    topics = {topic.topic_id: topic for topic in context.topics}
    assert [f.action for f in topics[topic_id].feedback] == ["exclude"]
    assert topics[topic_id].evidence == [{"profileField": "hobby"}]
    assert topics[kept_topic].evidence == [{"factId": str(other)}]
    card = next(c for c in context.past_cards if c.set_id == old_set and c.topic_id == topic_id)
    assert card.evidence == []
    text = context.model_dump_json(by_alias=True)
    assert str(refused) not in text and str(photo) not in text
    assert stored == excluded_evidence

    # 생성 함수가 그래도 그 이야기를 근거로 쓰면 결과 검증에서 거절
    result = fake_result(SimpleNamespace(model="synthetic-model", prompt_version="2"))
    result.cards[2] = result.cards[2].model_copy(
        update={"evidence_source": "lifeFact", "evidence": [{"factId": str(refused)}]}
    )
    assert any(problem.startswith("3번") for problem in result_problems(result, context))


def test_topic_whose_story_and_photo_evidence_is_gone_is_not_sent(migrated_database_url):
    """이야기나 사진 근거가 모두 지워졌거나 입력에서 빠진 주제는 다음 생성 입력에서 뺌(PM 결정 2026-11-08).

    남은 이야기나 사진, 세부 정보 칸 근거가 있는 주제와 근거가 없던 주제는 그대로 넣음. 보호자가
    제외한 주제는 근거 이야기가 DB에 남아 있으므로 입력에서 근거만 빠지고 주제는 남음(근거를 지운
    경우는 다음 시험). 지난 카드는 바꾸지 않음."""

    async def build(connection):
        profile_id, _, old_set, excluded = await _seed(connection, ("exclude",))
        kept = await value(
            connection, "SELECT fact_id FROM life_facts WHERE profile_id = %s", (profile_id,)
        )
        photo = await value(
            connection,
            "SELECT photo_id FROM photos WHERE profile_id = %s AND analysis_status = 'completed'",
            (profile_id,),
        )
        deleted, refused = [
            await value(
                connection,
                "INSERT INTO life_facts (profile_id, title, content)"
                " VALUES (%s, %s, '합성 이야기') RETURNING fact_id",
                (profile_id, title),
            )
            for title in ("지울 제목", "거절한 제목")
        ]
        deleted_photo = await value(
            connection,
            "INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, model,"
            " prompt_version) VALUES (%s, %s, '지울 사진 설명', 'completed', 'm', 'p')"
            " RETURNING photo_id",
            (profile_id, f"synthetic/{profile_id}/deleted.jpg"),
        )
        cursor = await connection.execute(
            "SELECT position, topic_id FROM conversation_cards WHERE set_id = %s", (old_set,)
        )
        topics = {row["position"]: row["topic_id"] for row in await cursor.fetchall()}
        assert topics[1] == excluded
        evidence = {
            1: [{"factId": str(refused)}],  # 제외한 주제. 근거 이야기는 남아 있고 입력에서만 빠짐
            2: [{"factId": str(deleted)}],  # 지운 이야기만
            3: [{"photoId": str(deleted_photo)}],  # 지운 사진만
            4: [{"factId": str(refused)}],  # 제외한 주제와 같은 이야기만
            5: [{"factId": str(deleted)}, {"factId": str(kept)}],
            6: [{"profileField": "hobby"}],
            7: [{"factId": str(deleted)}, {"profileField": "hobby"}],
            8: [{"photoId": str(deleted_photo)}, {"photoId": str(photo)}],
        }
        for position, items in evidence.items():
            await connection.execute(
                "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
                (Jsonb(items), topics[position]),
            )
        await connection.execute("DELETE FROM life_facts WHERE fact_id = %s", (deleted,))
        await connection.execute("DELETE FROM photos WHERE photo_id = %s", (deleted_photo,))
        return await build_context(connection, profile_id), old_set, topics, kept, photo

    context, old_set, topics, kept, photo = with_db(migrated_database_url, build)

    sent = {topic.topic_id: topic for topic in context.topics}
    assert [f.action for f in sent[topics[1]].feedback] == ["exclude"]
    assert sent[topics[1]].evidence == []
    for position in (2, 3, 4):
        assert topics[position] not in sent, position
    assert sent[topics[5]].evidence == [{"factId": str(kept)}]
    assert sent[topics[6]].evidence == [{"profileField": "hobby"}]
    assert sent[topics[7]].evidence == [{"profileField": "hobby"}]
    assert sent[topics[8]].evidence == [{"photoId": str(photo)}]
    assert all(topics[position] in sent for position in range(9, 13))
    # 지난 카드는 그대로. 빠진 주제를 가리키는 지난 카드가 있어도 결과 검증은 통과
    assert {c.topic_id for c in context.past_cards if c.set_id == old_set} == set(topics.values())
    request = SimpleNamespace(model="synthetic-model", prompt_version="2")
    assert result_problems(fake_result(request), context) == []
    # 빠진 주제를 다시 쓰면 입력에 없는 주제라 거절
    reused = fake_result(request, reuse_topic=topics[2])
    assert any(problem.startswith("1번") for problem in result_problems(reused, context))


async def _exclude(connection, profile_id, set_id, topic_id):
    """`set_id` 묶음을 쓴 회차에서 보호자가 `topic_id` 주제의 제외를 승인함."""
    cursor = await connection.execute(
        "SELECT s.session_id, c.card_id FROM card_sets s"
        "  JOIN conversation_cards c ON c.set_id = s.set_id"
        " WHERE s.set_id = %s AND c.topic_id = %s",
        (set_id, topic_id),
    )
    row = await cursor.fetchone()
    proposal_id = await value(
        connection,
        "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id,"
        " suggested_action, reason, status) VALUES (%s, %s, %s, %s, 'exclude', '합성 이유', 'settled')"
        " RETURNING proposal_id",
        (row["session_id"], profile_id, row["card_id"], topic_id),
    )
    await connection.execute(
        "INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action)"
        " VALUES (%s, %s, %s, 'exclude')",
        (profile_id, topic_id, proposal_id),
    )


def test_excluded_topic_is_not_sent_once_its_stories_and_photos_are_deleted(migrated_database_url):
    """제외한 주제는 근거 이야기와 사진에 종속됨(PM 결정 2026-11-09).

    근거 이야기와 사진은 제외 규칙으로 늘 입력에서 빠지므로, 넣을지는 보낸 입력이 아니라 DB에 남은
    이야기와 사진으로 정함. 하나라도 남아 있으면 '이 이야기로 만들지 말 것' 표시로 넣고, 보호자가
    모두 지웠으면 넣지 않음. 세부 정보 칸 근거가 있거나 근거가 없던 제외 주제는 그대로 넣음."""

    async def build(connection):
        profile_id, _, old_set, first = await _seed(connection, ("exclude",))
        kept = await value(
            connection, "SELECT fact_id FROM life_facts WHERE profile_id = %s", (profile_id,)
        )
        gone, gone_with_photo, gone_of_two, half, gone_beside_field, gone_beside_photo = [
            await value(
                connection,
                "INSERT INTO life_facts (profile_id, title, content)"
                " VALUES (%s, %s, '합성 이야기') RETURNING fact_id",
                (profile_id, title),
            )
            for title in (
                "지울 제목 1",
                "지울 제목 2",
                "지울 제목 3",
                "남길 제목",
                "지울 제목 4",
                "지울 제목 5",
            )
        ]
        gone_photo, kept_photo = [
            await value(
                connection,
                "INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, model,"
                " prompt_version) VALUES (%s, %s, '합성 사진 설명', 'completed', 'm', 'p')"
                " RETURNING photo_id",
                (profile_id, f"synthetic/{profile_id}/{name}.jpg"),
            )
            for name in ("deleted", "kept")
        ]
        cursor = await connection.execute(
            "SELECT position, topic_id FROM conversation_cards WHERE set_id = %s", (old_set,)
        )
        topics = {row["position"]: row["topic_id"] for row in await cursor.fetchall()}
        assert topics[1] == first
        evidence = {
            1: [{"factId": str(kept)}],  # 근거 이야기가 남아 있음
            2: [{"factId": str(gone)}],  # 근거 이야기를 지움
            3: [{"factId": str(gone_with_photo)}, {"photoId": str(gone_photo)}],  # 이야기와 사진을 모두 지움
            4: [{"factId": str(gone_of_two)}, {"factId": str(half)}],  # 두 이야기 중 하나만 지움
            5: [{"profileField": "hobby"}],  # 세부 정보 칸만
            6: [],  # 근거가 없던 주제
            7: [{"factId": str(gone_beside_field)}, {"profileField": "hobby"}],  # 세부 정보 칸이 남음
            8: [{"factId": str(gone_beside_photo)}, {"photoId": str(kept_photo)}],  # 사진이 남음
        }
        for position, items in evidence.items():
            await connection.execute(
                "UPDATE profile_topics SET evidence = %s WHERE topic_id = %s",
                (Jsonb(items), topics[position]),
            )
            if position > 1:
                await _exclude(connection, profile_id, old_set, topics[position])
        for fact_id in (gone, gone_with_photo, gone_of_two, gone_beside_field, gone_beside_photo):
            await connection.execute("DELETE FROM life_facts WHERE fact_id = %s", (fact_id,))
        await connection.execute("DELETE FROM photos WHERE photo_id = %s", (gone_photo,))
        context = await build_context(connection, profile_id)
        stored = await value(
            connection, "SELECT evidence FROM profile_topics WHERE topic_id = %s", (topics[2],)
        )
        return context, old_set, topics, kept, half, kept_photo, gone, stored

    context, old_set, topics, kept, half, kept_photo, gone, stored = with_db(
        migrated_database_url, build
    )

    sent = {topic.topic_id: topic for topic in context.topics}
    for position in (1, 4, 5, 6, 7, 8):
        assert [f.action for f in sent[topics[position]].feedback] == ["exclude"], position
    # 남은 근거 이야기와 사진은 제외 규칙대로 입력에서 빠짐
    for position in (1, 4, 8):
        assert sent[topics[position]].evidence == [], position
    assert {fact.fact_id for fact in context.life_facts}.isdisjoint({kept, half})
    assert kept_photo not in {photo.photo_id for photo in context.photos}
    assert sent[topics[5]].evidence == [{"profileField": "hobby"}]
    assert sent[topics[6]].evidence == []
    assert sent[topics[7]].evidence == [{"profileField": "hobby"}]
    for position in (2, 3):
        assert topics[position] not in sent, position
    assert all(topics[position] in sent for position in range(9, 13))
    # 저장된 주제와 지난 카드는 그대로
    assert stored == [{"factId": str(gone)}]
    assert {c.topic_id for c in context.past_cards if c.set_id == old_set} == set(topics.values())

    # 정상 결과는 통과. 빠진 제외 주제를 가리키는 지난 카드가 있어도 됨
    request = SimpleNamespace(model="synthetic-model", prompt_version="2")
    assert result_problems(fake_result(request), context) == []
    # 빠진 제외 주제를 다시 쓰면 입력에 없는 주제, 남은 제외 주제를 쓰면 제외한 주제로 거절
    dropped = result_problems(fake_result(request, reuse_topic=topics[2]), context)
    assert "1번: 이 프로필에 없는 주제" in dropped
    still_excluded = result_problems(fake_result(request, reuse_topic=topics[4]), context)
    assert "1번: 보호자가 제외한 주제" in still_excluded


def test_generated_cards_and_new_topics_are_saved(migrated_database_url):
    seen = {}

    def generate(request):
        seen["request"] = request
        return fake_result(request, reuse_topic=request.context.topics[0].topic_id)

    card_set, cards = _process(migrated_database_url, generate)

    request = seen["request"]
    assert (request.schema_version, request.model, request.prompt_version) == (1, "synthetic-model", 2)
    assert card_set["status"] == "completed" and card_set["lease_expires_at"] is None
    assert card_set["generation_log"]["input"] == sent_ids(request.context)
    assert card_set["generation_log"]["log"] == {"candidates": 18}
    # 카드별 부가 정보는 정해진 값만. 고른 이유 같은 글은 남기지 않음
    assert card_set["generation_log"]["cards"][0] == {"position": 1, "kind": "general"}
    assert [card["position"] for card in cards] == list(range(1, 13))
    assert cards[0]["topic_id"] == request.context.topics[0].topic_id
    assert (cards[1]["evidence_source"], cards[1]["evidence"]) == (
        "profile",
        [{"profileField": "hobby"}],
    )
    assert {card["position"] for card in cards if card["sensitive"]} == SENSITIVE_POSITIONS


def test_completed_generation_logs_card_counts_without_text(migrated_database_url, caplog):
    """처리 기록(2026-11-09 PM 결정)은 카드 수와 아픈 경험 카드 수만 남기고 문구는 남기지 않음."""
    caplog.set_level(logging.INFO, logger="saerok.card_generation")

    card_set, _ = _process(migrated_database_url, fake_result)

    records = [r for r in caplog.records if r.getMessage() == "card_generation_completed"]
    assert len(records) == 1
    formatted = SafeJsonFormatter().format(records[0])
    assert not HANGUL.search(formatted), formatted
    logged = json.loads(formatted)
    assert {key: logged[key] for key in ("set_id", "cards", "sensitive_cards", "prompt_version")} == {
        "set_id": str(card_set["set_id"]),
        "cards": 12,
        "sensitive_cards": len(SENSITIVE_POSITIONS),
        "prompt_version": 2,
    }


def test_saved_generation_log_keeps_ids_not_text(migrated_database_url):
    """기록에는 보낸 이야기, 사진, 주제, 회차, 지난 카드의 ID만 남음(PM 결정 2026-11-08).

    생성 쪽 실행 기록과 카드별 부가 정보에도 이야기 내용이 옮겨질 수 있어 숫자와 정해진 값만 남김."""
    seen = {}

    def generate(request):
        seen["request"] = request
        result = fake_result(request, reuse_topic=request.context.topics[0].topic_id)
        result.log = {
            "candidates": 18,
            "refills": ["합성 이야기를 더 찾아라"],
            "dropped": [{"no": 3, "card_title": "합성 제목", "reason": "합성 이유"}],
            "writingFirstProblems": ["3번: 질문이 물음표로 끝나지 않는다: 합성 질문"],
            "selectionSeed": 7,
            "seconds": 1.5,
        }
        for card in result.cards:
            card.extra = {
                "kind": "personal",
                "bucket": "new",
                "angle": "합성 이야기의 장면",
                "pickReason": "새 이야기",
                "agentReason": "합성 이야기",
                "matchReason": "합성 이유",
            }
        return result

    card_set, cards = _process(migrated_database_url, generate)

    log = card_set["generation_log"]
    assert card_set["status"] == "completed" and len(cards) == 12
    assert_no_text(log)
    assert log["input"] == sent_ids(seen["request"].context)
    assert log["input"]["profileFields"] == ["hobby"]
    assert all(
        log["input"][key]
        for key in ("lifeFactIds", "photoIds", "topicIds", "visitSessionIds", "pastCardIds")
    )
    assert log["log"] == {
        "candidates": 18,
        "refills": 1,
        "dropped": 1,
        "writingFirstProblems": 1,
        "selectionSeed": 7,
        "seconds": 1.5,
    }
    assert log["cards"] == [
        {"position": position, "kind": "personal", "bucket": "new"} for position in range(1, 13)
    ]


def _run_worker(database_url, generate):
    """worker로 작업 하나를 처리. 처리 함수 밖으로 나간 예외는 worker가 실패로 정리함."""
    worker = create_worker(
        Settings(_env_file=None, database_url=database_url, ml_api_key="synthetic-key"), generate
    )

    async def scenario():
        async with connect(database_url) as connection:
            _, set_id, _, _ = await _seed(connection)
        assert await worker.run_once()
        async with connect(database_url) as connection:
            cursor = await connection.execute("SELECT * FROM card_sets WHERE set_id = %s", (set_id,))
            return await cursor.fetchone()

    return run(scenario())


@pytest.mark.parametrize(
    "fail, error_code",
    [
        ("generation-error", "NOT_ENOUGH_TOPICS"),
        ("invalid-result", "INVALID_GENERATION_RESULT"),
        ("unexpected-error", "CARD_GENERATION_FAILED"),
    ],
)
def test_failed_generation_log_keeps_ids_not_text(migrated_database_url, fail, error_code):
    seen = {}

    def generate(request):
        seen["request"] = request
        if fail == "generation-error":
            raise CardGenerationError("NOT_ENOUGH_TOPICS", "합성 실패")
        if fail == "unexpected-error":
            raise RuntimeError("합성 이야기")
        result = fake_result(request)
        result.cards.pop()
        return result

    card_set = _run_worker(migrated_database_url, generate)

    assert (card_set["status"], card_set["error_code"]) == ("failed", error_code)
    assert_no_text(card_set["generation_log"])
    if fail == "unexpected-error":
        assert card_set["generation_log"] == {"input": None}
    else:
        assert card_set["generation_log"] == {"input": sent_ids(seen["request"].context)}


@pytest.mark.parametrize(
    "lease_left, saved",
    [("1 minute", True), ("-1 second", False)],
    ids=["within-lease", "after-lease"],
)
def test_result_is_saved_only_while_the_lease_lasts(migrated_database_url, lease_left, saved):
    """생성하는 동안 임대 시각이 지났으면 만료 정리(`expire_leases`)가 돌기 전이라도 결과를
    저장하지 않고 임대 만료로 끝낸다. 임대가 남았으면 그대로 저장한다."""
    queue = CardGenerationQueue()
    seen = {}

    def generate(request):
        seen["request"] = request
        # 생성 함수가 도는 동안 임대 시각을 옮긴다. 만료 정리는 아직 돌지 않았다.
        with psycopg.connect(psycopg_dsn(migrated_database_url), autocommit=True) as db:
            db.execute(
                "UPDATE card_sets SET lease_expires_at = now() + %s::interval"
                " WHERE status = 'running'",
                (lease_left,),
            )
        return fake_result(request)

    async def scenario():
        async with connect(migrated_database_url) as connection:
            profile_id, set_id, _, _ = await _seed(connection)
            topics_before = await value(
                connection,
                "SELECT count(*) FROM profile_topics WHERE profile_id = %s",
                (profile_id,),
            )
            job = await queue.claim(connection, lease_seconds=600)
            await CardGenerationProcessor(queue=queue, generate=generate)(connection, job)
            cursor = await connection.execute("SELECT * FROM card_sets WHERE set_id = %s", (set_id,))
            card_set = await cursor.fetchone()
            cards = await value(
                connection, "SELECT count(*) FROM conversation_cards WHERE set_id = %s", (set_id,)
            )
            topics_after = await value(
                connection,
                "SELECT count(*) FROM profile_topics WHERE profile_id = %s",
                (profile_id,),
            )
            return card_set, cards, topics_after - topics_before

    card_set, cards, new_topics = run(scenario())

    assert card_set["lease_expires_at"] is None
    if saved:
        assert (card_set["status"], cards, new_topics) == ("completed", 12, 12)
    else:
        assert (card_set["status"], card_set["error_code"]) == ("failed", "WORKER_LEASE_EXPIRED")
        assert (cards, new_topics) == (0, 0)
    # 임대 만료로 끝낸 기록도 보낸 글은 남기지 않고 ID만 남김(`reference_input`)
    assert_no_text(card_set["generation_log"])
    assert card_set["generation_log"]["input"] == sent_ids(seen["request"].context)


def test_lease_that_ends_while_save_waits_for_the_profile_lock_is_not_saved(
    migrated_database_url,
):
    """저장 트랜잭션이 프로필 잠금을 기다리는 사이 임대가 끝나면 저장하지 않는다.

    임대는 잠금을 잡은 뒤의 시각(`clock_timestamp()`)으로 본다. 트랜잭션 시작 시각(`now()`)으로
    보면 기다리는 동안 끝난 임대를 남은 것으로 보고 저장한다."""
    queue = CardGenerationQueue()
    seen = {}

    def generate(request):
        seen["request"] = request
        return fake_result(request)

    async def scenario():
        async with (
            connect(migrated_database_url) as connection,
            connect(migrated_database_url) as holder,
        ):
            profile_id, set_id, _, _ = await _seed(connection)
            job = await queue.claim(connection, lease_seconds=600)
            async with holder.transaction():
                await holder.execute(
                    "SELECT 1 FROM profiles WHERE profile_id = %s FOR UPDATE", (profile_id,)
                )
                processing = asyncio.create_task(
                    CardGenerationProcessor(queue=queue, generate=generate)(connection, job)
                )
                await _until_waiting_for_lock(holder, connection.info.backend_pid)
                # 저장 트랜잭션이 시작된 뒤의 시각을 임대 끝으로 둔다.
                await holder.execute(
                    "UPDATE card_sets SET lease_expires_at = clock_timestamp() WHERE set_id = %s",
                    (set_id,),
                )
            await processing
            cursor = await connection.execute("SELECT * FROM card_sets WHERE set_id = %s", (set_id,))
            card_set = await cursor.fetchone()
            cards = await value(
                connection, "SELECT count(*) FROM conversation_cards WHERE set_id = %s", (set_id,)
            )
            return card_set, cards

    card_set, cards = run(scenario())

    assert (card_set["status"], card_set["error_code"]) == ("failed", "WORKER_LEASE_EXPIRED")
    assert cards == 0
    assert_no_text(card_set["generation_log"])
    assert card_set["generation_log"] == {"input": sent_ids(seen["request"].context)}


async def _until_waiting_for_lock(observer, pid):
    """`pid` 연결이 잠금을 기다리기 시작할 때까지 기다림. pg_stat_activity는 트랜잭션 안에서
    처음 읽은 값을 계속 돌려주므로 pg_locks를 봄."""
    for _ in range(100):
        await asyncio.sleep(0.05)
        cursor = await observer.execute(
            "SELECT count(*) AS n FROM pg_locks WHERE pid = %s AND NOT granted", (pid,)
        )
        if (await cursor.fetchone())["n"] > 0:
            return
    raise AssertionError("저장이 프로필 잠금을 기다리지 않음")


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
    assert card_set["generation_log"]["cards"][0] == {"position": 1, "kind": "general", "bucket": "new"}
    assert_no_text(card_set["generation_log"])
    assert len(cards) == 12 and str(cards[0]["topic_id"]) == request.context.topics[0].topic_id


def test_story_sensitive_mark_reaches_the_ai_package_and_cards_keep_it(
    migrated_database_url, monkeypatch
):
    """이야기의 아픈 기억 표시(`life_facts.sensitive`)를 4-1 요청 `lifeFacts[].sensitive`로 넘긴다
    (2026-11-10 PM 결정). 카드 생성이 그 이야기를 근거로 한 카드에 낸 `sensitive`는 그대로 저장한다."""
    seen = {}

    def generate_cards(request, *, api_key):
        seen["request"] = request
        result = fake_ai_result(request)
        painful = next(f.fact_id for f in request.context.life_facts if f.sensitive)
        # 5번 카드는 아픈 기억 이야기를 근거로 한 카드. 카드 생성 2판은 이 카드를 늘 sensitive로 낸다
        data = result.model_dump(mode="json", by_alias=True)
        data["cards"][4].update(evidenceSource="lifeFact", evidence=[{"factId": painful}], sensitive=True)
        data["cards"][4]["topic"]["evidence"] = [{"factId": painful}]
        return ai.GenerationResult.model_validate(data)

    queue = CardGenerationQueue()
    processor = CardGenerationProcessor(
        queue=queue, generate=_ai_generator(monkeypatch, generate_cards)
    )

    async def scenario():
        async with connect(migrated_database_url) as connection:
            profile_id, set_id, _, _ = await _seed(connection)
            await connection.execute(
                "INSERT INTO life_facts (profile_id, title, content, sensitive)"
                " VALUES (%s, '합성 사별 이야기', '합성 내용', true)",
                (profile_id,),
            )
            job = await queue.claim(connection, lease_seconds=600)
            await processor(connection, job)
            cursor = await connection.execute(
                "SELECT position, sensitive FROM conversation_cards WHERE set_id = %s"
                " ORDER BY position",
                (set_id,),
            )
            return await cursor.fetchall()

    cards = run(scenario())

    sent = seen["request"].context.life_facts
    assert [(f.title, f.sensitive) for f in sent] == [
        ("합성 제목", False),
        ("합성 사별 이야기", True),
    ]
    assert {c["position"] for c in cards if c["sensitive"]} == SENSITIVE_POSITIONS | {5}


def test_card_generator_keeps_the_ai_failure_code(migrated_database_url, monkeypatch):
    def generate_cards(request, *, api_key):
        raise ai.CardGenerationError("NOT_ENOUGH_TOPICS", "다시 찾아도 주제가 모자람")

    card_set, cards = _process(migrated_database_url, _ai_generator(monkeypatch, generate_cards))

    assert (card_set["status"], card_set["error_code"]) == ("failed", "NOT_ENOUGH_TOPICS")
    assert cards == []


def test_default_card_prompt_version_is_the_latest_the_ai_package_knows():
    """2판부터 아픈 경험 카드에 `sensitive`가 붙는다(2026-11-09 PM 결정). 기본값이 이전 판이면
    표시가 늘 false로 저장된다."""
    from card_generation._versions import LATEST, VERSIONS

    version = Settings(_env_file=None).card_generation_prompt_version
    assert version in VERSIONS and version == LATEST.number


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
