"""'같은 이야기' 판정 평가. 연결 판정(②)에 합성 사례를 넣고, 후보가 기존 주제에 붙는지 정답과 비교한다.

    uv run python -m card_generation.tests.eval.same_story_eval --label v1 --same-story path/to/same_story.md --match path/to/match.md

자료는 tests/eval/data/same-story.json(이전 카드 MVP의 추천하지 않기 평가셋)이다. 어르신 7명, 기존 주제 14개, 후보 77개.
정답은 AI가 정한 것이라 사람 검수가 필요하다. ambiguous는 범위를 정해야 답이 나오는 짝이라 채점에서 빼고 따로 센다.

기존 주제를 두 가지로 넣어 본다(아래 group은 이 평가 안에서만 쓰는 이름).
  excluded  추천하지 않기 주제(excluded: true). 판정 프롬프트의 "애매하면 같은 이야기로 본다"가 켜진다. 운영에서 막힌 주제를 거를 때와 같다.
  revisit   보통 주제(excluded: false). 그 규칙이 꺼져서 정의 글만으로 크기를 어떻게 판단하는지 본다.
"""

from __future__ import annotations

import argparse
import json
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Any

from card_generation._steps.match import judge, match_prompt
from card_generation._versions import LATEST
from common.llm import chat_model
from simulation.llm_env import config_from_env

HERE = Path(__file__).resolve().parent
DATA = HERE / "data/same-story.json"
SAME = ("same_overlap", "same_paraphrase", "same_implicit")
DIFF = ("diff_overlap", "diff_context", "diff")


def payload(case: dict[str, Any], group: str) -> dict[str, Any]:
    existing = [{"topic_id": f"t{i}", "title": t["topicTitle"], "description": t["description"], "excluded": group == "excluded",
                 "evidence_texts": t["evidenceTexts"]} for i, t in enumerate(case["blockedTopics"], 1)]
    cands = [{"candidate_id": f"c{i}", "card_title": c["topicTitle"], "angle": c["note"],
              "kind": "personal" if c["evidenceTexts"] else "general", "evidence_texts": c["evidenceTexts"]}
             for i, c in enumerate(case["candidates"], 1)]
    return {"existing_topics": existing, "candidates": cands}


def run_case(model, prompt: str, case: dict[str, Any], group: str) -> list[dict[str, Any]]:
    started = time.monotonic()
    result = judge(model, payload(case, group), prompt)
    seconds = round(time.monotonic() - started, 1)
    keys = {f"t{i}": t["topicKey"] for i, t in enumerate(case["blockedTopics"], 1)}
    answers = {a.candidate_id: a for a in result.assignments}
    rows = []
    for i, c in enumerate(case["candidates"], 1):
        a = answers.get(f"c{i}")
        predicted = "MISSING" if a is None else (keys.get(a.topic_id, "UNKNOWN") if a.topic_id else None)
        rows.append({"case": case["caseId"], "group": group, "title": c["topicTitle"], "tag": c["tag"],
                     "expected": c["expected"], "predicted": predicted, "new_key": a.new_key if a else None,
                     "reason": a.reason if a else "", "seconds": seconds})
    return rows


def score(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_tag: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for r in rows:
        if r["tag"] == "ambiguous":
            by_tag[r["tag"]][0] += r["predicted"] is not None
        elif r["tag"] in SAME:
            by_tag[r["tag"]][0] += r["predicted"] != r["expected"]   # 놓침(붙여야 하는데 안 붙임)
        else:
            by_tag[r["tag"]][0] += r["predicted"] is not None        # 잘못 붙임
        by_tag[r["tag"]][1] += 1
    misses = sum(by_tag[t][0] for t in SAME)
    false_merges = sum(by_tag[t][0] for t in DIFF)
    # 새 주제로 간 후보가 판정 안에서 몇 개씩 묶였나(정답 없음, 크기 참고용)
    groups = Counter((r["case"], r["new_key"]) for r in rows if r["predicted"] is None and r["new_key"])
    size = round(sum(groups.values()) / len(groups), 2) if groups else 0
    return {"by_tag": dict(by_tag), "misses": misses, "same_total": sum(by_tag[t][1] for t in SAME),
            "false_merges": false_merges, "diff_total": sum(by_tag[t][1] for t in DIFF), "new_group_size": size}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--same-story", type=Path)
    ap.add_argument("--match", type=Path)
    ap.add_argument("--repeat", type=int, default=2)
    args = ap.parse_args()
    data = json.loads(DATA.read_text())
    prompt = match_prompt(LATEST, args.match, args.same_story)
    model = chat_model(config_from_env())
    jobs = [(case, group) for _ in range(args.repeat) for group in ("excluded", "revisit") for case in data["cases"]]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda job: run_case(model, prompt, *job), jobs))
    rows = [r for rs in results for r in rs]
    summary = {g: score([r for r in rows if r["group"] == g]) for g in ("excluded", "revisit")}
    out = HERE / "runs" / f"same-story-{args.label}-{datetime.now():%Y%m%d-%H%M%S}.json"
    out.write_text(json.dumps({"label": args.label, "repeat": args.repeat, "summary": summary, "rows": rows},
                              ensure_ascii=False, indent=1))
    for g, s in summary.items():
        tags = ", ".join(f"{t} {s['by_tag'][t][0]}/{s['by_tag'][t][1]}" for t in (*SAME, *DIFF, "ambiguous")
                         if t in s["by_tag"])
        print(f"[{args.label}/{g}] 놓침 {s['misses']}/{s['same_total']}, 잘못 붙임 {s['false_merges']}/{s['diff_total']}, "
              f"새 주제 묶음 평균 {s['new_group_size']}개 | {tags}")
    print(f"결과: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
