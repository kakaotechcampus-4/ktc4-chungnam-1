"""합성 시나리오를 DB에 넣고 조사 에이전트를 돌려, DB에 있던 것과 에이전트가 낸 후보를 나란히 적는다.

    uv run python -m simulation.rules.run_scenario third-visit            # 시나리오 하나
    uv run python -m simulation.rules.run_scenario --all                  # 전부

DB는 TOPIC_REC_DATABASE_URL로 정한다. 스키마(backend/database/init.sql)가 이미 적용된 테스트용 DB여야 한다.
같은 시나리오를 다시 넣으면 그 계정을 지우고 새로 넣는다. 결과는 runs/에 마크다운과 JSON으로 남는다(커밋하지 않음).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import psycopg

from card_generation._steps.match import MatchOutcome, run_match
from card_generation._steps.research.agent import AgentFailed, AgentSession
from card_generation._steps.research.candidates import CardCandidate, evidence_refs
from card_generation._steps.research.store import ProfileStore
from card_generation._steps.research.tools import FIELD_LABELS
from card_generation._versions import LATEST
from common.llm import ChatConfig, chat_model
from simulation.backends.context import build_context
from simulation.llm_env import config_from_env
from simulation.rules.seed_mock import scenario_names, seed_scenario

HERE = Path(__file__).resolve().parent
DB_ENV = "TOPIC_REC_DATABASE_URL"


def _cut(text: str, n: int = 60) -> str:
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1] + "…"


def _md_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def check(store: ProfileStore, candidates: list[CardCandidate]) -> tuple[list[dict], list[str]]:
    """후보마다 연결 주제, 근거 글, 문제를 붙인다. 코드로 판정할 수 있는 것만 본다."""
    profile = store.get_profile()
    topics = {t.topic_id: t for t in store.all_topics()}
    rows, notes, linked = [], [], {}
    for i, c in enumerate(candidates, 1):
        problems = []
        refs = evidence_refs(c)
        if any(sum(x is not None for x in (e.fact_id, e.photo_id, e.field)) != 1 for e in c.evidence):
            problems.append("근거 하나에 값이 0개거나 2개 이상")
        texts = store.evidence_texts([r for r in refs if r])
        if any(t is None for t in texts):
            problems.append("없는 근거를 가리킴")
        if c.kind in ("personal", "photo") and not any(texts):
            problems.append(f"{c.kind}인데 남아 있는 근거가 없음")
        if c.kind in ("discover", "general") and refs:
            problems.append(f"{c.kind}인데 근거를 적음")
        if c.kind == "discover" and c.discover_field not in profile.empty_fields:
            problems.append(f"discover인데 빈 칸이 아님({c.discover_field})")

        if c.linked_topic_id:
            t = topics.get(c.linked_topic_id)
            if t is None:
                topic_label = f"없는 주제 {c.linked_topic_id[:8]}"
                problems.append("없는 주제에 연결")
            else:
                topic_label = f"{t.title} (점수 {t.score:g}{', 제외' if t.excluded else ''})"
                if t.excluded:
                    problems.append("excluded 주제에 연결")
                if c.linked_topic_id in linked:
                    problems.append(f"{linked[c.linked_topic_id]}번 후보와 같은 주제")
                linked.setdefault(c.linked_topic_id, i)
        else:
            topic_label = f"새 주제: {c.new_topic_title}"
            if not (c.new_topic_title and c.new_topic_description):
                problems.append("새 주제인데 제목이나 설명이 비어 있음")
        rows.append({"no": i, "candidate": c.model_dump(), "topic": topic_label,
                     "evidence_texts": texts, "problems": problems})

    for t in topics.values():
        if t.score > 0 and not t.excluded and t.topic_id not in linked:
            detail = store.get_topic(t.topic_id)
            reason = " (근거가 모두 지워진 주제)" if detail.evidence_deleted else ""
            notes.append(f"점수가 양수인 주제 '{t.title}'를 이어 가는 후보가 없음{reason}")
    return rows, notes


def report(name: str, store: ProfileStore, config: ChatConfig, run, rows, notes) -> str:
    p = store.get_profile()
    gender = {"male": "남성", "female": "여성"}[p.gender]
    out = [f"# {name}", "", "## DB에 있던 것", ""]
    out.append(f"{p.age_band} {gender}. 이야기 {p.counts.life_facts}개, 사진 {p.counts.photos}장, "
               f"지난 주제 {p.counts.topics}개, 면회 {p.counts.visits}번.")
    out += ["", "초기 정보", ""]
    out += [f"- {FIELD_LABELS[f]}: {p.initial_details[f] or '(비어 있음)'}" for f in FIELD_LABELS]

    facts = store.list_life_facts(order="oldest", limit=30)
    if facts.total:
        out += ["", f"쌓아온 이야기 {facts.total}개" + (" 중 앞 10개" if facts.total > 10 else ""), ""]
        out += [f"- {f.title}: {_cut(f.content)}" for f in facts.facts[:10]]
    photos = store.list_photos()
    if photos.total:
        out += ["", "사진", ""] + [f"- {_cut(x.description)}" for x in photos.photos]

    topics = store.all_topics()
    if topics:
        out += ["", "지난 주제", "", "| 주제 | 제외 | 점수 | 면회에서 고른 횟수 | 마지막으로 고른 때 |", "| --- | --- | --- | --- | --- |"]
        for t in sorted(topics, key=lambda t: (t.excluded, -t.score)):
            last = "-" if t.last_selected_visits_ago is None else f"면회 {t.last_selected_visits_ago}번 전"
            out.append(f"| {_md_cell(t.title)} | {'제외' if t.excluded else ''} | {t.score:g} | {t.times_selected} | {last} |")

    out += ["", f"## 에이전트가 낸 후보 {len(rows)}개", "",
            "| # | 카드 제목 | 연결 | 종류 | 근거 | 다룰 장면 | 이유 |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        c = r["candidate"]
        ev = "; ".join(_cut(t, 40) if t else "(없음)" for t in r["evidence_texts"]) or "-"
        if c["kind"] == "discover":
            ev = f"빈 칸: {FIELD_LABELS.get(c['discover_field'], c['discover_field'])}"
        out.append(f"| {r['no']} | {_md_cell(c['card_title'])} | {_md_cell(r['topic'])} | {c['kind']} | "
                   f"{_md_cell(ev)} | {_md_cell(_cut(c['angle'], 50))} | {_md_cell(_cut(c['reason'], 50))} |")
    new = [r for r in rows if not r["candidate"]["linked_topic_id"]]
    if new:
        out += ["", "새 주제 설명", ""]
        out += [f"- {r['candidate']['new_topic_title']}: {r['candidate']['new_topic_description']}" for r in new]

    problems = [f"- {r['no']}번 {r['candidate']['card_title']}: {x}" for r in rows for x in r["problems"]]
    out += ["", "## 코드로 점검한 것", ""]
    out += problems + [f"- {n}" for n in notes] if problems or notes else ["걸린 것 없음."]

    out += ["", "## 실행 기록", "", f"{config.name}, {run.seconds}초."]
    if run.rejected:
        out.append(f"개수가 맞지 않아 다시 제출을 요청한 횟수: {len(run.rejected)}")
    out += ["", "도구 호출 순서", ""]
    for call in run.tool_calls:
        args = json.dumps(call.get("args", {}), ensure_ascii=False)
        out.append(f"- {call['turn']}턴 {call['call']}" + (f" {args}" if call.get("args") else ""))
    return "\n".join(out) + "\n"


def match_section(store: ProfileStore, rows: list[dict], outcome: MatchOutcome) -> list[str]:
    topics = {t.topic_id: t for t in store.all_topics()}
    agent_topics = {r["candidate"]["linked_topic_id"] or f"new:{r['candidate']['new_topic_title']}" for r in rows}
    judged = {m.topic_id or f"new:{m.new_key}" for m in outcome.kept}
    changed = [m for m in outcome.kept if m.topic_id != m.agent_topic_id]
    out = ["", "## 연결 판정 뒤", "",
           f"에이전트 기준 주제 {len(agent_topics)}개 → 판정 뒤 주제 {len(judged)}개. "
           f"남은 후보 {len(outcome.kept)}개, 빠진 후보 {len(outcome.dropped)}개, 에이전트와 연결이 달라진 후보 {len(changed)}개.",
           "", "| 주제 | 묶음 | 후보 |", "| --- | --- | --- |"]
    groups: dict[str, list] = {}
    for m in outcome.kept:
        groups.setdefault(m.topic_id or f"new:{m.new_key}", []).append(m)
    for key, ms in sorted(groups.items(), key=lambda kv: kv[1][0].no):
        if key.startswith("new:"):
            nt = outcome.new_topics[key[4:]]
            label, group = f"새 주제: {nt.title}", "-"
        else:
            label, group = topics[key].title, ("제외" if topics[key].excluded else f"점수 {topics[key].score:g}")
        names = ", ".join(f"{m.no}번 {m.candidate.card_title}" for m in ms)
        out.append(f"| {_md_cell(label)} | {group} | {_md_cell(names)} |")
    if changed:
        out += ["", "에이전트와 연결이 달라진 후보", ""]
        for m in changed:
            before = topics[m.agent_topic_id].title if m.agent_topic_id in topics else f"새 주제 '{m.candidate.new_topic_title}'"
            after = topics[m.topic_id].title if m.topic_id else f"새 주제 '{outcome.new_topics[m.new_key].title}'"
            out.append(f"- {m.no}번 {m.candidate.card_title}: {before} → {after}. {m.reason}")
    if outcome.dropped:
        out += ["", "빠진 후보", ""] + [f"- {d['no']}번 {d['card_title']}: {d['reason']}" for d in outcome.dropped]
    if outcome.new_topics:
        out += ["", "새 주제 설명", ""]
        out += [f"- {n.title}: {n.description}" for n in outcome.new_topics.values()]
    return out


def run_one(name: str, url: str, config: ChatConfig) -> Path:
    with psycopg.connect(url) as conn:
        profile_id = seed_scenario(conn, name)
    with psycopg.connect(url) as conn:
        store = ProfileStore(build_context(conn, profile_id), LATEST.decay)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    print(f"[{name}] 에이전트 실행 중…", flush=True)
    try:
        run = AgentSession(chat_model(config), store, LATEST).ask()
    except AgentFailed as error:
        path = HERE.parent / "runs" / f"{name}-{stamp}-failed.md"
        path.write_text(f"# {name}\n\n실패: {error}\n")
        print(f"[{name}] 실패: {error}")
        return path
    rows, notes = check(store, run.candidates)
    print(f"[{name}] 연결 판정 중…", flush=True)
    outcome = run_match(chat_model(config), store, run.candidates, LATEST.match_prompt())
    path = HERE.parent / "runs" / f"{name}-{stamp}.md"
    text = report(name, store, config, run, rows, notes)
    head, tail = text.split("\n## 코드로 점검한 것", 1)
    path.write_text(head + "\n".join(match_section(store, rows, outcome)) + "\n\n## 코드로 점검한 것" + tail)
    path.with_suffix(".json").write_text(json.dumps(
        {"scenario": name, "llm": config.name, "candidates": [r["candidate"] for r in rows],
         "checks": rows, "notes": notes, "tool_calls": run.tool_calls,
         "rejected": run.rejected, "seconds": run.seconds,
         "match": {"kept": [{"no": m.no, "topic_id": m.topic_id, "new_key": m.new_key, "reason": m.reason,
                             "agent_topic_id": m.agent_topic_id} for m in outcome.kept],
                   "dropped": outcome.dropped,
                   "new_topics": {k: v.model_dump() for k, v in outcome.new_topics.items()}}}, ensure_ascii=False, indent=1))
    print(f"[{name}] 후보 {len(rows)}개 → 판정 뒤 {len(outcome.kept)}개(빠짐 {len(outcome.dropped)}), "
          f"주제 {len({m.topic_id or m.new_key for m in outcome.kept})}개 → {path}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scenarios", nargs="*")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--effort", default="low")
    args = parser.parse_args()
    url = os.environ.get(DB_ENV)
    if not url:
        print(f"{DB_ENV}가 없습니다", file=sys.stderr)
        return 2
    names = scenario_names() if args.all else args.scenarios
    unknown = set(names) - set(scenario_names())
    if not names or unknown:
        print(f"시나리오: {', '.join(scenario_names())}", file=sys.stderr)
        return 2
    config = config_from_env(effort=args.effort or None)
    for name in names:
        run_one(name, url, config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
