"""initial schema

PR #39(backend/database/init.sql)에 정의된 새록 초기 PostgreSQL 스키마를
Alembic이 소유하는 migration으로 옮긴다. init.sql은 빈 개발 DB를 한 번에
세우는 bootstrap script일 뿐이고, 스키마 변경 이력의 source of truth는 이
migration이다.

init.sql의 개발 편의용 `DROP TABLE ... CASCADE`는 옮기지 않는다. 이
migration은 빈 DB에 스키마를 새로 만드는 것만 책임진다.

Revision ID: db2bf9003e7f
Revises:
Create Date: 2026-09-16 17:39:38.313583

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'db2bf9003e7f'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _uuid_pk(name: str) -> sa.Column:
    return sa.Column(
        name,
        postgresql.UUID(as_uuid=True),
        primary_key=True,
        server_default=sa.text("gen_random_uuid()"),
    )


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # -----------------------------------------------------------------
    # 계정 (소셜로그인)
    # -----------------------------------------------------------------
    op.create_table(
        "users",
        _uuid_pk("user_id"),
        sa.Column("provider", sa.String(20), nullable=False),
        sa.Column("social_id", sa.String(255), nullable=False),
        sa.Column("email", sa.String(320), nullable=True),
        sa.Column("nickname", sa.String(100), nullable=False),
        sa.Column(
            "role",
            sa.String(20),
            nullable=False,
            server_default="caregiver",
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("last_login_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.CheckConstraint("provider IN ('google')"),
        sa.CheckConstraint("role IN ('caregiver', 'admin')"),
        sa.UniqueConstraint("provider", "social_id"),
    )

    op.create_table(
        "account_consents",
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("consent_type", sa.String(30), nullable=False),
        sa.Column("consent_version", sa.String(20), nullable=False),
        sa.Column("granted", sa.Boolean(), nullable=False),
        sa.Column("granted_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("user_id", "consent_type"),
        sa.CheckConstraint(
            "consent_type IN "
            "('serviceData', 'sensitiveData', 'serviceImprovement', 'pushNotification')"
        ),
        sa.CheckConstraint("granted = false OR granted_at IS NOT NULL"),
    )

    # -----------------------------------------------------------------
    # 프로필과 생애 사실
    # -----------------------------------------------------------------
    op.create_table(
        "profiles",
        _uuid_pk("profile_id"),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("age_range", sa.String(10), nullable=False),
        sa.Column("condition_stage", sa.String(30), nullable=False),
        sa.Column("condition_symptom_note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "condition_stage IN ('mildCognitiveImpairment', 'mildDementia', 'unknown')"
        ),
    )
    op.create_index("idx_profiles_user", "profiles", ["user_id"])

    # source_session_id의 FK는 visit_sessions가 아직 없어 뒤에서 ALTER로 붙인다
    # (init.sql과 동일한 순서).
    op.create_table(
        "life_facts",
        _uuid_pk("fact_id"),
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("category", sa.String(20), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("source_type", sa.String(30), nullable=False),
        sa.Column("source_session_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "category IN ('occupation', 'hometown', 'hobby', 'family')"
        ),
        sa.CheckConstraint(
            "source_type IN ('caregiverVoiceInput', 'caregiverTextInput', 'visitConfirmed')"
        ),
        sa.CheckConstraint(
            "source_type = 'visitConfirmed' OR source_session_id IS NULL"
        ),
    )
    op.create_index(
        "idx_life_facts_profile", "life_facts", ["profile_id", "category"]
    )

    # pgvector를 켤 때 추가할 embedding 컬럼/인덱스는 카드 생성 로직이 아직
    # 결정되지 않아 이번 migration에 포함하지 않는다 (init.sql과 동일).

    op.create_table(
        "life_fact_collection_states",
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("category", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column(
            "attempt_count",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.PrimaryKeyConstraint("profile_id", "category"),
        sa.CheckConstraint(
            "category IN ('occupation', 'hometown', 'hobby', 'family')"
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'collected', 'skipped', 'manualFallback')"
        ),
        sa.CheckConstraint("attempt_count >= 0"),
    )

    # 사진 원본과 localUri는 단말에만 둔다. photo_id를 참조할 서버 테이블이
    # 없으므로 FK를 걸지 않는다 (init.sql과 동일한 계약).
    op.create_table(
        "profile_photo_tags",
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("photo_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("tag", sa.String(50), nullable=False),
        sa.PrimaryKeyConstraint("profile_id", "photo_id", "tag"),
    )

    # -----------------------------------------------------------------
    # 면회 회차
    # -----------------------------------------------------------------
    op.create_table(
        "visit_sessions",
        _uuid_pk("session_id"),
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("session_status", sa.String(20), nullable=False),
        sa.Column("photo_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("consent_version", sa.String(20), nullable=True),
        sa.Column(
            "recording_authorization_granted",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column(
            "recording_authorization_granted_at",
            sa.TIMESTAMP(timezone=True),
            nullable=True,
        ),
        sa.Column("started_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("ended_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "session_status IN "
            "('ready', 'recording', 'paused', 'ended', 'processing', 'completed', 'failed')"
        ),
        sa.CheckConstraint("ended_at IS NULL OR started_at IS NOT NULL"),
        sa.CheckConstraint("ended_at IS NULL OR ended_at >= started_at"),
    )
    op.create_index(
        "idx_visit_sessions_profile",
        "visit_sessions",
        ["profile_id", sa.text("started_at DESC")],
    )

    op.create_foreign_key(
        "life_facts_source_session_fk",
        "life_facts",
        "visit_sessions",
        ["source_session_id"],
        ["session_id"],
        ondelete="SET NULL",
    )

    op.create_table(
        "session_consents",
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_sessions.session_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("consent_type", sa.String(30), nullable=False),
        sa.Column("granted", sa.Boolean(), nullable=False),
        sa.Column("granted_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("session_id", "consent_type"),
        sa.CheckConstraint(
            "consent_type IN ('serviceData', 'sensitiveData', 'careRecipientConfirmation')"
        ),
        sa.CheckConstraint("granted = false OR granted_at IS NOT NULL"),
    )

    # -----------------------------------------------------------------
    # 대화 카드
    # -----------------------------------------------------------------
    op.create_table(
        "card_generation_requests",
        _uuid_pk("request_id"),
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("generation_status", sa.String(15), nullable=False),
        sa.Column("error_code", sa.String(50), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("completed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.CheckConstraint(
            "generation_status IN ('pending', 'processing', 'completed', 'failed')"
        ),
        sa.CheckConstraint(
            "generation_status <> 'failed' OR error_code IS NOT NULL"
        ),
    )

    op.create_table(
        "conversation_cards",
        _uuid_pk("card_id"),
        sa.Column(
            "request_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("card_generation_requests.request_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_sessions.session_id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("topic_key", sa.String(50), nullable=False),
        sa.Column("topic_title", sa.String(100), nullable=False),
        sa.Column("topic_description", sa.Text(), nullable=False),
        sa.Column("primary_question", sa.Text(), nullable=False),
        sa.Column(
            "follow_up_questions",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("display_order", sa.SmallInteger(), nullable=False),
        sa.Column(
            "selection_status",
            sa.String(15),
            nullable=False,
            server_default="unselected",
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("selection_status IN ('unselected', 'selected')"),
        sa.UniqueConstraint("request_id", "display_order"),
    )
    op.create_index(
        "idx_cards_session_selected",
        "conversation_cards",
        ["session_id"],
        postgresql_where=sa.text("selection_status = 'selected'"),
    )

    op.create_table(
        "card_evidence_refs",
        sa.Column(
            "card_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("conversation_cards.card_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "fact_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("life_facts.fact_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("card_id", "fact_id"),
    )

    # -----------------------------------------------------------------
    # 평가와 리포트
    # -----------------------------------------------------------------
    op.create_table(
        "caregiver_evaluations",
        _uuid_pk("review_id"),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_sessions.session_id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("conversation_satisfaction", sa.SmallInteger(), nullable=False),
        sa.Column("care_recipient_reaction", sa.String(15), nullable=False),
        sa.Column("free_note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("conversation_satisfaction BETWEEN 1 AND 5"),
        sa.CheckConstraint(
            "care_recipient_reaction IN "
            "('pleased', 'calm', 'angry', 'lowEnergy', 'unknown')"
        ),
    )

    op.create_table(
        "card_reviews",
        sa.Column(
            "review_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("caregiver_evaluations.review_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "card_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("conversation_cards.card_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("was_used", sa.Boolean(), nullable=False),
        sa.Column("caregiver_reaction", sa.String(10), nullable=False),
        sa.PrimaryKeyConstraint("review_id", "card_id"),
        sa.CheckConstraint(
            "caregiver_reaction IN ('positive', 'neutral', 'negative')"
        ),
    )

    op.create_table(
        "visit_reports",
        _uuid_pk("report_id"),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_sessions.session_id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column(
            "review_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("caregiver_evaluations.review_id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("report_status", sa.String(15), nullable=False),
        sa.Column("title", sa.String(200), nullable=True),
        sa.Column("visit_date", sa.Date(), nullable=False),
        sa.Column("mood", sa.String(10), nullable=True),
        sa.Column("photo_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("summary_text", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "report_status IN ('generating', 'ready', 'reviewed', 'acknowledged')"
        ),
        sa.CheckConstraint("mood IN ('hard', 'normal', 'good')"),
        sa.CheckConstraint(
            "report_status = 'generating' "
            "OR (title IS NOT NULL AND summary_text IS NOT NULL AND mood IS NOT NULL)"
        ),
    )

    op.create_table(
        "report_card_summaries",
        sa.Column(
            "report_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_reports.report_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "card_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("conversation_cards.card_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("topic_title", sa.String(100), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("display_order", sa.SmallInteger(), nullable=False),
        sa.PrimaryKeyConstraint("report_id", "card_id"),
    )

    # -----------------------------------------------------------------
    # 변경 제안
    # -----------------------------------------------------------------
    op.create_table(
        "change_proposals",
        _uuid_pk("proposal_id"),
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "report_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_reports.report_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "proposal_status",
            sa.String(15),
            nullable=False,
            server_default="pendingReview",
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("proposal_status IN ('pendingReview', 'reviewed')"),
    )

    op.create_table(
        "proposal_changes",
        _uuid_pk("change_id"),
        sa.Column(
            "proposal_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("change_proposals.proposal_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("change_type", sa.String(20), nullable=False),
        sa.Column("topic_key", sa.String(50), nullable=True),
        sa.Column("topic_title", sa.String(100), nullable=True),
        sa.Column("direction", sa.String(5), nullable=True),
        sa.Column("text", sa.Text(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column(
            "review_status",
            sa.String(10),
            nullable=False,
            server_default="pending",
        ),
        sa.Column(
            "applied_fact_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("life_facts.fact_id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("display_order", sa.SmallInteger(), nullable=False),
        sa.CheckConstraint("change_type IN ('topicPriority', 'lifeFactAdd')"),
        sa.CheckConstraint("direction IN ('up', 'down')"),
        sa.CheckConstraint(
            "review_status IN ('pending', 'accepted', 'rejected', 'reverted')"
        ),
        sa.CheckConstraint(
            "(change_type = 'topicPriority'"
            " AND topic_key IS NOT NULL AND topic_title IS NOT NULL"
            " AND direction IS NOT NULL AND text IS NULL)"
            " OR (change_type = 'lifeFactAdd'"
            " AND text IS NOT NULL"
            " AND topic_key IS NULL AND topic_title IS NULL AND direction IS NULL)"
        ),
    )


def downgrade() -> None:
    """Downgrade schema.

    FK dependency의 역순으로 안전하게 제거한다(생성 순서의 단순 역순이
    아니다). life_facts는 card_evidence_refs/proposal_changes보다 먼저
    지우면 안 되고, visit_sessions는 life_facts(및 그 FK)보다 먼저 지우면
    안 된다.
    """
    op.drop_table("proposal_changes")
    op.drop_table("change_proposals")
    op.drop_table("report_card_summaries")
    op.drop_table("visit_reports")
    op.drop_table("card_reviews")
    op.drop_table("caregiver_evaluations")
    op.drop_table("card_evidence_refs")
    op.drop_index("idx_cards_session_selected", table_name="conversation_cards")
    op.drop_table("conversation_cards")
    op.drop_table("card_generation_requests")
    op.drop_table("session_consents")
    # life_facts_source_session_fk는 life_facts 테이블과 함께 제거된다.
    op.drop_index("idx_life_facts_profile", table_name="life_facts")
    op.drop_table("life_facts")
    op.drop_index("idx_visit_sessions_profile", table_name="visit_sessions")
    op.drop_table("visit_sessions")
    op.drop_table("profile_photo_tags")
    op.drop_table("life_fact_collection_states")
    op.drop_index("idx_profiles_user", table_name="profiles")
    op.drop_table("profiles")
    op.drop_table("account_consents")
    op.drop_table("users")

    # pgcrypto는 이 migration 하나만의 소유물이 아니라 DB 전체에 걸리는
    # extension이다. 같은 DB의 다른 스키마/객체가 gen_random_uuid() 등을
    # 이미 쓰고 있을 수 있으므로 downgrade에서 임의로 제거하지 않는다.
