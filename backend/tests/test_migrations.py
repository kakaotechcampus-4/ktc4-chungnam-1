"""Alembic initial schema migration에 대한 통합 테스트.

실제 PostgreSQL이 필요하다. 임시 DB fixture와 실행 조건은 `conftest.py`에 있다.

실제 사용자 데이터는 쓰지 않는다. 아래 값은 모두 synthetic이다.
"""

import uuid

import pytest
import sqlalchemy as sa
from alembic import command
from sqlalchemy.exc import IntegrityError


@pytest.fixture
def engine(migrated_database_url):
    engine = sa.create_engine(migrated_database_url)
    try:
        yield engine
    finally:
        engine.dispose()


DOMAIN_TABLES = {
    "storage_deletion_request_queue",
    "users",
    "consent_records",
    "profiles",
    "life_facts",
    "visit_sessions",
    "card_sets",
    "profile_topics",
    "conversation_cards",
    "photos",
    "speech_analysis_jobs",
    "life_fact_proposals",
    "topic_proposals",
    "topic_feedback",
    "withdrawal_feedback",
}


def _insert_profile(conn) -> tuple[uuid.UUID, uuid.UUID]:
    user_id = conn.execute(
        sa.text(
            "INSERT INTO users (google_sub) VALUES (:sub) RETURNING user_id"
        ),
        {"sub": f"synthetic-sub-{uuid.uuid4().hex[:8]}"},
    ).scalar_one()
    profile_id = conn.execute(
        sa.text(
            "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage) "
            "VALUES (:user_id, '합성 이름', 'female', '1943-03-12', 'unknown') "
            "RETURNING profile_id"
        ),
        {"user_id": user_id},
    ).scalar_one()
    return user_id, profile_id


def _insert_visit_session(conn, profile_id: uuid.UUID) -> uuid.UUID:
    return conn.execute(
        sa.text(
            "INSERT INTO visit_sessions (profile_id) VALUES (:profile_id) "
            "RETURNING session_id"
        ),
        {"profile_id": profile_id},
    ).scalar_one()


def test_upgrade_creates_all_tables_and_view(engine):
    inspector = sa.inspect(engine)

    assert DOMAIN_TABLES <= set(inspector.get_table_names())
    assert len(DOMAIN_TABLES) == 15
    assert "current_consents" in inspector.get_view_names()


def test_upgrade_produces_working_constraints_and_defaults(engine):
    with engine.begin() as conn:
        user_id, profile_id = _insert_profile(conn)
        assert user_id is not None

        # 동의는 이력으로 쌓고 현재 동의는 가장 최근 이력이다.
        for push_notification in (True, False):
            conn.execute(
                sa.text(
                    "INSERT INTO consent_records "
                    "(user_id, terms_version, service_data, sensitive_data, "
                    " service_improvement, push_notification) "
                    "VALUES (:user_id, '2026-09-06', true, true, false, :push)"
                ),
                {"user_id": user_id, "push": push_notification},
            )
        current_push = conn.execute(
            sa.text(
                "SELECT push_notification FROM current_consents "
                "WHERE user_id = :user_id"
            ),
            {"user_id": user_id},
        ).scalar_one()
        assert current_push is False

        conn.execute(
            sa.text(
                "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
                "VALUES (:profile_id, 'running', 'synthetic-model', 'card-v1')"
            ),
            {"profile_id": profile_id},
        )

    # 프로필마다 진행 중인 카드 생성 작업은 하나뿐이다.
    with pytest.raises(IntegrityError):
        with engine.begin() as conn:
            conn.execute(
                sa.text(
                    "INSERT INTO card_sets (profile_id, status, model, prompt_version) "
                    "VALUES (:profile_id, 'running', 'synthetic-model', 'card-v1')"
                ),
                {"profile_id": profile_id},
            )

    # 필수 동의를 거부한 이력은 CHECK constraint로 거부된다.
    with pytest.raises(IntegrityError):
        with engine.begin() as conn:
            conn.execute(
                sa.text(
                    "INSERT INTO consent_records "
                    "(user_id, terms_version, service_data, sensitive_data, "
                    " service_improvement, push_notification) "
                    "VALUES (:user_id, '2026-09-06', false, true, false, false)"
                ),
                {"user_id": user_id},
            )

    # 존재하지 않는 참조는 FK violation으로 거부된다.
    with pytest.raises(IntegrityError):
        with engine.begin() as conn:
            conn.execute(
                sa.text(
                    "INSERT INTO profiles "
                    "(user_id, name, gender, birth_date, condition_stage) "
                    "VALUES ('00000000-0000-0000-0000-000000000000', "
                    " '합성 이름', 'male', '1940-01-01', 'unknown')"
                )
            )


