"""Persist the first card job's photo barrier.

Revision ID: a926d137e405
Revises: 9c4e2b7a1f63
"""
from alembic import op

revision = "a926d137e405"
down_revision = "9c4e2b7a1f63"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE card_sets ADD COLUMN photo_wait_ids UUID[] NOT NULL DEFAULT '{}'")
    op.execute("ALTER TABLE card_sets ADD COLUMN photo_wait_until TIMESTAMPTZ")
    op.execute("ALTER TABLE card_sets ADD COLUMN photo_ready_at TIMESTAMPTZ")


def downgrade() -> None:
    op.drop_column("card_sets", "photo_ready_at")
    op.drop_column("card_sets", "photo_wait_until")
    op.drop_column("card_sets", "photo_wait_ids")
