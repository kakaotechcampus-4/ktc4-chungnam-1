"""backend 역할: PR #84 테이블에서 카드 생성 context를 조립한다. 실제 backend worker가 할 일의 동기판 예시다.

넘기는 것과 거르는 조건은 card_generation/contract.py 설명과 같다.
  면회      evaluated_at이 있는 회차만, 시간순. 그 회차에 연결된 카드 묶음(card_sets.session_id)을 setId로 붙인다
  지난 카드 그 면회 묶음들의 카드만
  사진      프로필 사진(session_id 없음) 중 분석 완료
  결정      topic_feedback(승인된 결정)만. topic_proposals는 넘기지 않는다
"""

from __future__ import annotations

from typing import Any

import psycopg
from psycopg.rows import dict_row

from card_generation.contract import CardContext


def build_context(conn: psycopg.Connection, profile_id: str) -> CardContext:
    conn.row_factory = dict_row

    def rows(sql: str) -> list[dict[str, Any]]:
        return conn.execute(sql, {"pid": profile_id}).fetchall()

    profile = rows("SELECT (date_part('year', age(current_date, birth_date))::int / 10 * 10) AS decade, "
                   "occupation, hometown, hobby, family FROM profiles WHERE profile_id = %(pid)s")[0]
    facts = rows("SELECT fact_id::text, title, content, created_at, source_proposal_id IS NOT NULL AS from_visit "
                 "FROM life_facts WHERE profile_id = %(pid)s ORDER BY created_at, fact_id")
    photos = rows("SELECT photo_id::text, description FROM photos WHERE profile_id = %(pid)s AND session_id IS NULL "
                  "AND analysis_status = 'completed' ORDER BY created_at, photo_id")
    topics = rows("SELECT topic_id::text, title, description, evidence, created_at FROM profile_topics "
                  "WHERE profile_id = %(pid)s ORDER BY created_at, topic_id")
    feedback = rows("SELECT topic_id::text, action, decided_at FROM topic_feedback WHERE profile_id = %(pid)s "
                    "ORDER BY decided_at, feedback_id")
    visits = rows("SELECT v.session_id::text, v.started_at, s.set_id::text FROM visit_sessions v "
                  "LEFT JOIN card_sets s ON s.session_id = v.session_id "
                  "WHERE v.profile_id = %(pid)s AND v.evaluated_at IS NOT NULL ORDER BY v.started_at, v.session_id")
    cards = rows("SELECT c.card_id::text, c.set_id::text, c.topic_id::text, c.position, c.card_title, c.primary_question, "
                 "c.evidence, c.selected, c.review_reaction FROM conversation_cards c "
                 "JOIN card_sets s ON s.set_id = c.set_id JOIN visit_sessions v ON v.session_id = s.session_id "
                 "WHERE c.profile_id = %(pid)s AND s.status = 'completed' AND v.evaluated_at IS NOT NULL "
                 "ORDER BY v.started_at, c.position")
    by_topic: dict[str, list[dict[str, Any]]] = {}
    for f in feedback:
        by_topic.setdefault(f["topic_id"], []).append({"action": f["action"], "decidedAt": f["decided_at"]})
    return CardContext.model_validate({
        "ageRange": f"{profile['decade']}s",
        "profileFacts": {k: profile[k] for k in ("occupation", "hometown", "hobby", "family")},
        "lifeFacts": [{"factId": f["fact_id"], "title": f["title"], "content": f["content"], "createdAt": f["created_at"],
                       "source": "visit" if f["from_visit"] else "caregiver"} for f in facts],
        "photos": [{"photoId": p["photo_id"], "description": p["description"]} for p in photos],
        "topics": [{"topicId": t["topic_id"], "title": t["title"], "description": t["description"],
                    "evidence": t["evidence"] or [], "createdAt": t["created_at"], "feedback": by_topic.get(t["topic_id"], [])}
                   for t in topics],
        "visits": [{"sessionId": v["session_id"], "startedAt": v["started_at"], "setId": v["set_id"]} for v in visits],
        "pastCards": [{"cardId": c["card_id"], "setId": c["set_id"], "topicId": c["topic_id"], "position": c["position"],
                       "cardTitle": c["card_title"], "primaryQuestion": c["primary_question"], "evidence": c["evidence"] or [],
                       "selected": c["selected"], "reviewReaction": c["review_reaction"]} for c in cards],
    })
