"""card liked at

보호자가 지난 카드를 다시 보며 마음에 드는 카드에 남기는 "좋았어요" 표시를
`conversation_cards.liked_at`에 저장. 표시하지 않은 카드는 `NULL`이고 표시를 지우면 다시 `NULL`.

보호자 평가(6-1)의 `review_reaction`과 따로 둠. 평가는 회차마다 한 번 저장하고 리포트 생성에
쓰이지만, 이 표시는 평가 뒤에도 언제든 켜고 끌 수 있고 고르지 않은 카드에도 남길 수 있음.

Revision ID: a4f6c1d83b29
Revises: d73f0b5ca921
Create Date: 2026-10-27 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'a4f6c1d83b29'
down_revision: Union[str, Sequence[str], None] = 'd73f0b5ca921'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("ALTER TABLE conversation_cards ADD COLUMN liked_at TIMESTAMPTZ")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("ALTER TABLE conversation_cards DROP COLUMN liked_at")
