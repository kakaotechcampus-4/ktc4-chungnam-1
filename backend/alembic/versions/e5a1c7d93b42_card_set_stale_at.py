"""card set stale at

`card_sets.stale_at`은 카드 묶음을 받은 뒤 보호자가 프로필이나 일대기를 고친 시각임(#158).
값이 있으면 그 묶음으로는 면회를 시작할 수 없고(5-1), 4-1로 새 묶음을 만들 수 있음.
면회에 쓴 묶음에는 찍지 않음.

Revision ID: e5a1c7d93b42
Revises: b7e2c4a9d153
Create Date: 2026-10-26 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'e5a1c7d93b42'
down_revision: Union[str, Sequence[str], None] = 'b7e2c4a9d153'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
ALTER TABLE card_sets
    ADD COLUMN stale_at TIMESTAMPTZ,
    ADD CONSTRAINT card_sets_stale_check
        CHECK (stale_at IS NULL OR (status = 'completed' AND session_id IS NULL))
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("ALTER TABLE card_sets DROP COLUMN stale_at")
