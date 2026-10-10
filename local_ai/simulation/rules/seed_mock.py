"""simulation/rules/*.json(이전 카드 MVP의 합성 mock, 형식 v2)을 PR #84 스키마에 넣는다.

시나리오 하나가 계정 하나, 프로필 하나가 된다. ID는 시나리오 이름에서 uuid5로 만들기 때문에
같은 시나리오를 다시 넣으면 그 계정을 지우고 새로 넣는다.

mock에서 DB로 옮기는 방식
- topicKey가 처음 나온 카드의 제목과 근거로 profile_topics 한 행을 만든다. topicPreferences에 설명이 있으면 그걸 쓴다.
- 면회마다 visit_sessions, card_sets, conversation_cards를 만든다. inVisit이면 selected, reviewOutcome은 review_reaction.
- topicPreferences는 topic_proposals(settled)와 topic_feedback으로 넣는다. intent rest는 less로 바꾼다.
- origin이 visit인 이야기는 첫 면회의 life_fact_proposals를 승인해 만든 것으로 넣는다.
- f-deleted처럼 없는 이야기를 가리키는 근거는 그대로 둔다(지워진 근거).
"""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

import psycopg

NAMESPACE = uuid.UUID("6f1d3a52-6b0e-4c1e-9a1f-2a8c3b5d7e90")
HERE = Path(__file__).resolve().parent


def _birth(age_band: str) -> date:
    today = date.today()
    return today.replace(year=today.year - int(age_band.rstrip("s")) - 5)


def uid(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, "/".join(parts)))


def _evidence(prefix: str, refs: list[dict[str, Any]]) -> list[dict[str, str]]:
    out = []
    for r in refs or []:
        if r.get("field"):
            out.append({"profileField": r["field"]})
        elif r.get("factId"):
            out.append({"factId": uid(prefix, "fact", r["factId"])})
        elif r.get("photoId"):
            out.append({"photoId": uid(prefix, "photo", r["photoId"])})
    return out


def _source(evidence: list[dict[str, str]]) -> str:
    if not evidence:
        return "none"
    return "photo" if "photoId" in evidence[0] else "life_fact"


