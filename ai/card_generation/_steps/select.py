"""선정(③). 판정을 거친 후보에서 카드 12장을 코드로 고름.

한 묶음에는 주제마다 한 장(#84 스키마의 UNIQUE(set_id, topic_id)). 같은 주제 후보가 여럿이면 에이전트가 먼저 낸 것을 씀.

  새 이야기  min_new장을 에이전트가 낸 순서로 먼저 잡음
  기존 주제  남은 자리를 _softmax(score / temperature) 확률로 한 장씩 비복원 추출
  남은 자리  기존 주제가 모자라면 남은 새 이야기로 채움

excluded 주제는 판정에서 이미 빠짐. 카드 위치는 기존 주제와 새 이야기를 번갈아 놓음(1~9번이 고르는 카드, 10~12번이 보충용).
12장을 못 채우면 실패.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from itertools import zip_longest
from typing import Literal

from card_generation._steps.match import Matched, MatchOutcome
from card_generation._steps.research.tools import TopicView
from card_generation._versions.base import SelectionRules

Bucket = Literal["new", "existing"]


@dataclass
class Picked:
    """고른 카드 한 장. bucket은 새 이야기(new)인지 기존 주제(existing)인지, reason은 고른 이유와 뽑힐 확률."""
    matched: Matched
    bucket: Bucket
    reason: str


@dataclass
class Selection:
    """추첨 결과. picked는 카드 위치 순서, dropped는 빠진 후보와 이유."""
    picked: list[Picked] = field(default_factory=list)
    dropped: list[dict] = field(default_factory=list)


class SelectionFailed(RuntimeError):
    """서로 다른 주제로 12장을 채우지 못한 실패."""
    pass


def select_cards(outcome: MatchOutcome, topics: list[TopicView], rules: SelectionRules,
                 rng: random.Random | None = None) -> Selection:
    """rng가 없으면 매번 다르게 뽑음. 같은 결과를 보려면 같은 seed의 Random을 넘김."""
    rng = rng or random.Random()
    scores = {t.topic_id: t.score for t in topics}
    sel = Selection()

    first: dict[str, Matched] = {}
    for m in sorted(outcome.kept, key=lambda m: m.no):
        key = m.topic_id or f"new:{m.new_key}"
        if key in first:
            sel.dropped.append({"no": m.no, "card_title": m.candidate.card_title,
                                "reason": f"같은 주제의 {first[key].no}번 후보가 먼저 있음"})
            continue
        first[key] = m
    new = [m for m in first.values() if m.new_key]
    existing = [m for m in first.values() if not m.new_key]

    reserved, new = new[:rules.min_new], new[rules.min_new:]
    drawn = _draw(existing, scores, rules.card_count - len(reserved), rules.temperature, rng)
    drawn_ids = {id(m) for m, _ in drawn}
    left = [m for m in existing if id(m) not in drawn_ids]

    old = [Picked(m, "existing", f"기존 주제. 점수 {scores[m.topic_id]:.2f}, 뽑힐 확률 {p:.0%}") for m, p in drawn]
    fresh = [Picked(m, "new", "새 이야기") for m in reserved]
    sel.picked = [p for pair in zip_longest(old, fresh) for p in pair if p]
    while new and len(sel.picked) < rules.card_count:
        sel.picked.append(Picked(new.pop(0), "new", "새 이야기(남은 자리)"))
    for m in left + new:
        sel.dropped.append({"no": m.no, "card_title": m.candidate.card_title, "reason": "12장이 다 참"})
    if len(sel.picked) < rules.card_count:
        raise SelectionFailed(f"서로 다른 주제가 {len(sel.picked)}개뿐이라 {rules.card_count}장을 채우지 못함")
    return sel


def _draw(pool: list[Matched], scores: dict[str, float], count: int, temperature: float,
         rng: random.Random) -> list[tuple[Matched, float]]:
    """점수 _softmax 확률로 count장을 비복원 추출. (후보, 그 차례에 뽑힐 확률)을 뽑힌 순서대로 돌려줌."""
    left, out = list(pool), []
    while left and len(out) < count:
        probs = _softmax([scores[m.topic_id] for m in left], temperature)
        i = rng.choices(range(len(left)), weights=probs)[0]
        out.append((left.pop(i), probs[i]))
    return out


def _softmax(scores: list[float], temperature: float) -> list[float]:
    """점수 목록을 확률로 바꿈. exp((점수 - 최댓값) / temperature)를 합으로 나눔. 최댓값을 빼는 건 exp 넘침 방지."""
    top = max(scores)
    weights = [math.exp((s - top) / temperature) for s in scores]
    total = sum(weights)
    return [w / total for w in weights]
