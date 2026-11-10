"""photo analysis consent

AI 이미지 분석 선택 동의(`photoAnalysis`)를 동의 이력에 더한다. 문구와 범위는
`docs/legal/consent-draft.md`의 "AI 이미지 분석"(2026-10-14 PM 결정)을 따른다.

- `consent_records.photo_analysis`: 기존 이력은 모두 거부(false)로 채운다. 지금까지는
  이 항목을 묻지 않았으므로 동의한 것으로 꾸미지 않는다.
- `current_consents`는 `SELECT DISTINCT ON (user_id) *`로 만든 view라 열을 더해도
  자동으로 늘지 않는다. 같은 정의로 다시 만들어 새 열을 포함한다(새 열은 끝에 붙는다).
- 사진 분석 worker는 이 값이 true인 계정의 사진만 가져가고 저장 직전에 다시 확인한다.

Revision ID: e7c3a1f94d20
Revises: b91d2e7c4a60
Create Date: 2026-11-07 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e7c3a1f94d20"
down_revision: Union[str, None] = "b91d2e7c4a60"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

VIEW = """
CREATE OR REPLACE VIEW current_consents AS
SELECT DISTINCT ON (user_id) *
  FROM consent_records
 ORDER BY user_id, recorded_at DESC, record_id DESC
"""


def upgrade() -> None:
    op.execute(
        "ALTER TABLE consent_records "
        "ADD COLUMN photo_analysis BOOLEAN NOT NULL DEFAULT false"
    )
    op.execute(VIEW)


def downgrade() -> None:
    # 열을 지우기 전에 view를 열 없이 다시 만들어야 한다. CREATE OR REPLACE는 열을
    # 줄일 수 없으므로 지우고 만든다.
    op.execute("DROP VIEW current_consents")
    op.execute("ALTER TABLE consent_records DROP COLUMN photo_analysis")
    op.execute(VIEW.replace("CREATE OR REPLACE VIEW", "CREATE VIEW"))
