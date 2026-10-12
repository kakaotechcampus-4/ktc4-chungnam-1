"""주제 크기 평가. 실행이 끝난 뒤 주제마다 숨은 생애의 어느 항목을 다루는지
평가자 LLM에게 대조시킨다. 시스템 동작에는 영향을 주지 않는다.

    uv run python -m simulation.topic_size simulation/runs/<기록>.json [--again]   # 결과를 같은 JSON의 topic_eval에 넣고 화면을 다시 만든다

보는 것: 생애 항목·시절 하나에 단위가 몇 개 붙었나, 생애와 상관없는 일반 단위가 얼마나 되나, 같은 생애를 다룬 단위들에
결정이 어떻게 흩어졌나(하나만 막혀 옆 단위는 계속 나오는 경우). 생애 항목은 페르소나를 쓴 사람이 나눈 크기라 시절 묶음도 같이 본다.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel

from common.llm import chat_model
from simulation.llm_env import config_from_env

from . import roles
from .backends import get_backend, recommender_of


class TopicStory(BaseModel):
    index: int
    story_ids: list[str]
    kind: Literal["life", "general"]
    note: str


class TopicStories(BaseModel):
    topics: list[TopicStory]


def evaluate(run: dict[str, Any], model) -> dict[str, Any]:
    units = get_backend(recommender_of(run)).size_units(run)
    result = roles._call(model, TopicStories, "topic_story.md", {
        "life_story": run["persona"]["patient"]["life_story"],
        "topics": [{"index": i, "title": u["title"], "description": u["description"]} for i, u in enumerate(units)]})
    judged = {x.index: x for x in result.topics}
    known = {s["id"] for s in run["persona"]["patient"]["life_story"]}
    rows = []
    for i, u in enumerate(units):
        j = judged.get(i)
        rows.append({**u, "story_ids": [s for s in (j.story_ids if j else []) if s in known],
                     "kind": j.kind if j else "general", "note": j.note if j else "판정 없음"})
    return aggregate(run, rows)


def aggregate(run: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    period = {s["id"]: s["period"] for s in run["persona"]["patient"]["life_story"]}
    by_story: dict[str, list[int]] = {}
    by_period: dict[str, list[int]] = {}
    for i, r in enumerate(rows):
        for s in r["story_ids"]:
            by_story.setdefault(s, []).append(i)
        for pd in dict.fromkeys(period[s] for s in r["story_ids"]):
            by_period.setdefault(pd, []).append(i)
    return {"topics": rows, "by_story": by_story, "by_period": by_period,
            "summary": {"topics": len(rows), "general": sum(r["kind"] == "general" for r in rows),
                        "stories_covered": len(by_story), "stories_split": sum(len(v) >= 2 for v in by_story.values()),
                        "max_topics_per_story": max((len(v) for v in by_story.values()), default=0),
                        "max_topics_per_period": max((len(v) for v in by_period.values()), default=0)}}


def main(path: Path) -> None:
    from .viewer import build
    run = json.loads(path.read_text())
    if "--again" in sys.argv or "topic_eval" not in run:  # 판정은 LLM이라 이미 있으면 묶음만 다시 계산한다
        run["topic_eval"] = evaluate(run, chat_model(config_from_env()))
    else:
        run["topic_eval"] = aggregate(run, run["topic_eval"]["topics"])
    path.write_text(json.dumps(run, ensure_ascii=False, indent=1, default=str))
    print(json.dumps(run["topic_eval"]["summary"], ensure_ascii=False))
    print(build(path))


if __name__ == "__main__":
    main(Path(next(a for a in sys.argv[1:] if not a.startswith("--"))))
