"""판(promptVersion)별 프롬프트와 정해 둔 값. backend가 요청의 promptVersion으로 판을 고름.

판을 올릴 때는 v1을 복사해 v2를 만들고 고침. backend가 새 판으로 옮기기 전까지 이전 판을 지우지 않음.
"""

__all__ = ["VERSIONS", "LATEST", "SelectionRules", "Version"]

from card_generation._versions import v1
from card_generation._versions.base import SelectionRules, Version

VERSIONS: dict[int, Version] = {v.number: v for v in (v1.VERSION,)}
LATEST = VERSIONS[max(VERSIONS)]

