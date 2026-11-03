"""배포 전 새 분석 접수와 worker 임대를 중지할 상태. 기본은 허용."""
from alembic import op

revision = "f95c2d7eb143"
down_revision = "e84b1c6da032"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE deployment_control (
            singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
            admissions_paused BOOLEAN NOT NULL DEFAULT false,
            claims_paused BOOLEAN NOT NULL DEFAULT false,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CHECK (NOT claims_paused OR admissions_paused)
        );
        INSERT INTO deployment_control (singleton) VALUES (true);
    """)


def downgrade():
    op.execute("""
        DO $$ BEGIN
          IF EXISTS (SELECT 1 FROM deployment_control WHERE admissions_paused OR claims_paused) THEN
            RAISE EXCEPTION 'Resume deployment control before removing it';
          END IF;
        END $$;
        DROP TABLE deployment_control;
    """)
