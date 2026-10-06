"""카드 묶음(`card_sets`)의 상태 계산, 조회, 생성 요청과 생성 처리.

- 상태: 저장하지 않음. 가장 최근 묶음의 `status`, `session_id`, 그 회차의 `evaluated_at`으로 계산(API 명세 4절)
- 4-1 처리: worker가 임대한 작업 하나를 처리. 생성 함수는 밖에서 받음

      context 조립 → 생성 함수(트랜잭션 밖, 별도 스레드) → 결과 검증 → 저장(한 트랜잭션)
"""

import asyncio
import logging
from collections.abc import Callable
from typing import Any
from uuid import UUID

from psycopg.types.json import Jsonb

from app.core.database import DbConnection
from app.core.errors import AppError
from app.schemas.card_generation import (
    Card,
    CardContext,
    CardGenerationRequest,
    CardGenerationResult,
    CardSet,
    CardTopic,
    LifeFact,
    PastCard,
    Photo,
    ProfileFacts,
    Topic,
    TopicFeedback,
    Visit,
)
from app.services.card_generation_jobs import CardGenerationJob, CardGenerationQueue

logger = logging.getLogger("saerok.card_generation")

# DB 값 → API 값
EVIDENCE_SOURCE = {
    "life_fact": "lifeFact",
    "photo": "photo",
    "profile": "profile",
    "none": "none",
}


async def _latest(connection: DbConnection, profile_id: UUID) -> dict[str, Any] | None:
    cursor = await connection.execute(
        "SELECT s.set_id, s.status, s.session_id, v.evaluated_at "
        "  FROM card_sets s LEFT JOIN visit_sessions v ON v.session_id = s.session_id "
        " WHERE s.profile_id = %s ORDER BY s.created_at DESC, s.set_id LIMIT 1",
        (profile_id,),
    )
    return await cursor.fetchone()


def _status(latest: dict[str, Any] | None) -> str:
    if latest is None:
        return "none"
    if latest["status"] != "completed":
        return latest["status"]  # running, failed
    if latest["session_id"] is None:
        return "ready"
    return "inVisit" if latest["evaluated_at"] is None else "none"


async def generation_status(connection: DbConnection, profile_id: UUID) -> str:
    """`none`, `running`, `ready`, `inVisit`, `failed`."""
    return _status(await _latest(connection, profile_id))


async def current_card_set(connection: DbConnection, profile_id: UUID) -> CardSet:
    """4-3. 상태가 `ready`나 `inVisit`인 가장 최근 묶음. 없으면 404."""
    latest = await _latest(connection, profile_id)
    if _status(latest) not in ("ready", "inVisit"):
        raise AppError(
            status_code=404,
            error_code="CARD_GENERATION_NOT_FOUND",
            message="쓸 수 있는 카드 묶음이 없습니다.",
        )
    cursor = await connection.execute(
        "SELECT c.card_id, c.position, c.topic_id, t.title, t.description,"
        "       c.card_title, c.description AS card_description, c.primary_question,"
        "       c.follow_up_questions, c.evidence_source, c.evidence, c.selected"
        "  FROM conversation_cards c JOIN profile_topics t ON t.topic_id = c.topic_id"
        " WHERE c.set_id = %s ORDER BY c.position",
        (latest["set_id"],),
    )
    cards = [
        Card(
            card_id=row["card_id"],
            position=row["position"],
            topic=CardTopic(
                topic_id=row["topic_id"], title=row["title"], description=row["description"]
            ),
            card_title=row["card_title"],
            description=row["card_description"],
            primary_question=row["primary_question"],
            follow_up_questions=row["follow_up_questions"],
            evidence_source=EVIDENCE_SOURCE[row["evidence_source"]],
            evidence=row["evidence"],
            selected=row["selected"],
        )
        for row in await cursor.fetchall()
    ]
    return CardSet(set_id=latest["set_id"], used_by_session_id=latest["session_id"], cards=cards)


async def lock_profile(connection: DbConnection, profile_id: UUID) -> None:
    """프로필 행을 트랜잭션 끝까지 잠금. 4-1과 5-1이 같은 프로필에서 차례로 실행되게 함.

    4-1의 상태 확인과 INSERT 사이에 5-1이 묶음을 쓰기 시작하면 면회 중인 묶음이 최신이 아니게 됨.
    """
    await connection.execute(
        "SELECT 1 FROM profiles WHERE profile_id = %s FOR UPDATE", (profile_id,)
    )


