"""작업 B(카드·면회) 테스트의 합성 데이터와 앱 구성. 이름과 내용은 모두 합성."""

from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from fastapi import FastAPI

from app.api.deps import get_current_account
from app.core.config import Settings, get_settings
from app.core.database import DbConnection, connect
from app.main import create_app
from app.services.accounts import Account
from tests.support import run


def make_app(database_url: str, user_id: UUID, **settings: Any) -> FastAPI:
    account = Account(
        account_id=str(user_id),
        provider="google",
        social_id=f"synthetic-{uuid4().hex[:8]}",
        display_name="보호자",
        email=None,
        consent_version="2026-09-06",
        consents={},
        created_at=datetime.now(UTC),
    )
    application = create_app()
    settings.setdefault("ml_api_key", "synthetic-key")
    config = Settings(_env_file=None, database_url=database_url, **settings)
    application.dependency_overrides[get_settings] = lambda: config

    async def current_account() -> Account:
        return account

    application.dependency_overrides[get_current_account] = current_account
    return application


def with_db(database_url: str, build):
    """`build(connection)` 실행 결과."""

    async def scenario():
        async with connect(database_url) as connection:
            return await build(connection)

    return run(scenario())


def query(database_url: str, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
    async def build(connection: DbConnection):
        cursor = await connection.execute(sql, params)
        return await cursor.fetchall()

    return with_db(database_url, build)


async def value(connection: DbConnection, sql: str, params: tuple = ()) -> Any:
    cursor = await connection.execute(sql, params)
    return next(iter((await cursor.fetchone()).values()))


async def user_and_profile(connection: DbConnection) -> tuple[UUID, UUID]:
    user_id = await value(
        connection,
        "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id",
        (f"synthetic-sub-{uuid4().hex[:8]}",),
    )
    profile_id = await value(
        connection,
        "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage, symptom_note) "
        "VALUES (%s, '합성이름', 'female', '1943-04-01', 'mildDementia', '합성 증상 메모') "
        "RETURNING profile_id",
        (user_id,),
    )
    return user_id, profile_id


async def completed_card_set(
    connection: DbConnection, profile_id: UUID, *, profile_evidence: bool = False
) -> tuple[UUID, list[UUID]]:
    """카드 12장짜리 완료 묶음. 카드 ID를 position 순으로 돌려줌.

    `profile_evidence`이면 1번 카드의 근거가 세부 정보(`{"profileField": "occupation"}`).
    """
    set_id = await value(
        connection,
        "INSERT INTO card_sets (profile_id, status, model, prompt_version, generation_log) "
        "VALUES (%s, 'completed', 'synthetic-model', '2', '{\"input\": {}}') RETURNING set_id",
        (profile_id,),
    )
    cards = []
    for position in range(1, 13):
        topic_id = await value(
            connection,
            "INSERT INTO profile_topics (profile_id, title, description) "
            "VALUES (%s, %s, '합성 주제 설명') RETURNING topic_id",
            (profile_id, f"합성 주제 {position}"),
        )
        profile = profile_evidence and position == 1
        cards.append(
            await value(
                connection,
                "INSERT INTO conversation_cards (set_id, profile_id, topic_id, card_title, position,"
                " description, primary_question, follow_up_questions, evidence_source, evidence) "
                "VALUES (%s, %s, %s, %s, %s, '합성 설명', '합성 질문이었어요?',"
                " ARRAY['하나?', '둘?', '셋?'], %s, %s::jsonb) RETURNING card_id",
                (
                    set_id,
                    profile_id,
                    topic_id,
                    f"합성 카드 {position}",
                    position,
                    "profile" if profile else "none",
                    '[{"profileField": "occupation"}]' if profile else "[]",
                ),
            )
        )
    return set_id, cards


async def card_set_in(connection: DbConnection, profile_id: UUID, status: str) -> UUID:
    """카드가 없는 `running` 또는 `failed` 묶음."""
    return await value(
        connection,
        "INSERT INTO card_sets (profile_id, status, model, prompt_version, error_code, generation_log) "
        "VALUES (%s, %s, 'synthetic-model', '2', %s, %s) RETURNING set_id",
        (
            profile_id,
            status,
            "NOT_ENOUGH_TOPICS" if status == "failed" else None,
            '{"input": null}' if status == "failed" else None,
        ),
    )


async def visit_with(
    connection: DbConnection, profile_id: UUID, set_id: UUID, *, evaluated: bool
) -> UUID:
    """묶음을 쓴 회차. `evaluated`이면 평가까지 끝난 회차."""
    session_id = await value(
        connection,
        "INSERT INTO visit_sessions (profile_id, evaluated_at, evaluation_satisfaction,"
        " evaluation_reaction) VALUES (%s, %s, %s, %s) RETURNING session_id",
        (
            profile_id,
            datetime.now(UTC) if evaluated else None,
            4 if evaluated else None,
            "pleased" if evaluated else None,
        ),
    )
    await connection.execute(
        "UPDATE card_sets SET session_id = %s WHERE set_id = %s", (session_id, set_id)
    )
    return session_id
