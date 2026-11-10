"""card set claimed at

`card_sets.claimed_at`은 worker가 작업을 가져간 시각이다. 작업이 끝나도 지우지 않는다.

4-1과 4-2는 worker가 가져가지 않은 작업을 `CARD_GENERATION_NOT_STARTED`로 정리한다.
작업이 정해진 시간보다 오래 기다렸다는 것만으로는 worker가 멈췄는지, 앞 작업을 처리하느라
바쁜지 알 수 없다. 그 시간 안에 가져간 작업이 하나라도 있으면 worker가 일하고 있다고 보고
기다리는 작업을 실패시키지 않는다.

기존 행은 가져간 시각을 알 수 없어 `NULL`로 둔다. 적용 시점에 처리 중이던 작업은 임대가
남아 있으므로 정리 기준이 따로 본다.

Revision ID: 202cdc671d82
Revises: e7c3a1f94d20
Create Date: 2026-11-09 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "202cdc671d82"
down_revision: Union[str, None] = "e7c3a1f94d20"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("ALTER TABLE card_sets ADD COLUMN claimed_at TIMESTAMPTZ")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("ALTER TABLE card_sets DROP COLUMN claimed_at")