def test_deleting_visit_session_keeps_accepted_life_fact(engine):
    with engine.begin() as conn:
        _, profile_id = _insert_profile(conn)
        session_id = _insert_visit_session(conn, profile_id)
        proposal_id = conn.execute(
            sa.text(
                "INSERT INTO life_fact_proposals "
                "(session_id, profile_id, title, content, reason, status) "
                "VALUES (:session_id, :profile_id, '합성 제목', '합성 내용', "
                " '합성 이유', 'settled') RETURNING proposal_id"
            ),
            {"session_id": session_id, "profile_id": profile_id},
        ).scalar_one()
        fact_id = conn.execute(
            sa.text(
                "INSERT INTO life_facts "
                "(profile_id, title, content, source_proposal_id) "
                "VALUES (:profile_id, '합성 제목', '합성 내용', :proposal_id) "
                "RETURNING fact_id"
            ),
            {"profile_id": profile_id, "proposal_id": proposal_id},
        ).scalar_one()

    with engine.begin() as conn:
        conn.execute(
            sa.text("DELETE FROM visit_sessions WHERE session_id = :session_id"),
            {"session_id": session_id},
        )

    # 회차를 지우면 제안은 함께 지워지지만 승인한 사실은 남고 출처만 해제된다.
    with engine.begin() as conn:
        source = conn.execute(
            sa.text(
                "SELECT source_proposal_id FROM life_facts WHERE fact_id = :fact_id"
            ),
            {"fact_id": fact_id},
        ).one()
        assert source.source_proposal_id is None


def test_deleting_photo_queues_storage_deletion(engine):
    object_key = f"synthetic/photos/{uuid.uuid4().hex}.jpg"
    with engine.begin() as conn:
        _, profile_id = _insert_profile(conn)
        conn.execute(
            sa.text(
                "INSERT INTO photos (profile_id, s3_object_key) "
                "VALUES (:profile_id, :object_key)"
            ),
            {"profile_id": profile_id, "object_key": object_key},
        )

    with engine.begin() as conn:
        conn.execute(
            sa.text("DELETE FROM photos WHERE s3_object_key = :object_key"),
            {"object_key": object_key},
        )
        queued = conn.execute(
            sa.text(
                "SELECT count(*) FROM storage_deletion_request_queue "
                "WHERE s3_object_key = :object_key"
            ),
            {"object_key": object_key},
        ).scalar_one()
    assert queued == 1


def test_deleting_card_set_removes_orphan_topic(engine):
    with engine.begin() as conn:
        _, profile_id = _insert_profile(conn)
        topic_id = conn.execute(
            sa.text(
                "INSERT INTO profile_topics (profile_id, title, description) "
                "VALUES (:profile_id, '합성 주제', '합성 주제 설명') "
                "RETURNING topic_id"
            ),
            {"profile_id": profile_id},
        ).scalar_one()
        set_id = conn.execute(
            sa.text(
                "INSERT INTO card_sets "
                "(profile_id, status, model, prompt_version, generation_log) "
                "VALUES (:profile_id, 'completed', 'synthetic-model', 'card-v1', "
                " '{\"input\": {}}') RETURNING set_id"
            ),
            {"profile_id": profile_id},
        ).scalar_one()
        conn.execute(
            sa.text(
                "INSERT INTO conversation_cards "
                "(set_id, profile_id, topic_id, card_title, position, description, "
                " primary_question, follow_up_questions, evidence_source) "
                "VALUES (:set_id, :profile_id, :topic_id, '합성 카드', 1, "
                " '합성 카드 설명', '합성 질문?', ARRAY['합성 꼬리 질문?'], 'none')"
            ),
            {"set_id": set_id, "profile_id": profile_id, "topic_id": topic_id},
        )

    # 카드 묶음을 지우면 카드가 함께 지워지고, 남은 카드가 없는 주제는
    # 트랜잭션 끝의 지연 trigger가 지운다.
    with engine.begin() as conn:
        conn.execute(
            sa.text("DELETE FROM card_sets WHERE set_id = :set_id"),
            {"set_id": set_id},
        )

    with engine.begin() as conn:
        remaining = conn.execute(
            sa.text("SELECT count(*) FROM profile_topics WHERE topic_id = :topic_id"),
            {"topic_id": topic_id},
        ).scalar_one()
    assert remaining == 0


def test_downgrade_removes_all_tables_then_upgrade_recreates_them(
    alembic_config, test_database_url
):
    command.upgrade(alembic_config, "head")
    command.downgrade(alembic_config, "base")

    engine = sa.create_engine(test_database_url)
    try:
        inspector = sa.inspect(engine)
        assert set(inspector.get_table_names()) - {"alembic_version"} == set()
        assert inspector.get_view_names() == []
    finally:
        engine.dispose()

    command.upgrade(alembic_config, "head")

    engine2 = sa.create_engine(test_database_url)
    try:
        inspector = sa.inspect(engine2)
        table_names = set(inspector.get_table_names())
    finally:
        engine2.dispose()

    assert DOMAIN_TABLES <= table_names
