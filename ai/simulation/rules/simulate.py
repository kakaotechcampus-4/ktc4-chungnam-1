"""회차를 이어 가는 시뮬레이션. 추천 → 가상 보호자의 선택과 결정 → 다음 회차 추천을 반복한다.

    uv run python -m simulation.rules.simulate --rounds 5
    uv run python -m simulation.rules.simulate --persona simulation/rules/personas/sewing-seaside.json --rounds 5 --seed 7

가상 보호자는 페르소나 파일의 숨은 취향(likes, dislikes, taboo)으로 규칙대로 움직인다. 시스템은 이 취향을 볼 수 없다.
  taboo에 걸린 카드     고르지 않고 '추천하지 않기'
  dislikes에 걸린 카드  고르지 않고 '덜 자주'
  likes에 걸린 카드     고르고 반응은 좋았어요. more_probability 확률로 '더 자주'
  나머지               남은 자리를 무작위로 채우고 반응도 무작위
카드 글(card_title, angle)에 낱말이 들어 있는지로 판단한다. 질문 문장 작성 단계가 아직 없어서
카드의 질문은 자리표시 문장으로 넣는다. 결과는 runs/sim-*.md와 .json에 남는다(커밋하지 않음).
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import psycopg

from card_generation._steps.research.agent import AgentFailed
from card_generation._steps.research.candidates import evidence_refs
from card_generation._steps.research.store import ProfileStore
from card_generation._steps.select import SelectionFailed
from card_generation._versions import LATEST
from card_generation.generate import Recommendation, RecommendFailed, recommend
from common.llm import ChatConfig, chat_model
from simulation.backends.context import build_context
from simulation.llm_env import config_from_env
from simulation.rules.seed_mock import HERE as SCENARIOS
from simulation.rules.seed_mock import seed

HERE = Path(__file__).resolve().parent
DB_ENV = "TOPIC_REC_DATABASE_URL"


def save_new_topics(conn: psycopg.Connection, profile_id: str, rec: Recommendation) -> dict[str, str]:
    """고른 카드 중 새 주제를 profile_topics에 넣고 new_key → topic_id를 돌려준다. 고르지 않은 새 주제는 넣지 않는다."""
    created: dict[str, str] = {}
    for p in rec.picked:
        key = p.matched.new_key
        if not key or key in created:
            continue
        nt = rec.match.new_topics[key]
        row = conn.execute(
            "INSERT INTO profile_topics (profile_id, title, description, evidence) VALUES (%s, %s, %s, %s) "
            "RETURNING topic_id::text", (profile_id, nt.title, nt.description, json.dumps(evidence_refs(p.matched.candidate)))).fetchone()
        created[key] = row[0]
    return created


def _hits(text: str, words: list[str]) -> list[str]:
    return [w for w in words if w in text]


class Guardian:
    def __init__(self, persona: dict[str, Any], rng: random.Random) -> None:
        self.p = persona
        self.rng = rng

    def visit(self, cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """카드마다 selected, reaction, action(more/less/exclude/None), why를 정한다."""
        out = []
        for c in cards:
            text = f"{c['card_title']} {c['angle']}"  # 보호자가 카드에서 보는 글. 두 방식을 같은 조건으로 비교한다
            taboo, dislike, like = (_hits(text, self.p[k]) for k in ("taboo", "dislikes", "likes"))
            if taboo:
                out.append({**c, "selected": False, "reaction": None, "action": "exclude", "why": f"막음: {taboo}"})
            elif dislike:
                out.append({**c, "selected": False, "reaction": None, "action": "less", "why": f"싫어함: {dislike}"})
            elif like:
                more = self.rng.random() < self.p["more_probability"]
                out.append({**c, "selected": True, "reaction": "positive", "action": "more" if more else None,
                            "why": f"좋아함: {like}"})
            else:
                out.append({**c, "selected": None, "reaction": None, "action": None, "why": ""})
        limit = self.p["cards_selected_per_visit"]
        chosen = sum(1 for c in out if c["selected"])
        rest = [c for c in out if c["selected"] is None]
        self.rng.shuffle(rest)
        for c in rest:
            c["selected"] = chosen < limit
            if c["selected"]:
                chosen += 1
                c["reaction"] = self.rng.choice(["positive", "neutral", "neutral", "negative", "notUsed"])
        return out


def write_cards(conn: psycopg.Connection, profile_id: str, rec: Recommendation, created: dict[str, str],
                config: ChatConfig) -> tuple[str, list[dict[str, Any]]]:
    """backend 역할: 카드 묶음과 카드 12장을 쓴다. 질문 문장은 자리표시다."""
    set_id = conn.execute(
        "INSERT INTO card_sets (profile_id, status, model, prompt_version, generation_log) "
        "VALUES (%s, 'completed', %s, 'sim', %s) RETURNING set_id::text",
        (profile_id, config.name, json.dumps({"input": {"simulation": True}}))).fetchone()[0]
    cards = []
    for pos, p in enumerate(rec.picked, 1):
        m = p.matched
        topic_id = m.topic_id or created[m.new_key]
        refs = evidence_refs(p.matched.candidate)
        source = "none" if not refs else ("photo" if "photoId" in refs[0] else "life_fact")
        card_id = conn.execute(
            "INSERT INTO conversation_cards (set_id, profile_id, topic_id, card_title, position, description, "
            "primary_question, follow_up_questions, evidence_source, evidence) "
            "VALUES (%s, %s, %s, %s, %s, '(시뮬레이션: 문안 작성 단계 없음)', %s, ARRAY['그때는 어땠어요?'], %s, %s) "
            "RETURNING card_id::text",
            (set_id, profile_id, topic_id, m.candidate.card_title, pos, f"{m.candidate.card_title} 이야기를 들려주실 수 있어요?",
             source, json.dumps(refs))).fetchone()[0]
        title = conn.execute("SELECT title FROM profile_topics WHERE topic_id = %s", (topic_id,)).fetchone()[0]
        cards.append({"card_id": card_id, "topic_id": topic_id, "topic_title": title, "card_title": m.candidate.card_title,
                      "angle": m.candidate.angle, "kind": m.candidate.kind, "bucket": p.bucket,
                      "new_topic": m.new_key is not None})
    return set_id, cards


def record_visit(conn: psycopg.Connection, profile_id: str, set_id: str, started: datetime,
                 decided: list[dict[str, Any]], facts: list[dict[str, str]]) -> None:
    session = conn.execute("INSERT INTO visit_sessions (profile_id, started_at) VALUES (%s, %s) RETURNING session_id",
                           (profile_id, started)).fetchone()[0]
    conn.execute("UPDATE card_sets SET session_id = %s WHERE set_id = %s", (session, set_id))
    for c in decided:
        conn.execute("UPDATE conversation_cards SET selected = %s, review_reaction = %s WHERE card_id = %s",
                     (c["selected"], c["reaction"] if c["selected"] else None, c["card_id"]))
        if c["action"]:
            proposal = conn.execute(
                "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id, suggested_action, reason, status) "
                "VALUES (%s, %s, %s, %s, %s, '시뮬레이션', 'settled') RETURNING proposal_id",
                (session, profile_id, c["card_id"], c["topic_id"], c["action"])).fetchone()[0]
            conn.execute("INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action, decided_at) "
                         "VALUES (%s, %s, %s, %s, %s)",
                         (profile_id, c["topic_id"], proposal, c["action"], started + timedelta(hours=3)))
    for f in facts:
        proposal = conn.execute(
            "INSERT INTO life_fact_proposals (session_id, profile_id, title, content, reason, status) "
            "VALUES (%s, %s, %s, %s, '시뮬레이션', 'settled') RETURNING proposal_id",
            (session, profile_id, f["title"], f["content"])).fetchone()[0]
        conn.execute("INSERT INTO life_facts (profile_id, title, content, source_proposal_id, created_at) "
                     "VALUES (%s, %s, %s, %s, %s)", (profile_id, f["title"], f["content"], proposal,
                                                     started + timedelta(hours=3)))


def summarize(rounds: list[dict[str, Any]], persona: dict[str, Any]) -> list[str]:
    """회차 전체를 보고 코드로 판정할 수 있는 것만 적는다."""
    lines = []
    excluded_from: int | None = None
    for r in rounds:
        if excluded_from is not None:
            leaks = [c for c in r["cards"] if _hits(f"{c['card_title']} {c['angle']}", persona["taboo"])]
            for c in leaks:
                lines.append(f"- {r['round']}회차: 막은 이야기와 겹치는 카드 '{c['card_title']}'(주제 '{c['topic_title']}', "
                             f"{'새 주제' if c['new_topic'] else '기존 주제'})가 다시 나옴")
        if excluded_from is None and any(c["action"] == "exclude" for c in r["decided"]):
            excluded_from = r["round"]
    less_at: dict[str, int] = {}
    for r in rounds:
        shown = {c["topic_id"] for c in r["cards"]}
        for tid, at in list(less_at.items()):
            if tid in shown:
                title = next(c["topic_title"] for c in r["cards"] if c["topic_id"] == tid)
                lines.append(f"- '덜 자주' 주제 '{title}': {at}회차에 정함 → {r['round']}회차에 다시 나옴(면회 {r['round'] - at - 1}번 쉼)")
                del less_at[tid]
        for c in r["decided"]:
            if c["action"] == "less":
                less_at.setdefault(c["topic_id"], r["round"])
    more_at: dict[str, tuple[int, str]] = {}
    for r in rounds:
        shown = {c["topic_id"] for c in r["cards"]}
        for tid, (at, title) in list(more_at.items()):
            status = "다시 나옴" if tid in shown else "나오지 않음"
            lines.append(f"- '더 자주' 주제 '{title}'({at}회차에 정함): {r['round']}회차에 {status}")
            del more_at[tid]
        for c in r["decided"]:
            if c["action"] == "more":
                more_at[c["topic_id"]] = (r["round"], c["topic_title"])
    return lines or ["- 판정할 사건이 없음"]


def report(persona_path: Path, seed_value: int, rounds: list[dict[str, Any]], persona: dict[str, Any],
           failure: str | None) -> str:
    out = [f"# 회차 시뮬레이션: {persona_path.stem}", "",
           f"시작 상태 `{persona['start']}`, 회차 {len(rounds)}번, 난수 시드 {seed_value}.", "",
           "보호자의 숨은 취향(시스템은 모름)", "",
           f"- 좋아함: {', '.join(persona['likes'])}", f"- 싫어함('덜 자주'): {', '.join(persona['dislikes'])}",
           f"- 막음('추천하지 않기'): {', '.join(persona['taboo'])}", "",
           "## 회차를 거치며 본 것", ""] + summarize(rounds, persona)
    out += ["", "| 회차 | 주제 수(전체) | 새로 만든 주제 | 이어 가기 | 새 이야기 | 다시 꺼내기 | 시간(초) |",
            "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rounds:
        b = [c["bucket"] for c in r["cards"]]
        out.append(f"| {r['round']} | {r['topics_after']} | {sum(c['new_topic'] for c in r['cards'])} | "
                   f"{b.count('continue')} | {b.count('new')} | {b.count('revisit')} | {r['seconds']} |")
    for r in rounds:
        out += ["", f"## {r['round']}회차", "", "| # | 카드 | 주제 | 칸 | 보호자 | 결정 |", "| --- | --- | --- | --- | --- | --- |"]
        for i, c in enumerate(r["decided"], 1):
            who = ("고름" + (f"({c['reaction']})" if c["reaction"] else "")) if c["selected"] else "안 고름"
            topic = c["topic_title"] + (" (새)" if c["new_topic"] else "")
            out.append(f"| {i} | {c['card_title']} | {topic} | {c['bucket']} | {who} | {c['action'] or '-'} {c['why']} |")
        if r["facts"]:
            out += ["", "이 면회에서 새로 알게 된 이야기: " + ", ".join(f"{f['title']}({f['content']})" for f in r["facts"])]
        if r["rejected"]:
            out += ["", f"에이전트 제출이 검증에서 {len(r['rejected'])}번 거부됨"]
        if r.get("refills"):
            out += ["", f"판정 뒤 주제가 모자라 에이전트에게 {len(r['refills'])}번 다시 찾게 함", ""]
            out += ["> " + line for line in r["refills"][0].splitlines()]
    if failure:
        out += ["", "## 중단", "", failure]
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--persona", default=str(SCENARIOS / "personas/sewing-seaside.json"))
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    url = os.environ.get(DB_ENV)
    if not url:
        print(f"{DB_ENV}가 없습니다", file=sys.stderr)
        return 2
    persona_path = Path(args.persona)
    persona = json.loads(persona_path.read_text())
    rng = random.Random(args.seed)
    guardian = Guardian(persona, rng)
    config = config_from_env()
    name = f"sim-{persona_path.stem}-{args.seed}"
    with psycopg.connect(url) as conn:
        profile_id = seed(conn, json.loads((SCENARIOS / f"{persona['start']}.json").read_text()), name)
    first = datetime.fromisoformat(persona["first_visit_at"])
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    rounds: list[dict[str, Any]] = []
    failure = None
    for n in range(1, args.rounds + 1):
        print(f"[{n}회차] 추천 중…", flush=True)
        started = datetime.now()
        with psycopg.connect(url) as ro:
            store = ProfileStore(build_context(ro, profile_id), LATEST.decay)
            try:
                rec = recommend(store, chat_model(config), LATEST)
            except (RecommendFailed, AgentFailed, SelectionFailed, RuntimeError) as error:
                failure = f"{n}회차 추천 실패: {error}"
                print(failure)
                break
        with psycopg.connect(url) as rw, rw.transaction():
            created = save_new_topics(rw, profile_id, rec)
            set_id, cards = write_cards(rw, profile_id, rec, created, config)
            decided = guardian.visit(cards)
            facts = [f for f in persona["fact_pool"] if f["round"] == n]
            record_visit(rw, profile_id, set_id, first + timedelta(days=persona["visit_every_days"] * (n - 1)),
                         decided, facts)
            topics_after = rw.execute("SELECT count(*) FROM profile_topics WHERE profile_id = %s",
                                      (profile_id,)).fetchone()[0]
        rounds.append({"round": n, "cards": cards, "decided": decided, "facts": facts, "topics_after": topics_after,
                       "refills": rec.refills,
                       "rejected": rec.agent.rejected, "seconds": round((datetime.now() - started).total_seconds()),
                       "dropped_in_match": rec.match.dropped})
        actions = [c["action"] for c in decided if c["action"]]
        print(f"[{n}회차] 카드 12장, 새 주제 {len(created)}개, 다시 찾기 {len(rec.refills)}번, 결정 {actions}", flush=True)
        path = HERE.parent / "runs" / f"{name}-{stamp}.md"
        path.write_text(report(persona_path, args.seed, rounds, persona, failure))
    path = HERE.parent / "runs" / f"{name}-{stamp}.md"
    path.write_text(report(persona_path, args.seed, rounds, persona, failure))
    path.with_suffix(".json").write_text(json.dumps({"persona": persona, "rounds": rounds, "failure": failure},
                                                    ensure_ascii=False, indent=1, default=str))
    print(f"결과: {path}")
    return 0 if failure is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
