"""backend 역할: PR #84 테이블에서 카드 생성 context를 조립한다. backend `app/services/card_sets.py`의
`build_context`를 동기 방식으로 옮긴 것이다. 규칙을 바꿀 때는 그쪽과 같이 고친다.

넘기는 것과 거르는 조건은 card_generation/contract.py 설명과 같다.
  면회      evaluated_at이 있는 회차만, 시간순. 그 회차에 연결된 카드 묶음(card_sets.session_id)을 setId로 붙인다
  지난 카드 그 면회 묶음들의 카드만
  사진      프로필 사진(session_id 없음) 중 보호자 설명이 있거나 분석이 끝난 것. 보호자 설명을 AI 설명보다 먼저 쓴다(#205)
  결정      topic_feedback(승인된 결정)만. topic_proposals는 넘기지 않는다
  제외      exclude한 주제의 근거 이야기와 사진은 입력에서 뺀다(이름만 다른 새 주제가 나오지 않게)
  근거      context에 없는 이야기와 사진을 가리키는 주제와 지난 카드의 근거 항목은 뺀다.
            이야기나 사진 근거가 모두 사라진 주제는 넣지 않는다(#291). 원래 근거가 없던 주제와 세부 정보 칸 근거는 그대로
"""

from __future__ import annotations

from typing import Any

import psycopg
from psycopg.rows import dict_row

from card_generation.contract import CardContext


def _without_missing(evidence: list[dict[str, str]], fact_ids: set[str], photo_ids: set[str]) -> list[dict[str, str]]:
    """context에 없는 이야기나 사진을 가리키는 근거 항목을 뺀다. 세부 정보 칸(profileField)은 남긴다."""
    return [e for e in evidence
            if ("factId" not in e or e["factId"] in fact_ids) and ("photoId" not in e or e["photoId"] in photo_ids)]


def build_context(conn: psycopg.Connection, profile_id: str, backend_filters: bool = True) -> CardContext:
    """backend_filters=False면 제외와 근거 정리를 하지 않은 원본을 돌려준다. 카드 생성 단위 테스트가
    ProfileStore의 방어 동작(지워진 근거 표시 등)을 확인할 때만 쓴다. 시뮬레이션은 늘 backend와 같게 거른다."""
    conn.row_factory = dict_row

    def rows(sql: str) -> list[dict[str, Any]]:
        return conn.execute(sql, {"pid": profile_id}).fetchall()

    profile = rows("SELECT (date_part('year', age(current_date, birth_date))::int / 10 * 10) AS decade, "
                   "occupation, hometown, hobby, family FROM profiles WHERE profile_id = %(pid)s")[0]
    facts = rows("SELECT fact_id::text, title, content, created_at, sensitive, source_proposal_id IS NOT NULL AS from_visit "
                 "FROM life_facts WHERE profile_id = %(pid)s ORDER BY created_at, fact_id")
    photos = rows("SELECT photo_id::text, COALESCE(user_description, description) AS description FROM photos "
                  "WHERE profile_id = %(pid)s AND session_id IS NULL "
                  "AND (user_description IS NOT NULL OR analysis_status = 'completed') ORDER BY created_at, photo_id")
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
                 "WHERE c.profile_id = %(pid)s AND v.evaluated_at IS NOT NULL "
                 "ORDER BY v.started_at, c.position")
    by_topic: dict[str, list[dict[str, Any]]] = {}
    for f in feedback:
        by_topic.setdefault(f["topic_id"], []).append({"action": f["action"], "decidedAt": f["decided_at"]})

    if not backend_filters:
        return _context(profile, facts, photos, topics, by_topic, visits, cards,
                        {t["topic_id"]: t["evidence"] or [] for t in topics}, lambda ev: ev or [])
    # 제외 규칙으로 빼기 전에 DB에 남은 이야기와 입력에 넣을 수 있는 사진
    stored_facts = {f["fact_id"] for f in facts}
    stored_photos = {p["photo_id"] for p in photos}
    excluded_topics = {tid for tid, items in by_topic.items() if any(i["action"] == "exclude" for i in items)}
    excluded = {(k, e[k]) for t in topics if t["topic_id"] in excluded_topics
                for e in (t["evidence"] or []) for k in ("factId", "photoId") if k in e}
    facts = [f for f in facts if ("factId", f["fact_id"]) not in excluded]
    photos = [p for p in photos if ("photoId", p["photo_id"]) not in excluded]
    fact_ids, photo_ids = {f["fact_id"] for f in facts}, {p["photo_id"] for p in photos}
    evidence = {t["topic_id"]: _without_missing(t["evidence"] or [], fact_ids, photo_ids) for t in topics}

    def gone(t: dict[str, Any]) -> bool:
        """이야기나 사진 근거가 있었는데 하나도 안 남은 주제. 제외한 주제는 제외 전 DB 기준으로 본다(PM 결정 2026-11-09)."""
        remaining = (_without_missing(t["evidence"] or [], stored_facts, stored_photos)
                     if t["topic_id"] in excluded_topics else evidence[t["topic_id"]])
        return bool(t["evidence"]) and not remaining

    topics = [t for t in topics if not gone(t)]
    return _context(profile, facts, photos, topics, by_topic, visits, cards, evidence,
                    lambda ev: _without_missing(ev or [], fact_ids, photo_ids))


def _context(profile, facts, photos, topics, by_topic, visits, cards, evidence, card_evidence) -> CardContext:
    return CardContext.model_validate({
        "ageRange": f"{profile['decade']}s",
        "profileFacts": {k: profile[k] for k in ("occupation", "hometown", "hobby", "family")},
        "lifeFacts": [{"factId": f["fact_id"], "title": f["title"], "content": f["content"], "createdAt": f["created_at"],
                       "source": "visit" if f["from_visit"] else "caregiver", "sensitive": f["sensitive"]} for f in facts],
        "photos": [{"photoId": p["photo_id"], "description": p["description"]} for p in photos],
        "topics": [{"topicId": t["topic_id"], "title": t["title"], "description": t["description"],
                    "evidence": evidence[t["topic_id"]], "createdAt": t["created_at"], "feedback": by_topic.get(t["topic_id"], [])}
                   for t in topics],
        "visits": [{"sessionId": v["session_id"], "startedAt": v["started_at"], "setId": v["set_id"]} for v in visits],
        "pastCards": [{"cardId": c["card_id"], "setId": c["set_id"], "topicId": c["topic_id"], "position": c["position"],
                       "cardTitle": c["card_title"], "primaryQuestion": c["primary_question"],
                       "evidence": card_evidence(c["evidence"]),
                       "selected": c["selected"], "reviewReaction": c["review_reaction"]} for c in cards],
    })
