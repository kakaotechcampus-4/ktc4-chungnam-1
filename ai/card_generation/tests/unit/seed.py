"""테스트용 합성 데이터. 실제 사용자 자료가 아니다.

어르신 A의 면회 4번(v1~v4)과 면회에 쓰이지 않은 카드 묶음 1개, 비교용 어르신 B를 넣는다.
보호자 결정과 기대 점수(decay 0.7):
  탄광 시절  more(v2 뒤, 이후 면회 2번) + more(v3 뒤, 1번) = 0.49 + 0.7 = 1.19  → continue
  바다 이야기 less(v1 뒤, 3번) = -0.343                                       → revisit
  고향 집    less(v4 뒤, 0번) = -1.0                                         → resting
  장터 구경  exclude                                                         → excluded
  그 시절 노래, 옛 친구  결정 없음 = 0                                         → revisit
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timezone

import psycopg

VISIT_STARTS = [datetime(2026, 9, d, 10, tzinfo=timezone.utc) for d in (1, 8, 15, 22)]


def _decided(visit: int) -> datetime:
    """v{visit} 다음 날 결정."""
    return VISIT_STARTS[visit - 1].replace(day=VISIT_STARTS[visit - 1].day + 1)


@dataclass
class Seeded:
    profile_a: str
    profile_b: str
    facts: dict[str, str] = field(default_factory=dict)
    photos: dict[str, str] = field(default_factory=dict)
    topics: dict[str, str] = field(default_factory=dict)
    missing_fact: str = ""
    fact_b: str = ""
    topic_b: str = ""


def _id(conn: psycopg.Connection, sql: str, *params: object) -> str:
    return str(conn.execute(sql, params).fetchone()[0])


def _profile(conn: psycopg.Connection, sub: str, **details: str | None) -> str:
    user = _id(conn, "INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id", sub)
    today = date.today()
    birth = today.replace(year=today.year - 85)
    return _id(conn,
               "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage, symptom_note, "
               "occupation, hometown, hobby, family) VALUES (%s, '합성이름', 'male', %s, 'mildDementia', "
               "'합성 증상 메모', %s, %s, %s, %s) RETURNING profile_id",
               user, birth, details.get("occupation"), details.get("hometown"), details.get("hobby"),
               details.get("family"))


def seed(conn: psycopg.Connection) -> Seeded:
    pid = _profile(conn, "synthetic-a", occupation="태백 탄광에서 광부로 일하심", hometown="강원도 태백",
                   hobby=None, family="아들 둘, 딸 하나")
    s = Seeded(profile_a=pid, profile_b="")

    visits = [_id(conn, "INSERT INTO visit_sessions (profile_id, started_at, evaluation_satisfaction, "
                        "evaluation_reaction, evaluation_note, evaluated_at) VALUES (%s, %s, 4, 'pleased', "
                        "'합성 평가 메모', %s) RETURNING session_id", pid, t, t) for t in VISIT_STARTS]

    for key, title, content in [
        ("coal", "탄광 동료들", "태백 탄광에서 일할 때 동료들과 도시락을 나눠 먹으며 지내셨다."),
        ("sea", "고기잡이", "젊을 때 삼척 앞바다에서 배를 타고 고기를 잡으셨다."),
        ("song", "라디오 노래", "저녁마다 라디오에서 나오는 트로트를 즐겨 들으셨다."),
        ("wedding", "결혼식", "읍내 예식장에서 결혼식을 올리셨다."),
    ]:
        s.facts[key] = _id(conn, "INSERT INTO life_facts (profile_id, title, content, created_at) "
                                 "VALUES (%s, %s, %s, %s) RETURNING fact_id",
                           pid, title, content, datetime(2026, 8, len(s.facts) + 1, tzinfo=timezone.utc))
    proposal = _id(conn, "INSERT INTO life_fact_proposals (session_id, profile_id, title, content, reason, status) "
                         "VALUES (%s, %s, '장터 국밥', '장날이면 장터에서 국밥을 사 드셨다.', '합성', 'settled') "
                         "RETURNING proposal_id", visits[0], pid)
    s.facts["market"] = _id(conn, "INSERT INTO life_facts (profile_id, title, content, source_proposal_id, created_at) "
                                  "VALUES (%s, '장터 국밥', '장날이면 장터에서 국밥을 사 드셨다.', %s, now()) "
                                  "RETURNING fact_id",
                            pid, proposal)
    # 면회에서 나온 아직 승인하지 않은 제안. 도구에 보이면 안 된다.
    conn.execute("INSERT INTO life_fact_proposals (session_id, profile_id, title, content, reason) "
                 "VALUES (%s, %s, '승인 전 제안', '확인되지 않은 합성 내용', '합성')", (visits[3], pid))

    s.photos["beach"] = _id(conn, "INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, "
                                  "model, prompt_version) VALUES (%s, 'synthetic/beach.jpg', "
                                  "'바닷가에서 가족이 함께 찍은 사진', 'completed', 'synthetic', 'v0') RETURNING photo_id",
                            pid)
    conn.execute("INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, 'synthetic/pending.jpg')", (pid,))

    s.missing_fact = str(uuid.uuid4())
    for key, title, description, evidence in [
        ("coal", "탄광 시절", "태백 탄광에서 광부로 일하던 시절과 함께 일한 동료들 이야기", [{"factId": s.facts["coal"]}]),
        ("market", "장터 구경", "장날이면 장터에 나가 구경하고 국밥을 사 드시던 이야기", []),
        ("home", "고향 집", "강원도 태백 고향 집과 동네 풍경 이야기", [{"profileField": "hometown"}]),
        ("song", "그 시절 노래", "젊은 시절 라디오로 즐겨 듣던 트로트 이야기", []),
        ("sea", "바다 이야기", "삼척 앞바다에서 배를 타고 고기를 잡던 이야기", [{"factId": s.facts["sea"]}]),
        ("gone", "옛 친구", "어린 시절 함께 놀던 옛 친구 이야기", [{"factId": s.missing_fact}]),
    ]:
        s.topics[key] = _id(conn, "INSERT INTO profile_topics (profile_id, title, description, evidence) "
                                  "VALUES (%s, %s, %s, %s) RETURNING topic_id",
                            pid, title, description, json.dumps(evidence))

    def card_set(session: str | None) -> str:
        return _id(conn, "INSERT INTO card_sets (profile_id, session_id, status, model, prompt_version, "
                         "generation_log) VALUES (%s, %s, 'completed', 'synthetic', 'v0', '{\"input\": {}}') "
                         "RETURNING set_id", pid, session)

    def card(set_id: str, pos: int, topic: str, evidence: list[dict[str, str]], selected: bool,
             reaction: str | None) -> str:
        source = "none" if not evidence else ("photo" if "photoId" in evidence[0] else "life_fact")
        return _id(conn,
                   "INSERT INTO conversation_cards (set_id, profile_id, topic_id, card_title, position, description, "
                   "primary_question, follow_up_questions, evidence_source, evidence, selected, review_reaction) "
                   "VALUES (%s, %s, %s, %s, %s, '합성 설명', %s, ARRAY['합성 꼬리 질문'], %s, %s, %s, %s) "
                   "RETURNING card_id",
                   set_id, pid, s.topics[topic], f"{topic} 카드 {pos}", pos, f"{topic} 질문 {pos}?", source,
                   json.dumps(evidence), selected, reaction)

    def decide(visit: int, card_id: str, topic: str, action: str) -> None:
        proposal = _id(conn, "INSERT INTO topic_proposals (session_id, profile_id, card_id, topic_id, "
                             "suggested_action, reason, status) VALUES (%s, %s, %s, %s, %s, '합성', 'settled') "
                             "RETURNING proposal_id", visits[visit - 1], pid, card_id, s.topics[topic], action)
        conn.execute("INSERT INTO topic_feedback (profile_id, topic_id, proposal_id, action, decided_at) "
                     "VALUES (%s, %s, %s, %s, %s)", (pid, s.topics[topic], proposal, action, _decided(visit)))

    coal, sea = [{"factId": s.facts["coal"]}], [{"factId": s.facts["sea"]}]
    hometown = [{"profileField": "hometown"}]

    v1 = card_set(visits[0])
    card(v1, 1, "coal", coal, True, "positive")
    sea_v1 = card(v1, 2, "sea", sea, True, "negative")
    card(v1, 3, "song", [], False, None)
    decide(1, sea_v1, "sea", "less")

    v2 = card_set(visits[1])
    coal_v2 = card(v2, 1, "coal", [{"profileField": "occupation"}], True, "positive")
    market_v2 = card(v2, 2, "market", [], True, "neutral")
    decide(2, coal_v2, "coal", "more")
    decide(2, market_v2, "market", "exclude")

    v3 = card_set(visits[2])
    coal_v3 = card(v3, 1, "coal", coal, True, None)
    card(v3, 2, "home", hometown, True, None)
    decide(3, coal_v3, "coal", "more")

    v4 = card_set(visits[3])
    home_v4 = card(v4, 1, "home", hometown, True, "neutral")
    card(v4, 2, "song", [], True, "positive")
    card(v4, 3, "gone", [{"factId": s.missing_fact}], False, None)
    decide(4, home_v4, "home", "less")

    unused = card_set(None)  # 만들었지만 면회에 쓰지 않은 묶음. 사용 이력에 세지 않는다.
    card(unused, 1, "sea", sea, False, None)

    # 다른 어르신. A의 도구로는 보이면 안 된다.
    pb = _profile(conn, "synthetic-b", occupation="합성 B 직업", hometown=None, hobby=None, family=None)
    s.profile_b = pb
    s.fact_b = _id(conn, "INSERT INTO life_facts (profile_id, title, content) VALUES (%s, 'B의 이야기', "
                         "'다른 어르신의 바다 이야기') RETURNING fact_id", pb)
    s.topic_b = _id(conn, "INSERT INTO profile_topics (profile_id, title, description) VALUES (%s, 'B 주제', "
                          "'B 설명') RETURNING topic_id", pb)
    return s