def seed(conn: psycopg.Connection, mock: dict[str, Any], name: str) -> str:
    p = name
    user_id, profile_id = uid(p, "user"), uid(p, "profile")
    descriptions = {x["topicKey"]: x["description"] for x in mock.get("topicPreferences", []) if x.get("description")}
    with conn.transaction():
        conn.execute("DELETE FROM users WHERE user_id = %s", (user_id,))
        conn.execute("INSERT INTO users (user_id, google_sub) VALUES (%s, %s)", (user_id, f"mock-{p}"))
        prof, d = mock["profile"], mock["initialDetails"]
        conn.execute(
            "INSERT INTO profiles (profile_id, user_id, name, gender, birth_date, condition_stage, "
            "occupation, hometown, hobby, family) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (profile_id, user_id, f"합성-{p}", prof["gender"], _birth(prof["ageBand"]), prof["conditionStage"],
             d.get("occupation"), d.get("hometown"), d.get("hobby"), d.get("family")))
        for i, ph in enumerate(mock["photos"]):
            conn.execute(
                "INSERT INTO photos (photo_id, profile_id, s3_object_key, description, analysis_status, model, "
                "prompt_version, created_at) VALUES (%s, %s, %s, %s, 'completed', 'mock-vlm', 'mock', %s)",
                (uid(p, "photo", ph["photoId"]), profile_id, f"mock/{p}/{ph['photoId']}.jpg", ph["description"],
                 datetime(2026, 1, 1) + timedelta(minutes=i)))

        sessions: list[tuple[str, datetime]] = []
        topics: dict[str, str] = {}
        cards: dict[tuple[int, str], str] = {}  # (면회 순서, topicKey) → card_id
        for v in sorted(mock["visits"], key=lambda v: v["visitIndex"]):
            started = datetime.fromisoformat(v["startedAt"])
            sid = uid(p, "session", str(v["visitIndex"]))
            sessions.append((sid, started))
            conn.execute("INSERT INTO visit_sessions (session_id, profile_id, started_at) VALUES (%s, %s, %s)",
                         (sid, profile_id, started))
            set_id = uid(p, "set", str(v["visitIndex"]))
            conn.execute(
                "INSERT INTO card_sets (set_id, profile_id, session_id, status, model, prompt_version, generation_log, "
                "created_at) VALUES (%s, %s, %s, 'completed', 'mock', 'mock', %s, %s)",
                (set_id, profile_id, sid, json.dumps({"input": {}, "mock": True}), started - timedelta(hours=1)))
            for c in v["cards"]:
                key = c["topicKey"]
                ev = _evidence(p, c.get("evidence", []))
                if key not in topics:
                    topics[key] = uid(p, "topic", key)
                    conn.execute(
                        "INSERT INTO profile_topics (topic_id, profile_id, title, description, evidence, created_at) "
                        "VALUES (%s, %s, %s, %s, %s, %s)",
                        (topics[key], profile_id, c["topicTitle"],
                         descriptions.get(key, f"{c['topicTitle']}을(를) 여쭤보는 주제예요."),
                         json.dumps(ev), started - timedelta(hours=1)))
                if (v["visitIndex"], key) in cards:
                    continue  # 한 묶음에 같은 주제는 한 장
                card_id = uid(p, "card", str(v["visitIndex"]), key)
                cards[(v["visitIndex"], key)] = card_id
                selected = bool(c.get("inVisit"))
                conn.execute(
                    "INSERT INTO conversation_cards (card_id, set_id, profile_id, topic_id, card_title, position, "
                    "description, primary_question, follow_up_questions, evidence_source, evidence, selected, "
                    "review_reaction) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                    (card_id, set_id, profile_id, topics[key], c["topicTitle"], c["position"],
                     f"{c['topicTitle']}을(를) 여쭤보는 주제예요.", f"{c['topicTitle']} 이야기를 들려주실 수 있어요?",
                     ["그때는 어땠어요?"], _source(ev), json.dumps(ev), selected,
                     c.get("reviewOutcome") if selected else None))

        first_session = sessions[0][0] if sessions else None
        for i, f in enumerate(mock["lifeFacts"]):
            source = None
            if f.get("origin") == "visit" and first_session:
                source = uid(p, "lfp", f["factId"])
                conn.execute(
                    "INSERT INTO life_fact_proposals (proposal_id, session_id, profile_id, title, content, reason, status) "
                    "VALUES (%s, %s, %s, %s, %s, '합성 제안', 'settled')",
                    (source, first_session, profile_id, f["title"], f["content"]))
            conn.execute("INSERT INTO life_facts (fact_id, profile_id, title, content, source_proposal_id, created_at) "
                         "VALUES (%s, %s, %s, %s, %s, %s)",
                         (uid(p, "fact", f["factId"]), profile_id, f["title"], f["content"], source,
                          datetime(2026, 1, 1) + timedelta(minutes=i)))

        for pref in mock.get("topicPreferences", []):
            key, decided = pref["topicKey"], datetime.fromisoformat(pref["decidedAt"])
            visits = [i + 1 for i, (_, started) in enumerate(sessions) if started <= decided]
            card_visit = next((i for i in reversed(visits) if (i, key) in cards), None)
            card_visit = card_visit or next((i for (i, k) in sorted(cards) if k == key), None)
            if card_visit is None:
                raise ValueError(f"주제 제안을 붙일 카드가 없음: {key}")
            action = {"more": "more", "rest": "less", "exclude": "exclude"}[pref["intent"]]
            proposal_id = uid(p, "tp", key)
            conn.execute(
                "INSERT INTO topic_proposals (proposal_id, session_id, profile_id, card_id, topic_id, "
                "suggested_action, reason, status) VALUES (%s, %s, %s, %s, %s, %s, '합성 제안', 'settled')",
                (proposal_id, sessions[card_visit - 1][0], profile_id, cards[(card_visit, key)], topics[key], action))
            conn.execute("INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action, decided_at) "
                         "VALUES (%s, %s, %s, %s, %s)", (profile_id, topics[key], proposal_id, action, decided))
    return profile_id


def seed_scenario(conn: psycopg.Connection, name: str) -> str:
    return seed(conn, json.loads((HERE / f"{name}.json").read_text()), name)


def scenario_names() -> list[str]:
    return sorted(p.stem for p in HERE.glob("*.json"))
