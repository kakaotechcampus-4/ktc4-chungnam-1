"""v3. v2에서 general 설명만 바꿈(조사 에이전트 agent.md와, 에이전트와 연결 판정이 함께 쓰는 same_story.md의 예).
match.md, writing_topics.md와 정해 둔 값은 v2와 같음.

general을 '연령대에 맞는 보편적인 옛 추억(계절, 음식, 노래, 동네 풍경 등)'에서 '어르신 자신의 취향과 겪은 일을 여쭐 수
있는 열린 소재'로 바꿈. 초기 정보가 없을 때 군고구마, 부채질 같은 계절 풍경과 감각 묘사 카드가 대부분을 차지하고,
김장, 빨래터처럼 모르는 생활상을 전제하는 카드가 나온다는 보고(2026-11-10)에 따른 것. backend 기본 버전도 3(2026-11-10).

아래는 v2 설명.
v2. v1에서 조사 에이전트 프롬프트와 문안 프롬프트를 바꾸고 아픈 경험 카드를 켬(PM 결정, 2026-11-09).

쌓아온 이야기나 초기 정보에 나온 아픈 경험은 후보로 낼 수 있게 하고, 그런 후보는 sensitive를 true로 표시하게 함.
문안 프롬프트는 규칙 7(근거 글의 단서로 구체적으로 여쭙기)과 8(sensitive 카드는 아픈 순간을 캐묻지 않기)이 더 있음.
아픈 기억 표시가 붙은 이야기(life_facts.sensitive)는 조사 도구 결과에 sensitive로 보이고, 그 이야기를 근거로 한 카드는
모델이 무엇을 적든 sensitive로 냄(generate.py, PM 결정 2026-11-10).
최근 기억을 시험하는 주제는 v1처럼 막음. 정해 둔 값은 아픈 경험 카드를 켜는 sensitive_cards 말고는 v1과 같고
모두 검증 전 값(ai/CLAUDE.md).
"""

from pathlib import Path

from card_generation._versions.base import SelectionRules, Version

VERSION = Version(
    number=3,
    prompts=Path(__file__).resolve().parent / "prompts",
    min_candidates=16, max_candidates=24,
    min_topics=14,         # 12장은 주제마다 한 장(#84 스키마 UNIQUE). 판정에서 빠질 몫까지 14개
    max_per_topic=3,
    min_new_topics=6,      # 선정의 새 이야기 5장을 채울 만큼
    decay=0.7,
    selection=SelectionRules(card_count=12, min_new=5, temperature=1.0),
    sensitive_cards=True,
)
