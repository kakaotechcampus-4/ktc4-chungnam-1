"""add asynchronous speech analysis jobs

Revision ID: a8c31f17d902
Revises: db2bf9003e7f
Create Date: 2026-09-25
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "a8c31f17d902"
down_revision: Union[str, Sequence[str], None] = "db2bf9003e7f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "visit_sessions",
        sa.Column("participant_count", sa.SmallInteger(), nullable=True),
    )
    op.create_check_constraint(
        "ck_visit_sessions_participant_count",
        "visit_sessions",
        "participant_count IS NULL OR participant_count BETWEEN 1 AND 8",
    )

    op.create_table(
        "speech_analysis_jobs",
        sa.Column(
            "analysis_id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
        ),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("visit_sessions.session_id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("participant_count", sa.SmallInteger(), nullable=False),
        sa.Column("s3_object_key", sa.String(255), nullable=False, unique=True),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("sha256", sa.String(64), nullable=True),
        sa.Column("data_expires_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column(
            "attempt_count",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("lease_expires_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("error_code", sa.String(50), nullable=True),
        sa.Column("audio_deleted_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("stt_completed_at", sa.TIMESTAMP(timezone=True), nullable=True),
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
        sa.Column("completed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('uploading', 'queued', 'transcribing', 'sttCompleted', "
            "'generatingReport', 'completed', 'failed')",
            name="ck_speech_analysis_jobs_status",
        ),
        sa.CheckConstraint(
            "participant_count BETWEEN 1 AND 8",
            name="ck_speech_analysis_jobs_participant_count",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_speech_analysis_jobs_attempt_count",
        ),
        sa.CheckConstraint(
            "(status = 'uploading' AND size_bytes IS NULL AND sha256 IS NULL) "
            "OR (status <> 'uploading' AND size_bytes > 0 "
            "AND sha256 ~ '^[0-9a-f]{64}$')",
            name="ck_speech_analysis_jobs_audio_metadata",
        ),
        sa.CheckConstraint(
            "status <> 'failed' OR error_code IS NOT NULL",
            name="ck_speech_analysis_jobs_failed_error",
        ),
    )
    op.create_index(
        "idx_speech_analysis_jobs_queue",
        "speech_analysis_jobs",
        ["created_at"],
        postgresql_where=sa.text("status = 'queued'"),
    )
    op.create_index(
        "idx_speech_analysis_jobs_expiry",
        "speech_analysis_jobs",
        ["data_expires_at"],
        postgresql_where=sa.text("audio_deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index(
        "idx_speech_analysis_jobs_expiry",
        table_name="speech_analysis_jobs",
    )
    op.drop_index(
        "idx_speech_analysis_jobs_queue",
        table_name="speech_analysis_jobs",
    )
    op.drop_table("speech_analysis_jobs")
    op.drop_constraint(
        "ck_visit_sessions_participant_count",
        "visit_sessions",
        type_="check",
    )
    op.drop_column("visit_sessions", "participant_count")
