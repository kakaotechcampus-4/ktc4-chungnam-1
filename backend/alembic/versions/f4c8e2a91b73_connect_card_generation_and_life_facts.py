"""connect card generation and visit proposals to life facts

Revision ID: f4c8e2a91b73
Revises: a8c31f17d902
Create Date: 2026-09-25
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "f4c8e2a91b73"
down_revision: Union[str, Sequence[str], None] = "a8c31f17d902"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the persisted inputs and outputs needed by the recommendation loop."""

    op.create_table(
        "profile_topic_preferences",
        sa.Column(
            "profile_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("profiles.profile_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("topic_key", sa.String(50), nullable=False),
        sa.Column("topic_title", sa.String(100), nullable=False),
        sa.Column(
            "priority_score",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("profile_id", "topic_key"),
        sa.CheckConstraint(
            "priority_score BETWEEN -100 AND 100",
            name="ck_profile_topic_preferences_score",
        ),
    )

    op.create_table(
        "card_generation_fact_inputs",
        sa.Column(
            "request_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("card_generation_requests.request_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "fact_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("life_facts.fact_id", ondelete="CASCADE"),
            nullable=False,
        ),
        # 카드 생성 시점을 재현하되 원본 녹음이나 전사문은 저장하지 않는다.
        sa.Column("fact_category_snapshot", sa.String(20), nullable=False),
        sa.Column("fact_text_snapshot", sa.Text(), nullable=False),
        sa.Column(
            "fact_updated_at_snapshot",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("request_id", "fact_id"),
        sa.CheckConstraint(
            "fact_category_snapshot IN ('occupation', 'hometown', 'hobby', 'family')",
            name="ck_card_generation_fact_inputs_category",
        ),
    )
    op.create_index(
        "idx_card_generation_fact_inputs_fact",
        "card_generation_fact_inputs",
        ["fact_id"],
    )

    op.add_column(
        "proposal_changes",
        sa.Column("life_fact_category", sa.String(20), nullable=True),
    )
    # 기존 lifeFactAdd 행에는 category가 없을 수 있다. NOT VALID는 기존 행 때문에
    # 배포가 중단되는 것을 막으면서도 migration 이후 INSERT/UPDATE에는 제약을
    # 즉시 적용한다. 기존 행을 분류한 뒤 별도 작업에서 VALIDATE한다.
    op.execute(
        "ALTER TABLE proposal_changes ADD CONSTRAINT "
        "ck_proposal_changes_life_fact_category CHECK ("
        "(change_type = 'topicPriority' AND life_fact_category IS NULL) OR "
        "(change_type = 'lifeFactAdd' AND life_fact_category IN "
        "('occupation', 'hometown', 'hobby', 'family'))) NOT VALID"
    )
    op.execute(
        "ALTER TABLE proposal_changes ADD CONSTRAINT "
        "ck_proposal_changes_applied_fact_state CHECK ("
        "(change_type = 'topicPriority' AND applied_fact_id IS NULL) OR "
        "(change_type = 'lifeFactAdd' AND ("
        "(review_status IN ('pending', 'rejected') AND applied_fact_id IS NULL) OR "
        "(review_status = 'accepted' AND applied_fact_id IS NOT NULL) OR "
        "review_status = 'reverted'))) NOT VALID"
    )
    op.create_index(
        "uq_proposal_changes_applied_fact",
        "proposal_changes",
        ["applied_fact_id"],
        unique=True,
        postgresql_where=sa.text("applied_fact_id IS NOT NULL"),
    )

    # 기존 계약은 미사용 카드의 caregiver_reaction을 null로 표현한다. 기존
    # 값 enum CHECK는 PostgreSQL에서 null을 허용하므로 nullable만 바꾸고,
    # 사용 여부와 반응 값의 조합을 별도 CHECK로 고정한다.
    op.alter_column(
        "card_reviews",
        "caregiver_reaction",
        existing_type=sa.String(10),
        nullable=True,
    )
    op.create_check_constraint(
        "ck_card_reviews_usage_reaction",
        "card_reviews",
        "(was_used = true AND caregiver_reaction IS NOT NULL) "
        "OR (was_used = false AND caregiver_reaction IS NULL)",
    )


def downgrade() -> None:
    """Return to the previous schema without inventing legacy values."""

    # 이전 스키마는 caregiver_reaction NOT NULL이다. 새 스키마에서만 유효한
    # 행을 임의 삭제하거나 반응 값을 만들지 않고, 존재하면 안전하게 중단한다.
    op.execute(
        "DO $$ BEGIN "
        "IF EXISTS (SELECT 1 FROM card_reviews "
        "WHERE caregiver_reaction IS NULL) THEN "
        "RAISE EXCEPTION 'cannot downgrade: card_reviews contains null reactions'; "
        "END IF; END $$"
    )
    op.drop_constraint(
        "ck_card_reviews_usage_reaction",
        "card_reviews",
        type_="check",
    )
    op.alter_column(
        "card_reviews",
        "caregiver_reaction",
        existing_type=sa.String(10),
        nullable=False,
    )

    op.drop_index(
        "uq_proposal_changes_applied_fact",
        table_name="proposal_changes",
    )
    op.drop_constraint(
        "ck_proposal_changes_applied_fact_state",
        "proposal_changes",
        type_="check",
    )
    op.drop_constraint(
        "ck_proposal_changes_life_fact_category",
        "proposal_changes",
        type_="check",
    )
    op.drop_column("proposal_changes", "life_fact_category")

    op.drop_index(
        "idx_card_generation_fact_inputs_fact",
        table_name="card_generation_fact_inputs",
    )
    op.drop_table("card_generation_fact_inputs")
    op.drop_table("profile_topic_preferences")
