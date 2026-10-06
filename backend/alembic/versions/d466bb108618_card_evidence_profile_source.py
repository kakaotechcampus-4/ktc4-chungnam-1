"""card evidence profile source

카드 근거(`conversation_cards.evidence_source`)에 `profile` 추가. 세부 정보 네 항목(하시던 일, 고향,
취미, 가족)은 `profiles`의 열이라 `fact_id`가 없음. 근거 항목은 `{"profileField": "occupation"}`처럼
칸 이름으로 가리킴. `profile`도 `life_fact`, `photo`처럼 근거가 하나 이상 있어야 함.

downgrade는 `profile` 카드를 `none`으로 바꾸고 근거를 비움.

Revision ID: d466bb108618
Revises: f301b2505814
Create Date: 2026-10-06 17:22:06.914628

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'd466bb108618'
down_revision: Union[str, Sequence[str], None] = 'f301b2505814'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
ALTER TABLE conversation_cards
    DROP CONSTRAINT conversation_cards_evidence_source_check,
    DROP CONSTRAINT conversation_cards_check2,
    ADD CHECK (evidence_source IN ('life_fact', 'photo', 'profile', 'none')),
    ADD CHECK (CASE WHEN jsonb_typeof(evidence) <> 'array' THEN false
                    WHEN evidence_source IN ('life_fact', 'photo', 'profile') THEN jsonb_array_length(evidence) > 0
                    ELSE evidence = '[]'::jsonb END)
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("""
UPDATE conversation_cards SET evidence_source = 'none', evidence = '[]'::jsonb
 WHERE evidence_source = 'profile'
""")
    op.execute("""
ALTER TABLE conversation_cards
    DROP CONSTRAINT conversation_cards_evidence_source_check,
    DROP CONSTRAINT conversation_cards_check2,
    ADD CHECK (evidence_source IN ('life_fact', 'photo', 'none')),
    ADD CHECK (CASE WHEN jsonb_typeof(evidence) <> 'array' THEN false
                    WHEN evidence_source IN ('life_fact', 'photo') THEN jsonb_array_length(evidence) > 0
                    ELSE evidence = '[]'::jsonb END)
""")
