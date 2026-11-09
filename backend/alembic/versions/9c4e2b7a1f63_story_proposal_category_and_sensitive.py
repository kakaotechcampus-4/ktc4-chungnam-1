"""story proposal category and sensitive

PM 결정(2026-11-09): AI가 이야기 후보에 일대기 분류를 붙이고, 아픈 기억일 수 있는 후보와 카드를
표시한다. 보호자는 변경 사항 확인(7-4)에서 분류를 고칠 수 있다.

- `life_fact_proposals.story_category`: AI가 고른 분류. 값은 `life_facts.story_category`와 같은
  `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`. 7-4 승인 때 보호자가 바꾸지
  않으면 이 값으로 이야기를 만든다.
- `life_fact_proposals.sensitive`: 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 후보.
- `conversation_cards.sensitive`: 저장된 이야기나 세부 정보의 아픈 경험을 다루는 카드.

기존 행은 `other`, `false`로 채운다. 열만 더하므로 이전 코드가 실행 중이어도 적용할 수 있다.
downgrade는 세 열을 지운다. 그동안 저장된 분류와 표시는 되살리지 않는다.

Revision ID: 9c4e2b7a1f63
Revises: 685f243e9f1f
Create Date: 2026-11-09 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '9c4e2b7a1f63'
down_revision: Union[str, Sequence[str], None] = '685f243e9f1f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
ALTER TABLE life_fact_proposals
    ADD COLUMN story_category VARCHAR(20) NOT NULL DEFAULT 'other'
        CONSTRAINT life_fact_proposals_story_category_check CHECK (story_category IN
            ('family', 'hobby', 'work', 'hometown', 'friend', 'travel', 'other')),
    ADD COLUMN sensitive BOOLEAN NOT NULL DEFAULT false
""")
    op.execute(
        "ALTER TABLE conversation_cards ADD COLUMN sensitive BOOLEAN NOT NULL DEFAULT false"
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("ALTER TABLE conversation_cards DROP COLUMN sensitive")
    op.execute("""
ALTER TABLE life_fact_proposals
    DROP COLUMN sensitive,
    DROP COLUMN story_category
""")
