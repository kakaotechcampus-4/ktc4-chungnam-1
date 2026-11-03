"""기존 보관 기한 안에서 실패한 리포트를 수동 재처리한다."""
from alembic import op

revision = "d73f0b5ca921"
down_revision = "c62e19a4b308"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE speech_analysis_jobs
          DROP CONSTRAINT speech_analysis_jobs_check3,
          ADD CONSTRAINT speech_analysis_jobs_check3
            CHECK (transcript IS NULL OR status IN ('sttCompleted','generatingReport','failed')),
          ADD COLUMN retry_of_analysis_id UUID
            REFERENCES speech_analysis_jobs(analysis_id) ON DELETE SET NULL,
          ADD CONSTRAINT uq_speech_analysis_retry_parent UNIQUE (retry_of_analysis_id)
    """)


def downgrade():
    op.execute("""
        DO $$ BEGIN
          IF EXISTS (SELECT 1 FROM speech_analysis_jobs
                     WHERE (status='failed' AND transcript IS NOT NULL)
                        OR retry_of_analysis_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Speech recovery data exists; review backup and rollback before downgrade';
          END IF;
        END $$;
        ALTER TABLE speech_analysis_jobs
          DROP COLUMN retry_of_analysis_id,
          DROP CONSTRAINT speech_analysis_jobs_check3,
          ADD CONSTRAINT speech_analysis_jobs_check3
            CHECK (transcript IS NULL OR status IN ('sttCompleted','generatingReport'))
    """)
