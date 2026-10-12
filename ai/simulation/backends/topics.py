"""주제판(PR #84 스키마) 백엔드 역할. 추천은 card_generation.generate를 부르고, 저장은 PR #84 테이블에 한다.

  카드 받기  profile_topics(새 주제), card_sets, conversation_cards
  반영      card_sets.session_id, conversation_cards.selected·review_reaction·report_summary,
            topic_proposals → 보호자 확인 → topic_feedback
조정은 카드에 붙은 주제 하나에 붙는다. 범위를 고르는 단계가 없다.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

import psycopg

from card_generation._steps.research.store import ProfileStore
from card_generation._versions import LATEST
from card_generation.contract import CardGenerationError, GenerationRequest
from card_generation.generate import generate_cards
from common.llm import ChatConfig

from . import OWN, Backend
from .context import build_context

NAME = "topics"


def profile_store(url: str, pid: str) -> ProfileStore:
    """화면용 조회. 카드 생성과 같은 context를 DB에서 조립해 읽는다."""
    with psycopg.connect(url) as ro:
        return ProfileStore(build_context(ro, pid), LATEST.decay)


def topic_group(t) -> str:
    """기록 화면에 보일 주제 상태. excluded가 아니면 active."""
    return "excluded" if t.excluded else "active"


def evidence_columns(refs: list[dict[str, str]]) -> tuple[str, list[dict[str, str]]]:
    """conversation_cards의 (evidence_source, evidence). 카드 생성은 세부 정보 근거를 profile로 내지만(2026-10-06 결정),
    지금 스키마 CHECK는 life_fact, photo, none만 받는다. 스키마를 고치기 전까지는 none과 빈 목록으로 쓰고,
    넣지 못한 근거는 카드 기록(evidence_lost)에 남긴다."""
    kept = [r for r in refs if "factId" in r or "photoId" in r]
    if not kept:
        return "none", []
    return ("life_fact" if "factId" in kept[0] else "photo"), kept


class TopicsBackend(Backend):
    name = NAME
    label = "주제판 (PR #84 스키마)"
    recommend_errors = (CardGenerationError,)
    snapshot_tables = [
        ("users", ("user_id",), "user_id = (SELECT user_id FROM profiles WHERE profile_id = %(pid)s)"),
        ("profiles", ("profile_id",), OWN),
        ("photos", ("photo_id",), OWN),
        ("visit_sessions", ("session_id",), OWN),
        ("speech_analysis_jobs", ("analysis_id",),
         "session_id IN (SELECT session_id FROM visit_sessions WHERE profile_id = %(pid)s)"),
        ("card_sets", ("set_id",), OWN),
        ("conversation_cards", ("card_id",), OWN),
        ("profile_topics", ("topic_id",), OWN),
        ("topic_proposals", ("proposal_id",), OWN),
        ("topic_feedback", ("feedback_id",), OWN),
        ("life_fact_proposals", ("proposal_id",), OWN),
        ("life_facts", ("fact_id",), OWN),
    ]
    prompt_files = {
        "추천 ① 조사 에이전트": "card_generation/_versions/v1/prompts/agent.md",
        "추천 ② 연결 판정": "card_generation/_versions/v1/prompts/match.md",
        "추천 ④ 문안 작성": "card_generation/_versions/v1/prompts/writing_topics.md",
        "추천 ①② 같은 이야기 기준": "card_generation/_versions/v1/prompts/same_story.md",
    }

    def store(self, conn: psycopg.Connection, pid: str) -> ProfileStore:
        return ProfileStore(build_context(conn, pid), LATEST.decay)

    # 1 카드 받기: 실제 backend worker와 같은 경로. DB에서 context 조립 → generate_cards → 결과 저장
    def recommend(self, url: str, pid: str, config: ChatConfig, model) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        with psycopg.connect(url) as ro:
            context = build_context(ro, pid)
        store = ProfileStore(context, LATEST.decay)   # 화면에 보여 줄 '추천 전' 주제 상태와 근거 글. 생성에는 쓰지 않는다
        before = {t.topic_id: t for t in store.all_topics()}
        request = GenerationRequest(model=config.model, prompt_version=LATEST.number, context=context)
        result = generate_cards(request, api_key=config.api_key)
        topics = {t.topic_id: t for t in context.topics}
        cards = []
        with psycopg.connect(url) as rw, rw.transaction():
            self.set_id = rw.execute(
                "INSERT INTO card_sets (profile_id, status, model, prompt_version, generation_log) "
                "VALUES (%s, 'completed', %s, %s, %s) RETURNING set_id::text",
                (pid, result.model, str(result.prompt_version),
                 json.dumps({"input": context.model_dump(mode="json", by_alias=True), "log": result.log,
                             "cards": [{"position": c.position, **c.extra.model_dump(by_alias=True)} for c in result.cards]},
                            ensure_ascii=False, default=str))).fetchone()[0]
            for c in result.cards:
                if c.topic.topic_id:
                    tid, title, description = c.topic.topic_id, topics[c.topic.topic_id].title, topics[c.topic.topic_id].description
                else:
                    title, description = c.topic.title, c.topic.description
                    tid = rw.execute("INSERT INTO profile_topics (profile_id, title, description, evidence) VALUES (%s, %s, %s, %s) "
                                     "RETURNING topic_id::text", (pid, title, description, json.dumps(c.topic.evidence or []))).fetchone()[0]
                source, stored = evidence_columns(c.evidence)
                card_id = rw.execute(
                    "INSERT INTO conversation_cards (set_id, profile_id, topic_id, card_title, position, description, "
                    "primary_question, follow_up_questions, evidence_source, evidence) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING card_id::text",
                    (self.set_id, pid, tid, c.card_title, c.position, c.description, c.primary_question,
                     c.follow_up_questions, source, json.dumps(stored))).fetchone()[0]
                cards.append({"position": c.position, "card_title": c.card_title, "angle": c.extra.angle, "kind": c.extra.kind,
                              "bucket": c.extra.bucket, "pick_reason": c.extra.pick_reason, "agent_reason": c.extra.agent_reason,
                              "evidence_texts": [t for t in store.evidence_texts(c.evidence) if t], "topic_id": tid,
                              "topic": {"title": title, "description": description,
                                        "group": topic_group(before[tid]) if tid in before else "new", "new": tid not in before,
                                        "match_reason": c.extra.match_reason},
                              "card_id": card_id, "evidence_source": source, "evidence": stored,
                              "evidence_lost": [r for r in c.evidence if r not in stored],
                              "description": c.description, "primary_question": c.primary_question,
                              "follow_up_questions": c.follow_up_questions})
        record = {"candidates": result.log["candidates"], "tool_calls": result.log["toolCalls"],
                  "rejected_submissions": result.log["rejectedSubmissions"], "refills": result.log["refills"],
                  "dropped": result.log["dropped"], "new_topics": sum(1 for c in result.cards if not c.topic.topic_id),
                  "writing_first_problems": result.log["writingFirstProblems"], "seconds": result.log["seconds"]}
        return cards, record

    def card_names(self, card: dict[str, Any]) -> list[str]:
        return [card["topic"]["title"]]

    def output_card(self, card: dict[str, Any]) -> dict[str, Any]:
        return {"elements": [{"kind": "topic", "name": card["topic"]["title"] + (" (새 주제)" if card["topic"]["new"] else "")}]}

    # 9 반영
    def attach_cards(self, rw: psycopg.Connection, session: Any, cards: list[dict[str, Any]], summaries: dict[int, str]) -> None:
        rw.execute("UPDATE card_sets SET session_id = %s WHERE set_id = %s", (session, self.set_id))
        for c in cards:
            # report_summary는 평가가 positive·neutral·negative인 카드에만 넣을 수 있다(스키마 CHECK)
            summary = summaries.get(c["position"]) if c["review"] in ("positive", "neutral", "negative") else None
            c["report_summary"] = summary
            rw.execute("UPDATE conversation_cards SET selected = %s, review_reaction = %s, report_summary = %s "
                       "WHERE card_id = %s", (c["selected"], c["review"], summary or None, c["card_id"]))

    def apply_adjustment(self, rw: psycopg.Connection, pid: str, session: Any, decided_at: datetime,
                         card: dict[str, Any], t: dict[str, Any], d) -> dict[str, Any] | None:
        """보호자가 ×로 뺀 조정도 topic_proposals에는 남기고(settled), topic_feedback만 넣지 않는다."""
        proposal = rw.execute(
            "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id, suggested_action, reason, status) "
            "VALUES (%s, %s, %s, %s, %s, %s, 'settled') RETURNING proposal_id",
            (session, pid, card["card_id"], card["topic_id"], t["suggested_action"], t["reason"])).fetchone()[0]
        if d is not None and not d.keep:
            return None
        action = d.action if d else t["suggested_action"]
        rw.execute("INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action, decided_at) "
                   "VALUES (%s, %s, %s, %s, %s)", (pid, card["topic_id"], proposal, action, decided_at))
        if d and (d.new_name or d.new_description):
            rw.execute("UPDATE profile_topics SET title = COALESCE(%s, title), description = COALESCE(%s, description) "
                       "WHERE topic_id = %s", (d.new_name, d.new_description, card["topic_id"]))
        return {"card_title": t["card_title"], "action": action, "kind": "topic",
                "name": d.new_name if d and d.new_name else t["topic_name"],
                "changed_action": bool(d and action != t["suggested_action"])}

    def strip(self, card: dict[str, Any]) -> dict[str, Any]:
        return {k: v for k, v in card.items() if k not in ("card_id", "topic_id")}

    # 상태
    def state(self, url: str, pid: str) -> dict[str, Any]:
        store = profile_store(url, pid)
        topics = store.all_topics()
        facts = store.list_life_facts(order="oldest", limit=30).facts
        return {"life_facts": [{"title": f.title, "content": f.content, "from_visit": f.from_visit} for f in facts],
                "topics": [{"title": t.title, "description": t.description, "group": topic_group(t), "score": t.score,
                            "times_offered": t.times_offered, "times_selected": t.times_selected} for t in topics]}

    def size_units(self, run: dict[str, Any]) -> list[dict[str, Any]]:
        """주제 크기 평가에 넣을 단위. 주제판은 profile_topics 전체."""
        tables = run["db_snapshots"][-1]["tables"]
        sets = {r["set_id"]: i for i, r in enumerate(tables["card_sets"]["rows"], 1)}
        visits: dict[str, list[int]] = {}
        for c in tables["conversation_cards"]["rows"]:
            visits.setdefault(c["topic_id"], []).append(sets.get(c["set_id"]))
        actions: dict[str, list[str]] = {}
        for f in tables["topic_feedback"]["rows"]:
            actions.setdefault(f["topic_id"], []).append(f["action"])
        return [{"title": t["title"], "description": t["description"],
                 "visits": sorted(v for v in visits.get(t["topic_id"], []) if v), "actions": actions.get(t["topic_id"], [])}
                for t in tables["profile_topics"]["rows"]]