async def start_card_generation(
    connection: DbConnection, profile_id: UUID, *, model: str, prompt_version: int
) -> None:
    """`running` 작업 생성. 이미 `running`이 있으면 넘어감. `inVisit`, `ready`이면 409.

    `ready`도 거절해서 아직 안 쓴 완료 묶음은 늘 최신 묶음 하나뿐이게 함. 그래서 5-1이 받는
    묶음이 4-2, 4-3이 보는 최신 묶음과 같음.

    프로필당 `running`은 하나(부분 유일 인덱스 `uq_card_sets_running`). `prompt_version` 열이
    문자열 열이라 문자열로 저장함.
    """
    async with connection.transaction():
        await lock_profile(connection, profile_id)
        status = await generation_status(connection, profile_id)
        if status == "inVisit":
            raise AppError(
                status_code=409,
                error_code="VISIT_IN_PROGRESS",
                message="평가를 마치지 않은 면회가 있습니다.",
            )
        if status == "ready":
            raise AppError(
                status_code=409,
                error_code="CARD_SET_READY",
                message="아직 쓰지 않은 카드 묶음이 있습니다.",
            )
        await connection.execute(
            "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
            "VALUES (%s, 'running', %s, %s) "
            "ON CONFLICT (profile_id) WHERE status = 'running' DO NOTHING",
            (profile_id, model, str(prompt_version)),
        )


# ── 4-1 처리 ──────────────────────────────────────────
PROFILE_FIELDS = ("occupation", "hometown", "hobby", "family")
EVIDENCE_KEYS = ("factId", "photoId", "profileField")
# 근거 종류별 근거 항목의 키
EVIDENCE_KEY = {"lifeFact": "factId", "photo": "photoId", "profile": "profileField"}
# card_title, profile_topics.title이 VARCHAR(100)
TITLE_MAX = 100
# API 값 → DB 값
DB_EVIDENCE_SOURCE = {
    "lifeFact": "life_fact",
    "photo": "photo",
    "profile": "profile",
    "none": "none",
}

Generate = Callable[[CardGenerationRequest], CardGenerationResult]


