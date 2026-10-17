"""life fact story category and image

일대기(작업 D)의 이야기 분류와 기본 그림 번호를 `life_facts`에 저장. 그림 파일은 앱
`assets`에 있고 서버는 번호만 가짐.

- `story_category`: `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`
- `image_number`: 1~5. 분류마다 기본 그림이 5장

필드 이름은 임시(작업 D 문서 미정 D1, D2). 기존 행은 `other`, 1로 채움(미정 D9). 2-6은 두 값을
항상 받고, 기본값은 기존 행과 7-4로 만드는 이야기(미정 D5)를 위한 것.

Revision ID: b7e2c4a9d153
Revises: d466bb108618
Create Date: 2026-10-17 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b7e2c4a9d153'
down_revision: Union[str, Sequence[str], None] = 'd466bb108618'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
ALTER TABLE life_facts
    ADD COLUMN story_category VARCHAR(10) NOT NULL DEFAULT 'other'
        CONSTRAINT life_facts_story_category_check CHECK (story_category IN
            ('family', 'hobby', 'work', 'hometown', 'friend', 'travel', 'other')),
    ADD COLUMN image_number SMALLINT NOT NULL DEFAULT 1
        CONSTRAINT life_facts_image_number_check CHECK (image_number BETWEEN 1 AND 5)
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("""
ALTER TABLE life_facts
    DROP COLUMN image_number,
    DROP COLUMN story_category
""")
