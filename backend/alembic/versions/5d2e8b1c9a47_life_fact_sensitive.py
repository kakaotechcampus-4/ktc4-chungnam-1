"""life fact sensitive

PM 결정(2026-11-10): 보호자가 지우지 않는 한 아픈 이야기도 일대기에 남기고 카드에도 쓴다. 일대기는
그 이야기에 부드러운 표시를 붙이고, 그 이야기를 근거로 한 카드에는 '조심스러운 이야기' 표시가 붙는다.

- `life_facts.sensitive`: 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 이야기. 7-4가 승인한 이야기
  후보의 `life_fact_proposals.sensitive`를 그대로 옮기고, 보호자가 2-7로 바꿀 수 있다. 카드 생성(4-1)
  입력에 담는다.

이미 승인해 만든 이야기는 출처 제안(`source_proposal_id`)의 표시를 옮긴다. 이 열이 생기기 전 7-4가
표시를 버린 것을 되살리는 것이다. 출처 제안이 없는 이야기(2-6으로 담은 것)는 `false`다. 열을 더하고
값을 채우기만 하므로 이전 코드가 실행 중이어도 적용할 수 있다. downgrade는 열을 지운다. 그동안
보호자가 2-7로 바꾼 표시는 되살리지 않는다.

Revision ID: 5d2e8b1c9a47
Revises: a926d137e405
Create Date: 2026-11-10 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '5d2e8b1c9a47'
down_revision: Union[str, Sequence[str], None] = 'a926d137e405'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("ALTER TABLE life_facts ADD COLUMN sensitive BOOLEAN NOT NULL DEFAULT false")
    op.execute("""
UPDATE life_facts f SET sensitive = true
  FROM life_fact_proposals p
 WHERE p.proposal_id = f.source_proposal_id AND p.sensitive
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("ALTER TABLE life_facts DROP COLUMN sensitive")
