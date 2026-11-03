"""보호자가 고친 사진 설명을 AI 원문과 분리한다."""
from alembic import op

revision = "c62e19a4b308"
down_revision = "e5a1c7d93b42"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE photos
          ADD COLUMN user_description TEXT,
          ADD COLUMN description_updated_at TIMESTAMPTZ,
          ADD CONSTRAINT photos_user_description_check CHECK (
            (user_description IS NULL AND description_updated_at IS NULL)
            OR (user_description IS NOT NULL AND length(btrim(user_description)) > 0
                AND description_updated_at IS NOT NULL))
    """)


def downgrade():
    op.execute("ALTER TABLE photos DROP COLUMN user_description, DROP COLUMN description_updated_at")
