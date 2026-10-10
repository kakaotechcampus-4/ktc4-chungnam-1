"""1판. 모두 검증 전 값(local_ai/CLAUDE.md)."""

from pathlib import Path

from card_generation._versions.base import SelectionRules, Version

VERSION = Version(
    number=1,
    prompts=Path(__file__).resolve().parent / "prompts",
    min_candidates=16, max_candidates=24,
    min_topics=14,         # 12장은 주제마다 한 장(#84 스키마 UNIQUE). 판정에서 빠질 몫까지 14개
    max_per_topic=3,
    min_new_topics=6,      # 선정의 새 이야기 5장을 채울 만큼
    decay=0.7,
    selection=SelectionRules(card_count=12, min_new=5, temperature=1.0),
)
