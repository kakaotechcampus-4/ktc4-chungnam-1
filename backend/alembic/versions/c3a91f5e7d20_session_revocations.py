"""session revocations

로그아웃과 탈퇴로 폐기한 세션의 `jti`를 그 세션의 만료 시각까지 남긴다. 이전에는 API
프로세스 메모리에만 있어, 서버를 다시 띄우면 그 전에 폐기한 세션이 만료까지 다시
통과했다(#101, #129).

- `token_id`: 세션 JWT의 `jti`. 세션마다 새로 만든 무작위 값이다.
- `expires_at`: 그 세션의 만료 시각. 지난 행은 서명 확인에서 이미 거절되므로 다음
  폐기 때 지운다.

계정 식별자, 구글 `sub`와 토큰 원문은 담지 않는다. `users`를 참조하지 않으므로 탈퇴로
계정이 지워져도 그 요청에 쓴 세션의 폐기 기록은 만료까지 남는다.

Revision ID: c3a91f5e7d20
Revises: d466bb108618
Create Date: 2026-10-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'c3a91f5e7d20'
down_revision: Union[str, Sequence[str], None] = 'd466bb108618'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
CREATE TABLE session_revocations (
    token_id   VARCHAR(64) PRIMARY KEY CHECK (length(btrim(token_id)) > 0),
    expires_at TIMESTAMPTZ NOT NULL
)
""")
    op.execute("""
CREATE INDEX idx_session_revocations_expires ON session_revocations(expires_at)
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DROP TABLE session_revocations")
