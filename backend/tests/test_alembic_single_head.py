"""migration head가 하나인지 확인한다.

두 PR이 같은 부모 revision에 각자 migration을 붙이면, 글자 충돌 없이 병합돼도 head가 둘이 되어
`alembic upgrade head`가 실패한다. DB 없이 revision 파일만 읽는다.
"""

from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory

ALEMBIC_INI = Path(__file__).resolve().parents[1] / "alembic.ini"


def test_alembic_has_a_single_head() -> None:
    heads = ScriptDirectory.from_config(Config(str(ALEMBIC_INI))).get_heads()
    assert len(heads) == 1, (
        f"migration head가 {len(heads)}개다: {sorted(heads)}. "
        "나중에 병합하는 PR의 첫 migration `down_revision`을 먼저 병합한 PR의 revision으로 바꾼다."
    )
