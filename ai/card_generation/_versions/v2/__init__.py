"""2판. 1판에서 조사 에이전트 프롬프트만 바꿈(PM 결정, 2026-11-09).

쌓아온 이야기나 초기 정보에 나온 아픈 경험은 후보로 낼 수 있게 하고, 그런 후보는 sensitive를 true로 표시하게 함.
최근 기억을 시험하는 주제는 1판처럼 막음. 정해 둔 값은 아픈 경험 카드를 켜는 sensitive_cards 말고는 1판과 같고
모두 검증 전 값(ai/CLAUDE.md).
"""

from pathlib import Path

from card_generation._versions.base import SelectionRules, Version

VERSION = Version(
    number=2,
    prompts=Path(__file__).resolve().parent / "prompts",
    min_candidates=16, max_candidates=24,
    min_topics=14,         # 12장은 주제마다 한 장(#84 스키마 UNIQUE). 판정에서 빠질 몫까지 14개
    max_per_topic=3,
    min_new_topics=6,      # 선정의 새 이야기 5장을 채울 만큼
    decay=0.7,
    selection=SelectionRules(card_count=12, min_new=5, temperature=1.0),
    sensitive_cards=True,
)
