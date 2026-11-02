"""Keep a cleanup record before uploading short profile speech."""

from alembic import op

revision = "e84b1c6da032"
down_revision = "d73f0b5ca921"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE storage_deletion_request_queue ADD COLUMN not_before TIMESTAMPTZ NOT NULL DEFAULT now()")


def downgrade() -> None:
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM storage_deletion_request_queue WHERE not_before > clock_timestamp()) THEN
            RAISE EXCEPTION 'Pending short speech uploads require the deletion deadline column';
        END IF;
    END $$;""")
    op.execute("ALTER TABLE storage_deletion_request_queue DROP COLUMN not_before")
