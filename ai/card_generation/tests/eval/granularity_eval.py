"""주제 크기 평가. 연결 판정(②)이 후보를 얼마나 크게 묶는지 tests/eval/data/granularity.json의 정답과 비교한다.

    uv run python -m card_generation.tests.eval.granularity_eval --label v2 [--same-story ...] [--match ...] [--repeat 3]

세 가지를 센다.
  기존 주제 연결  붙어야 할 기존 주제에 붙었나. 엉뚱한 주제에 끌려 붙으면 틀림
  과하게 묶음     정답에서 다른 묶음인 새 후보 두 개를 같은 새 주제로 묶은 쌍
  쪼갬           정답에서 같은 묶음인 새 후보 두 개를 다른 새 주제로 나눈 쌍
ambiguous와 scope는 채점하지 않고 판정 결과만 적는다. 정답은 확정되지 않은 제안 기준이다.
"""

from __future__ import annotations

import argparse
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from itertools import combinations
from pathlib import Path
from typing import Any

from card_generation._steps.match import judge, match_prompt
from card_generation._versions import LATEST
from common.llm import chat_model
from simulation.llm_env import config_from_env

HERE = Path(__file__).resolve().parent
DATA = HERE / "data/granularity.json"


def payload(case: dict[str, Any]) -> dict[str, Any]:
    existing = [{"topic_id": f"t{i}", "title": t["title"], "description": t["description"],
                 "excluded": t.get("group") == "excluded", "evidence_texts": t["evidence"]}
                for i, t in enumerate(case["existing"], 1)]
    cands = [{"candidate_id": f"c{i}", "card_title": c["title"], "angle": c["angle"],
              "kind": "personal" if c["evidence"] else "general", "evidence_texts": c["evidence"]}
             for i, c in enumerate(case["candidates"], 1)]
    return {"existing_topics": existing, "candidates": cands}


def run_case(model, prompt: str, case: dict[str, Any]) -> dict[str, Any]:
    result = judge(model, payload(case), prompt)
    keys = {f"t{i}": t["key"] for i, t in enumerate(case["existing"], 1)}
    answers = {a.candidate_id: a for a in result.assignments}
    new_titles = {n.new_key: n.title for n in result.new_topics}
    rows = []
    for i, c in enumerate(case["candidates"], 1):
        a = answers.get(f"c{i}")
        rows.append({"title": c["title"], "tag": c.get("tag"), "expected": c["expected"],
                     "topic": keys.get(a.topic_id, "UNKNOWN") if a and a.topic_id else None,
                     "new_key": a.new_key if a else None,
                     "new_title": new_titles.get(a.new_key) if a and a.new_key else None,
                     "reason": a.reason if a else "판정 없음"})
    return {"case": case["caseId"], "rows": rows}


def score(results: list[dict[str, Any]]) -> dict[str, Any]:
    link_ok = link_total = over = over_total = split = split_total = 0
    wrong: list[str] = []
    for res in results:
        graded = [r for r in res["rows"] if r["expected"]]
        for r in graded:
            exp = r["expected"]
            if "topic" in exp:
                link_total += 1
                if r["topic"] == exp["topic"]:
                    link_ok += 1
                else:
                    wrong.append(f"{res['case']}: '{r['title']}' → {r['topic'] or '새 주제 ' + str(r['new_title'])} "
                                 f"(정답 {exp['topic']})")
            elif r["topic"] is not None:
                link_total += 1
                wrong.append(f"{res['case']}: '{r['title']}' → 기존 {r['topic']}에 끌려 붙음(정답 새 주제)")
            else:
                link_total += 1
                link_ok += 1
        news = [r for r in graded if "group" in r["expected"] and r["topic"] is None]
        for a, b in combinations(news, 2):
            same_exp = a["expected"]["group"] == b["expected"]["group"]
            same_pred = a["new_key"] == b["new_key"]
            if same_exp:
                split_total += 1
                if not same_pred:
                    split += 1
                    wrong.append(f"{res['case']}: '{a['title']}'와 '{b['title']}'를 나눔(같은 이야기)")
            else:
                over_total += 1
                if same_pred:
                    over += 1
                    wrong.append(f"{res['case']}: '{a['title']}'와 '{b['title']}'를 묶음(다른 이야기)")
    return {"link": [link_ok, link_total], "over_merge": [over, over_total], "split": [split, split_total],
            "wrong": wrong}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--same-story", type=Path)
    ap.add_argument("--match", type=Path)
    ap.add_argument("--repeat", type=int, default=3)
    args = ap.parse_args()
    data = json.loads(DATA.read_text())
    prompt = match_prompt(LATEST, args.match, args.same_story)
    model = chat_model(config_from_env())
    jobs = [case for _ in range(args.repeat) for case in data["cases"]]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda case: run_case(model, prompt, case), jobs))
    s = score(results)
    unscored = [f"{res['case']}: '{r['title']}'({r['tag']}) → {r['topic'] or '새 주제 ' + str(r['new_title'])}"
                for res in results for r in res["rows"] if r["tag"]]
    out = HERE / "runs" / f"granularity-{args.label}-{datetime.now():%Y%m%d-%H%M%S}.json"
    out.write_text(json.dumps({"label": args.label, "repeat": args.repeat, "score": s, "unscored": unscored,
                               "results": results}, ensure_ascii=False, indent=1))
    print(f"[{args.label}] 기존 주제 연결 {s['link'][0]}/{s['link'][1]} 맞음, "
          f"과하게 묶음 {s['over_merge'][0]}/{s['over_merge'][1]}쌍, 쪼갬 {s['split'][0]}/{s['split'][1]}쌍")
    for w in sorted(set(s["wrong"])):
        print("  틀림:", w, f"(x{s['wrong'].count(w)})")
    for u in sorted(set(unscored)):
        print("  채점 안 함:", u, f"(x{unscored.count(u)})")
    print(f"결과: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
