"""card generation log refs

PM 결정(2026-11-08): 카드 생성 기록(`card_sets.generation_log`)에는 생성에 보낸 글을 복사하지
않고 ID만 남긴다. 새 코드가 쓰는 형태로 기존 행을 고친다. 규칙은
`app/services/card_generation_log.py`의 `reference_log` 하나이며 새 코드도 같은 함수로 기록을 쓴다.

- 이미 글이 없는 행, `{"input": null}`, 진행 중인 작업(NULL)은 UPDATE하지 않는다. 다시 적용해도
  바뀌는 행이 없다.
- 열과 제약은 바꾸지 않아 이전 코드가 실행 중이어도 적용할 수 있다. 다만 적용한 뒤 api와
  card-worker를 새 코드로 다시 띄우기 전까지 이전 card-worker가 쓴 기록에는 글이 남는다. 배포 순서와
  다시 고치는 방법은 `docs/deployment.md`의 "카드 생성 기록 정리"에 있다.
- downgrade는 아무것도 하지 않는다. 지운 글은 되살리지 않는다.

Revision ID: 685f243e9f1f
Revises: e7c3a1f94d20
Create Date: 2026-11-09 12:00:00.000000

"""
import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.services.card_generation_log import reference_log

# revision identifiers, used by Alembic.
revision: str = "685f243e9f1f"
down_revision: Union[str, Sequence[str], None] = "e7c3a1f94d20"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """글이 든 기록만 ID만 남긴 형태로 고친다."""
    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT set_id, generation_log FROM card_sets"
            " WHERE generation_log IS NOT NULL ORDER BY set_id"
        )
    ).all()
    for set_id, log in rows:
        converted = reference_log(log)
        if converted != log:
            bind.execute(
                sa.text(
                    "UPDATE card_sets SET generation_log = CAST(:log AS jsonb)"
                    " WHERE set_id = :set_id"
                ),
                {"log": json.dumps(converted), "set_id": set_id},
            )


def downgrade() -> None:
    """지운 글은 되살릴 수 없어 아무것도 하지 않는다."""
