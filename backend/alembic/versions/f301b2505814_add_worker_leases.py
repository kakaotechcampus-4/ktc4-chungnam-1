"""add worker leases

카드 생성(`card_sets`)과 사진 분석(`photos`)도 음성 분석 작업처럼 worker가 행 하나를
임대해 처리한다. 임대 시각이 없으면 여러 worker가 같은 작업을 동시에 가져가는 것을
막을 수 없고, 처리 중에 worker가 멈춘 작업을 찾을 수 없다.

- `lease_expires_at`: 처리 중인 작업의 임대 만료 시각. 카드 생성은 `running` 중에서
  임대가 없는 작업이 대기 중인 작업이다. 사진은 `processing`일 때만 둔다.
- `attempt_count`: 작업을 가져간 횟수.

Revision ID: f301b2505814
Revises: f8fd6d0e862c
Create Date: 2026-10-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'f301b2505814'
down_revision: Union[str, Sequence[str], None] = 'f8fd6d0e862c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
ALTER TABLE card_sets
    ADD COLUMN lease_expires_at TIMESTAMPTZ,
    ADD COLUMN attempt_count    SMALLINT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    ADD CONSTRAINT card_sets_lease_check CHECK (lease_expires_at IS NULL OR status = 'running')
""")
    op.execute("""
CREATE INDEX idx_card_sets_waiting
    ON card_sets(created_at) WHERE status = 'running' AND lease_expires_at IS NULL
""")
    op.execute("""
ALTER TABLE photos
    ADD COLUMN lease_expires_at TIMESTAMPTZ,
    ADD COLUMN attempt_count    SMALLINT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    ADD CONSTRAINT photos_lease_check
        CHECK ((analysis_status = 'processing') = (lease_expires_at IS NOT NULL))
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("""
ALTER TABLE photos
    DROP CONSTRAINT photos_lease_check,
    DROP COLUMN attempt_count,
    DROP COLUMN lease_expires_at
""")
    op.execute("DROP INDEX idx_card_sets_waiting")
    op.execute("""
ALTER TABLE card_sets
    DROP CONSTRAINT card_sets_lease_check,
    DROP COLUMN attempt_count,
    DROP COLUMN lease_expires_at
""")
