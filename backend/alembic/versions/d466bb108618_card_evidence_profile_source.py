"""card evidence profile source

카드 근거(`conversation_cards.evidence_source`)에 `profile` 추가. 세부 정보 네 항목(하시던 일, 고향,
취미, 가족)은 `profiles`의 열이라 `fact_id`가 없음. 근거 항목은 `{"profileField": "occupation"}`처럼
칸 이름으로 가리킴. `profile`도 `life_fact`, `photo`처럼 근거가 하나 이상 있어야 함.

카드 문구도 막음. 카드 제목, 설명, 첫 질문이 공백뿐이면 안 되고 꼬리 질문은 정확히 3개에
모두 내용이 있어야 함(API 명세 4-1 처리). BE가 저장 전에 먼저 거르고, 이 제약은 마지막 방어선.

downgrade는 `profile` 카드를 `none`으로 바꾸고 근거를 비움. 문구 제약은 꼬리 질문 1개 이상으로 되돌림.

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
    op.execute(r"""
ALTER TABLE conversation_cards
    DROP CONSTRAINT conversation_cards_follow_up_questions_check,
    ADD CONSTRAINT conversation_cards_card_title_check CHECK (card_title ~ '\S'),
    ADD CONSTRAINT conversation_cards_description_check CHECK (description ~ '\S'),
    ADD CONSTRAINT conversation_cards_primary_question_check CHECK (primary_question ~ '\S'),
    ADD CONSTRAINT conversation_cards_follow_up_questions_check CHECK (
        cardinality(follow_up_questions) = 3
        AND coalesce(follow_up_questions[1] ~ '\S' AND follow_up_questions[2] ~ '\S'
                     AND follow_up_questions[3] ~ '\S', false))
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("""
ALTER TABLE conversation_cards
    DROP CONSTRAINT conversation_cards_card_title_check,
    DROP CONSTRAINT conversation_cards_description_check,
    DROP CONSTRAINT conversation_cards_primary_question_check,
    DROP CONSTRAINT conversation_cards_follow_up_questions_check,
    ADD CONSTRAINT conversation_cards_follow_up_questions_check
        CHECK (cardinality(follow_up_questions) >= 1)
""")
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
