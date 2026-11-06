"""push devices

리포트 완료 푸시를 보낼 기기의 FCM 등록 ID(Firebase Installation ID, FID)를 계정과
잇는다. 앱이 알림 수신에 동의한 계정에서 등록(1-7)하고, 로그아웃이나 동의 철회 때
해제(1-8)한다.

- `fid`: 앱이 FCM 에 등록하고 받은 FID. 한 앱 설치본마다 하나라서 기본키로 둔다.
  같은 기기에서 다른 계정이 등록하면 그 계정으로 옮겨, 앞 계정의 알림이 그 기기로
  가지 않게 한다.
- `user_id`: 알림을 받을 계정. 탈퇴하면 함께 지운다.
- `registered_at`: 마지막으로 등록한 시각. 앱은 켤 때마다 다시 등록하므로 오래된
  등록을 고를 때 쓴다(FCM 은 한 달 넘게 연결이 없으면 오래된 등록으로 본다).

알림 내용과 발송 기록은 담지 않는다.

Revision ID: b91d2e7c4a60
Revises: a4f6c1d83b29
Create Date: 2026-11-06 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b91d2e7c4a60'
down_revision: Union[str, Sequence[str], None] = 'a4f6c1d83b29'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("""
CREATE TABLE push_devices (
    fid           VARCHAR(64) PRIMARY KEY CHECK (fid ~ '^[A-Za-z0-9_-]+$'),
    user_id       UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
""")
    op.execute("""
CREATE INDEX idx_push_devices_user ON push_devices(user_id)
""")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DROP TABLE push_devices")