class CardGenerationError(RuntimeError):
    """생성 함수의 실패. `code`는 API 명세 4-1 처리의 실패 표 값."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


async def _rows(connection: DbConnection, sql: str, profile_id: UUID) -> list[dict[str, Any]]:
    cursor = await connection.execute(sql, {"profile_id": profile_id})
    return await cursor.fetchall()


async def build_context(connection: DbConnection, profile_id: UUID) -> CardContext:
    """생성 함수에 넘길 context. 이름, 성별, 생년월일, 인지 상태, 증상 메모, 평가 메모,
    리포트 본문, 전사문, 승인 전 제안은 넣지 않음."""
    profile = (
        await _rows(
            connection,
            "SELECT date_part('year', age(current_date, birth_date))::int / 10 * 10 AS decade,"
            "       occupation, hometown, hobby, family"
            "  FROM profiles WHERE profile_id = %(profile_id)s",
            profile_id,
        )
    )[0]
    facts = await _rows(
        connection,
        "SELECT fact_id, title, content, created_at, source_proposal_id IS NOT NULL AS from_visit"
        "  FROM life_facts WHERE profile_id = %(profile_id)s ORDER BY created_at, fact_id",
        profile_id,
    )
    photos = await _rows(
        connection,
        "SELECT photo_id, description FROM photos"
        " WHERE profile_id = %(profile_id)s AND session_id IS NULL"
        "   AND analysis_status = 'completed' ORDER BY created_at, photo_id",
        profile_id,
    )
    topics = await _rows(
        connection,
        "SELECT topic_id, title, description, evidence, created_at FROM profile_topics"
        " WHERE profile_id = %(profile_id)s ORDER BY created_at, topic_id",
        profile_id,
    )
    feedback = await _rows(
        connection,
        "SELECT topic_id, action, decided_at FROM topic_feedback"
        " WHERE profile_id = %(profile_id)s ORDER BY decided_at, feedback_id",
        profile_id,
    )
    visits = await _rows(
        connection,
        "SELECT v.session_id, v.started_at, s.set_id"
        "  FROM visit_sessions v LEFT JOIN card_sets s ON s.session_id = v.session_id"
        " WHERE v.profile_id = %(profile_id)s AND v.evaluated_at IS NOT NULL"
        " ORDER BY v.started_at, v.session_id",
        profile_id,
    )
    cards = await _rows(
        connection,
        "SELECT c.card_id, c.set_id, c.topic_id, c.position, c.card_title,"
        "       c.primary_question, c.evidence, c.selected, c.review_reaction"
        "  FROM conversation_cards c"
        "  JOIN card_sets s ON s.set_id = c.set_id"
        "  JOIN visit_sessions v ON v.session_id = s.session_id"
        " WHERE c.profile_id = %(profile_id)s AND v.evaluated_at IS NOT NULL"
        " ORDER BY v.started_at, c.position",
        profile_id,
    )
    feedback_by_topic: dict[UUID, list[TopicFeedback]] = {}
    for row in feedback:
        feedback_by_topic.setdefault(row["topic_id"], []).append(
            TopicFeedback(action=row["action"], decided_at=row["decided_at"])
        )
    return CardContext(
        age_range=f"{profile['decade']}s",
        profile_facts=ProfileFacts(**{field: profile[field] for field in PROFILE_FIELDS}),
        life_facts=[
            LifeFact(
                fact_id=row["fact_id"],
                title=row["title"],
                content=row["content"],
                created_at=row["created_at"],
                source="visit" if row["from_visit"] else "caregiver",
            )
            for row in facts
        ],
        photos=[Photo(photo_id=row["photo_id"], description=row["description"]) for row in photos],
        topics=[
            Topic(
                topic_id=row["topic_id"],
                title=row["title"],
                description=row["description"],
                evidence=row["evidence"],
                created_at=row["created_at"],
                feedback=feedback_by_topic.get(row["topic_id"], []),
            )
            for row in topics
        ],
        visits=[
            Visit(session_id=row["session_id"], started_at=row["started_at"], set_id=row["set_id"])
            for row in visits
        ],
        past_cards=[
            PastCard(
                card_id=row["card_id"],
                set_id=row["set_id"],
                topic_id=row["topic_id"],
                position=row["position"],
                card_title=row["card_title"],
                primary_question=row["primary_question"],
                evidence=row["evidence"],
                selected=row["selected"],
                review_reaction=row["review_reaction"],
            )
            for row in cards
        ],
    )


def result_problems(result: CardGenerationResult, context: CardContext) -> list[str]:
    """저장 전 검증(API 명세 4-1 처리). 문제 목록을 돌려줌. 하나라도 있으면 부르는 쪽에서
    `INVALID_GENERATION_RESULT`로 실패 처리."""
    problems = []
    if sorted(card.position for card in result.cards) != list(range(1, 13)):
        problems.append("카드가 12장이 아니거나 position 1~12가 한 번씩이 아니다")
    known_topics = {topic.topic_id for topic in context.topics}
    reused = [card.topic.topic_id for card in result.cards if card.topic.topic_id]
    if len(reused) != len(set(reused)):
        problems.append("한 묶음 안에 같은 기존 주제가 두 번 있다")
    fact_ids = {str(fact.fact_id) for fact in context.life_facts}
    photo_ids = {str(photo.photo_id) for photo in context.photos}
    # 세부 정보 중 값이 있는 항목만 근거가 될 수 있음
    filled_fields = {field for field in PROFILE_FIELDS if getattr(context.profile_facts, field)}
    for card in result.cards:
        if len(card.follow_up_questions) != 3:
            problems.append(f"{card.position}번: 꼬리 질문이 3개가 아니다")
        if card.topic.topic_id and card.topic.topic_id not in known_topics:
            problems.append(f"{card.position}번: 이 프로필에 없는 주제")
        if not card.topic.topic_id and not (
            (card.topic.title or "").strip() and (card.topic.description or "").strip()
        ):
            problems.append(f"{card.position}번: 새 주제에 제목이나 설명이 없다")
        if len(card.card_title) > TITLE_MAX or len(card.topic.title or "") > TITLE_MAX:
            problems.append(f"{card.position}번: 카드나 주제 제목이 {TITLE_MAX}자를 넘는다")
        if (card.evidence_source == "none") != (not card.evidence):
            problems.append(f"{card.position}번: 근거 종류와 근거 목록이 맞지 않는다")
        elif any(
            next(iter(item), None) != EVIDENCE_KEY.get(card.evidence_source) for item in card.evidence
        ):
            problems.append(f"{card.position}번: 근거 항목이 근거 종류와 다르다")
        for item in [*card.evidence, *(card.topic.evidence or [])]:
            key = next(iter(item), None)
            if len(item) != 1 or key not in EVIDENCE_KEYS:
                problems.append(f"{card.position}번: 근거 항목 형식이 틀렸다")
            elif key == "profileField" and item[key] not in PROFILE_FIELDS:
                problems.append(f"{card.position}번: 근거 항목 형식이 틀렸다")
            elif (
                (key == "factId" and item[key] not in fact_ids)
                or (key == "photoId" and item[key] not in photo_ids)
                or (key == "profileField" and item[key] not in filled_fields)
            ):
                problems.append(f"{card.position}번: context에 없는 근거")
    return problems


async def save_result(
    connection: DbConnection,
    job: CardGenerationJob,
    context: CardContext,
    result: CardGenerationResult,
) -> bool:
    """새 주제, 카드 12장, 작업 완료를 한 트랜잭션으로 저장.

    그 사이 임대가 만료돼 실패 처리됐으면 저장하지 않고 `False`.
    """
    async with connection.transaction():
        cursor = await connection.execute(
            "SELECT 1 FROM card_sets WHERE set_id = %s AND status = 'running'"
            "   AND lease_expires_at IS NOT NULL FOR UPDATE",
            (job.set_id,),
        )
        if await cursor.fetchone() is None:
            return False
        for card in result.cards:
            topic_id = card.topic.topic_id
            if topic_id is None:
                cursor = await connection.execute(
                    "INSERT INTO profile_topics (profile_id, title, description, evidence)"
                    " VALUES (%s, %s, %s, %s) RETURNING topic_id",
                    (
                        job.profile_id,
                        card.topic.title,
                        card.topic.description,
                        Jsonb(card.topic.evidence or []),
                    ),
                )
                topic_id = (await cursor.fetchone())["topic_id"]
            await connection.execute(
                "INSERT INTO conversation_cards (set_id, profile_id, topic_id, card_title,"
                " position, description, primary_question, follow_up_questions,"
                " evidence_source, evidence) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    job.set_id,
                    job.profile_id,
                    topic_id,
                    card.card_title,
                    card.position,
                    card.description,
                    card.primary_question,
                    card.follow_up_questions,
                    DB_EVIDENCE_SOURCE[card.evidence_source],
                    Jsonb(card.evidence),
                ),
            )
        log = {
            "input": context.model_dump(mode="json", by_alias=True),
            "log": result.log,
            "cards": [{"position": card.position, **card.extra} for card in result.cards],
        }
        await connection.execute(
            "UPDATE card_sets SET status = 'completed', lease_expires_at = NULL,"
            " generation_log = %s WHERE set_id = %s",
            (Jsonb(log), job.set_id),
        )
    return True


class CardGenerationProcessor:
    """worker 처리 함수. 실패하면 보낸 context를 `generation_log.input`에 남기고 실패 처리."""

    def __init__(self, *, queue: CardGenerationQueue, generate: Generate) -> None:
        self._queue = queue
        self._generate = generate

    async def __call__(self, connection: DbConnection, job: CardGenerationJob) -> None:
        cursor = await connection.execute(
            "SELECT model, prompt_version FROM card_sets WHERE set_id = %s", (job.set_id,)
        )
        card_set = await cursor.fetchone()
        context = await build_context(connection, job.profile_id)
        sent = context.model_dump(mode="json", by_alias=True)
        request = CardGenerationRequest(
            model=card_set["model"],
            prompt_version=int(card_set["prompt_version"]),
            context=context,
        )
        try:
            # LLM 호출은 동기 코드라 이벤트 루프를 막지 않게 별도 스레드에서 실행
            result = await asyncio.to_thread(self._generate, request)
        except CardGenerationError as error:
            logger.warning("card_generation_failed code=%s", error.code)
            await self._queue.fail(connection, job, error_code=error.code, generation_input=sent)
            return
        problems = result_problems(result, context)
        if problems:
            logger.warning("card_generation_invalid_result problems=%s", len(problems))
            await self._queue.fail(
                connection, job, error_code="INVALID_GENERATION_RESULT", generation_input=sent
            )
            return
        if not await save_result(connection, job, context, result):
            logger.warning("card_generation_lease_lost set_id=%s", job.set_id)
