"""Track storage deletion attempts without changing the original request time."""

from alembic import op

revision = "a49d71b28c36"
down_revision = "e5a1c7d93b42"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE storage_deletion_request_queue
            ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0
                CHECK (attempt_count >= 0),
            ADD COLUMN last_attempt_at TIMESTAMPTZ,
            ADD COLUMN last_error_code VARCHAR(64);
        CREATE INDEX storage_deletion_attempt_order_idx
            ON storage_deletion_request_queue
            (last_attempt_at NULLS FIRST, requested_at, s3_object_key);
    """)


def downgrade() -> None:
    op.execute("""
        DROP INDEX storage_deletion_attempt_order_idx;
        ALTER TABLE storage_deletion_request_queue
            DROP COLUMN last_error_code,
            DROP COLUMN last_attempt_at,
            DROP COLUMN attempt_count;
    """)
