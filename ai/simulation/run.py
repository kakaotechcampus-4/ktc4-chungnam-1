"""페르소나 시뮬레이션. 합성 어르신·보호자 페르소나로 앱 사용 흐름을 처음부터 따라가며 면회를 여러 회차 이어서 돌린다.

    uv run python -m simulation.run --persona simulation/personas/seocheon-seamstress.json \
        [--visits 5] [--seed 7]

카드와 결정은 PR #84 스키마(profile_topics, card_sets, conversation_cards, topic_*)에 쓴다.

앱 흐름(origin/codex/report-proposal-review 기준)을 따른다.
  처음 한 번  프로필 입력: 기본 정보(필수), 생애 질문 네 개(선택), 사진 한 장(선택)과 태그 고르기
  회차마다    1 카드 받기: card_generation로 12장. 앞 9장은 고르는 대상, 10~12번은 면회 중 추가용
              2 카드 고르기: 보호자가 앞 9장 중 1~9장
              3 면회 사진: 찍었는지만 기록(리포트용)
              4 녹음과 대화: 어르신·보호자 에이전트가 한 턴씩. 보호자는 보충 카드를 추가할 수 있다
              5 소감: 만족도·반응(필수), 카드별 평가·메모(선택)
              6 음성 인식: 화자를 "화자 1·2"로만 나눈 글로 바꾼다(누가 어르신인지 시스템은 모른다)
              7 리포트와 변경 제안: report_generation, proposal_generation(#106 내부 API 형식)
              8 변경 사항 확인: 보호자가 ×로 빼기, 행동 바꾸기, 이름·내용 고치기. 쌓아온 이야기에 직접 추가
              9 반영: 남긴 것만 DB에 넣는다
결과는 runs/persona-<판>-<id>-<seed>-<시각>.json과 .events.jsonl에 남는다(커밋하지 않음).
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any, Callable

import psycopg

from card_generation._steps.research.agent import AgentFailed
from card_generation._steps.select import SelectionFailed
from card_generation._steps.write import WritingFailed
from common.llm import chat_model
from common.visit_report import (
    ReportCard,
    ReportCardTopic,
    ReportEvaluation,
    ReportLifeFact,
    ReportProfileFacts,
    Transcript,
    TranscriptSegment,
    VisitReportRequest,
    combine,
)
from proposal_generation import PROMPT as PROPOSALS_PROMPT
from proposal_generation import generate_proposals
from report_generation import PROMPT as REPORT_PROMPT
from report_generation import generate_report
from simulation.llm_env import config_from_env

from . import roles, topic_size, tracing
from .backends import Backend, get_backend
from .backends.context import build_context

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
DB_ENV = "TOPIC_REC_DATABASE_URL"
DEFAULT_MOODS = [["좋음", 3], ["보통", 3], ["조금 피곤함", 2], ["기운 없음", 1], ["예민함", 1]]
SIM_PROMPTS = HERE / "prompts"
PROBE_TURN = 10  # 시험용 의도를 보호자에게 지금 꺼내라고 알리는 턴(면회 초반 인사가 끝난 뒤)
CARD_FIELDS = ("position", "card_title", "description", "primary_question", "follow_up_questions")
_TIME_COLS = ("created_at", "decided_at", "started_at", "recorded_at")


def prompt_files(backend: Backend) -> dict[str, Path]:
    """이 판에서 실제로 쓰는 프롬프트. 웹 화면의 편집 목록도 이것을 쓴다."""
    return {
        "보호자: 프로필 입력": SIM_PROMPTS / "caregiver_onboarding.md",
        "사진 분석(VLM) 대역": SIM_PROMPTS / "vlm_photo.md",
        "보호자: 사진 태그 고르기": SIM_PROMPTS / "caregiver_tags.md",
        **{name: ROOT / path for name, path in backend.prompt_files.items()},
        "보호자: 카드 고르기": SIM_PROMPTS / "caregiver_select.md",
        "대화: 어르신 한 턴": SIM_PROMPTS / "patient_turn.md",
        "대화: 보호자 한 턴": SIM_PROMPTS / "caregiver_turn.md",
        "보호자: 소감": SIM_PROMPTS / "caregiver_review.md",
        "면회 리포트": REPORT_PROMPT,
        "변경 제안": PROPOSALS_PROMPT,
        "보호자: 변경 사항 확인": SIM_PROMPTS / "caregiver_changes.md",
        "평가: 이야기 대조": SIM_PROMPTS / "story_match.md",
        "평가: 주제 크기": SIM_PROMPTS / "topic_story.md",
    }


# ── 처음 한 번 ──────────────────────────────────────
def create_user(conn: psycopg.Connection, backend: Backend, persona: dict[str, Any], seed: int) -> str:
    """가입까지. 판·페르소나·시드가 같은 실행만 지우고 새로 만든다. 다른 실행을 같은 DB에서 동시에 돌려도 서로 지우지 않는다."""
    sub = f"sim-{backend.name}-{persona['id']}-{seed}"
    conn.execute("DELETE FROM users WHERE google_sub = %s", (sub,))
    return str(conn.execute("INSERT INTO users (google_sub) VALUES (%s) RETURNING user_id", (sub,)).fetchone()[0])


def onboarding(model, backend: Backend, persona: dict[str, Any], url: str, user_id: str, seed: int) -> tuple[str, dict[str, Any]]:
    """프로필 입력 화면. (profile_id, 기록)."""
    ob = roles.caregiver_onboarding(model, persona)
    b, a = ob.basic, ob.answers
    try:
        birth = date(b.birth_year, b.birth_month, b.birth_day)
    except ValueError:
        birth = date(b.birth_year, 1, 1)
    record: dict[str, Any] = {"basic": b.model_dump(), "answers": a.model_dump(), "photo_id": ob.photo_id, "why": ob.why}
    photo = next((x for x in persona.get("album", []) if x["id"] == ob.photo_id), None)
    if photo:
        vlm = roles.vlm_photo(model, photo["truth"])
        tags = roles.caregiver_tags(model, persona, photo["truth"], vlm.tag_candidates)
        record["photo"] = {"truth": photo["truth"], "description": vlm.description, "tag_candidates": vlm.tag_candidates,
                           "tags_chosen": tags.chosen, "tags_why": tags.why}
    with psycopg.connect(url) as conn:
        pid = str(conn.execute(
            "INSERT INTO profiles (user_id, name, gender, birth_date, condition_stage, occupation, hometown, hobby, family) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING profile_id",
            (user_id, b.name, b.gender, birth, b.condition_stage, *(getattr(a, k) or None for k in
                                                                     ("occupation", "hometown", "hobby", "family")))).fetchone()[0])
        if photo:  # s3_object_key는 DB 전체에서 겹치면 안 된다
            conn.execute("INSERT INTO photos (profile_id, s3_object_key, description, analysis_status, model, prompt_version) "
                         "VALUES (%s, %s, %s, 'completed', 'sim-vlm', 'v0')",
                         (pid, f"sim/{backend.name}/{persona['id']}/{seed}/{photo['id']}.jpg", record["photo"]["description"]))
    tracing.emit("output", visit=0, what="프로필 입력", data=record)
    return pid, record


# ── DB 스냅숏 ──────────────────────────────────────
def _plain(value: Any) -> Any:
    if isinstance(value, (uuid.UUID, datetime, date, Decimal)):
        return value.isoformat() if isinstance(value, (datetime, date)) else str(value)
    return value


def db_snapshot(backend: Backend, url: str, pid: str) -> dict[str, dict[str, Any]]:
    """이 프로필에 걸린 행을 테이블마다 열 그대로 담는다. {테이블: {key, columns, rows}}.
    ID를 이름으로 바꿔 보여 주는 일은 화면이 한다(같은 스냅숏 안의 행으로 이름표를 만든다)."""
    out: dict[str, dict[str, Any]] = {}
    with psycopg.connect(url) as conn:
        for table, key, where in backend.snapshot_tables:
            try:
                cols = [c.name for c in conn.execute(f"SELECT * FROM {table} LIMIT 0").description]
            except psycopg.errors.UndefinedTable:
                conn.rollback()
                continue
            order = [c for c in _TIME_COLS if c in cols][:1] + (["position"] if "position" in cols else []) + list(key)
            cur = conn.execute(f"SELECT * FROM {table} WHERE {where} ORDER BY {', '.join(order)}", {"pid": pid})
            out[table] = {"key": ",".join(key), "columns": cols,
                          "rows": [{c: _plain(v) for c, v in zip(cols, r)} for r in cur.fetchall()]}
    return out


def take_snapshot(run: dict[str, Any], backend: Backend, url: str, pid: str, point: str, label: str, visit: int) -> None:
    """화면의 DB 탭이 시점별로 보여 줄 스냅숏을 남기고, 실행 중인 화면에도 바로 보낸다."""
    snap = {"id": point, "label": label, "visit": visit, "tables": db_snapshot(backend, url, pid)}
    run.setdefault("db_snapshots", []).append(snap)
    tracing.emit("db_snapshot", **snap)


def learned_facts(backend: Backend, url: str, pid: str) -> list[dict[str, str]]:
    """보호자가 앱에서 승인하거나 직접 넣은 이야기. 보호자도 이제 아는 것이다."""
    with psycopg.connect(url) as ro:
        facts = backend.store(ro, pid).list_life_facts(order="oldest", limit=30).facts
    return [{"title": f.title, "content": f.content} for f in facts]


# ── 실행 ────────────────────────────────────────────
def simulate(persona_path: Path, recommender: str, visits: int | None, seed: int, url: str,
             sink: Callable[[dict[str, Any]], None] | None = None,
             should_stop: Callable[[], bool] = lambda: False) -> Path:
    """시뮬레이션 한 번. sink를 주면 진행 이벤트(단계, LLM 요청, 도구 호출, 대화 턴, 중간 산출물)를 받는다."""
    backend = get_backend(recommender)
    tag = backend.name
    persona = json.loads(persona_path.read_text())
    visits = visits or persona["visits"]["count"]
    out_path = HERE / "runs" / f"persona-{tag}-{persona['id']}-{seed}-{datetime.now():%Y%m%d-%H%M%S}.json"
    events_path = out_path.with_suffix(".events.jsonl")

    def write_event(event: dict[str, Any]) -> None:
        with events_path.open("a") as f:
            f.write(json.dumps(event, ensure_ascii=False, default=str) + "\n")
        if sink:
            sink(event)

    tracing.set_sink(write_event)
    try:
        rng = random.Random(seed)
        config = config_from_env()
        model = chat_model(config)
        run: dict[str, Any] = {"recommender": backend.name, "persona": persona, "seed": seed, "llm": config.name,
                               "started_at": datetime.now().isoformat(), "visits": [], "failure": None,
                               "prompts": {name: path.read_text() for name, path in prompt_files(backend).items()}}
        tracing.emit("run_start", run=out_path.stem, persona=persona["id"], recommender=backend.name, visits=visits, seed=seed)
        try:
            with psycopg.connect(url) as conn:
                backend.prepare(conn)
                user_id = create_user(conn, backend, persona, seed)
            with tracing.stage("처음 한 번 · 프로필 입력"):
                pid, run["onboarding"] = onboarding(model, backend, persona, url, user_id, seed)
            run["profile_id"] = pid
            run["initial_state"] = backend.state(url, pid)
            take_snapshot(run, backend, url, pid, "onboarding", "프로필 입력 직후", 0)
            out_path.write_text(json.dumps(run, ensure_ascii=False, indent=1, default=str))
            first = datetime.fromisoformat(persona["visits"]["first_at"])
            run_visits(run, backend, persona, visits, first, rng, url, pid, config, model, out_path, should_stop)
            if run["visits"]:
                with tracing.stage("평가: 주제 크기"):
                    run["topic_eval"] = topic_size.evaluate(run, model)
                    tracing.emit("output", visit=0, what="주제 크기", data=run["topic_eval"]["summary"])
        except Exception as error:  # 재시도해도 안 되는 LLM 오류 등. 끝난 회차는 이미 저장돼 있다
            run["failure"] = f"{len(run['visits']) + 1}회차 중단: {type(error).__name__}: {str(error)[:300]}"
            print(run["failure"])
            tracing.emit("run_error", error=run["failure"])
        out_path.write_text(json.dumps(run, ensure_ascii=False, indent=1, default=str))
        tracing.emit("run_end", run=out_path.stem, failure=run["failure"], visits=len(run["visits"]))
        print(f"결과: {out_path}")
        return out_path
    finally:
        tracing.set_sink(None)


def _pick_mood(rng: random.Random, persona: dict[str, Any]) -> str:
    moods = persona["visits"].get("moods") or DEFAULT_MOODS
    return rng.choices([m for m, _ in moods], weights=[w for _, w in moods])[0]


def run_visits(run, backend: Backend, persona, visits, first, rng, url, pid, config, model, out_path,
               should_stop) -> None:
    notes: list[str] = []
    heard: list[str] = []  # 지난 면회에서 어르신이 직접 한 이야기. 보호자도 들었으니 기억한다
    days = list(persona["caregiver"].get("visit_days", []))
    rng.shuffle(days)
    stories = {s["id"]: s["text"] for s in persona["patient"]["life_story"]}
    for n in range(1, visits + 1):
        if should_stop():
            run["failure"] = f"{n}회차 전에 사용자가 멈춤"
            return
        t0 = time.monotonic()
        started = first + timedelta(days=persona["visits"]["every_days"] * (n - 1))
        visit: dict[str, Any] = {"no": n, "date": started.isoformat(), "timings": {}}
        step = lambda name: tracing.stage(f"{n}회차 · {name}")
        tracing.emit("visit_start", visit=n, date=visit["date"])

        # 1 카드 받기
        try:
            with step("카드 받기(추천)"):
                cards, visit["recommend"] = backend.recommend(url, pid, config, model)
                tracing.emit("output", visit=n, what="추천 카드", data=[
                    {k: c[k] for k in ("position", "card_title", "bucket", "primary_question", "follow_up_questions")}
                    | backend.output_card(c) for c in cards])
        except (*backend.recommend_errors, AgentFailed, SelectionFailed, WritingFailed, RuntimeError) as error:
            run["failure"] = f"{n}회차 추천 실패: {error}"
            print(run["failure"])
            return
        visit["timings"]["recommend"] = round(time.monotonic() - t0)
        take_snapshot(run, backend, url, pid, f"v{n}-cards", "카드 저장 직후", n)
        public = {c["position"]: {k: c[k] for k in CARD_FIELDS} | {"elements": backend.card_names(c)} for c in cards}
        learned = learned_facts(backend, url, pid)

        # 2 카드 고르기(앞 9장)
        with step("카드 고르기"):
            sel = roles.caregiver_select(model, persona, [public[p] for p in range(1, 10) if p in public], learned)
            chosen = list(dict.fromkeys(p.position for p in sel.selected if 1 <= p.position <= 9)) or [1]  # 1장 이상
            why = {p.position: p.why for p in [*sel.selected, *sel.skipped]}
            tracing.emit("output", visit=n, what="보호자 선택", data=sel.model_dump())

        # 3 면회 사진, 4 녹음과 대화
        photo_taken = rng.random() < 0.5
        mood = _pick_mood(rng, persona)
        with step(f"녹음과 대화(기분: {mood})"):
            today = days[(n - 1) % len(days)] if days else ""
            # 시험판 페르소나만: 정한 회차에 보호자의 그날 의도를 더한다. 결과에 따로 남겨 자연 발생 결과와 섞이지 않게 한다
            intent = persona["caregiver"].get("visit_intents", {}).get(str(n))
            if intent:
                today = f"{today} {intent}".strip()
                visit["probe_intent"] = intent
                tracing.emit("output", visit=n, what="시험용 의도", data={"intent": intent})
            turns, revealed, added = roles.dialogue(model, persona, n, mood, [public[p] for p in chosen],
                                                    [public[p] for p in (10, 11, 12) if p in public], notes, learned,
                                                    today=today, heard=heard,
                                                    probe=(intent, PROBE_TURN) if intent else None)
        heard += [f"{n}회차: {stories[x]}" for x in revealed if x in stories]
        used = chosen + added
        for c in cards:
            c["selected"], c["added_in_visit"] = c["position"] in used, c["position"] in added
            c["select_why"] = why.get(c["position"], "면회 중에 추가함" if c["position"] in added else "")
        visit.update(today=today, mood=mood, photo_taken=photo_taken, transcript=turns, revealed_story_ids=revealed,
                     added_cards=added)

        # 5 소감
        with step("소감"):
            review = roles.caregiver_review(model, persona, [public[p] for p in used], turns, learned)
            reactions = {r.position: r.reaction for r in review.card_reviews if r.position in used}
            for c in cards:
                c["review"] = reactions.get(c["position"]) if c["selected"] else None
            sat = review.satisfaction if 1 <= review.satisfaction <= 5 else 3
            visit["evaluation"] = {"satisfaction": sat, "reaction": review.reaction, "note": review.note}
            notes.append(f"{n}회차 소감: {review.note}" if review.note else f"{n}회차 소감: 만족도 {sat}")
            tracing.emit("output", visit=n, what="소감", data=review.model_dump())

        # 6 음성 인식: 화자를 군집 이름(SPEAKER_00 등)으로만 남김. 누가 어르신인지 시스템은 모름
        labels = ["SPEAKER_00", "SPEAKER_01"]
        rng.shuffle(labels)
        who = {"caregiver": labels[0], "patient": labels[1]}
        visit["stt_labels"] = who
        segments, ms = [], 0
        for t in turns:
            length = 1000 + 60 * len(t["text"])
            segments.append(TranscriptSegment(start_ms=ms, end_ms=ms + length, speaker_label=who[t["speaker"]], text=t["text"]))
            ms += length

        # 7 리포트와 변경 제안: #106 내부 API(8-3)와 같은 형식
        selected = [c for c in cards if c["selected"]]
        by_card = {c["card_id"]: c for c in selected}
        with psycopg.connect(url) as ro:
            ctx = build_context(ro, pid)
        request = VisitReportRequest(
            analysis_id=f"sim-{n}", visit_date=started.date(),
            evaluation=ReportEvaluation(conversation_satisfaction=sat, care_recipient_reaction=review.reaction,
                                        free_note=review.note or None),
            cards=[ReportCard(card_id=c["card_id"], card_title=c["card_title"],
                              topic=ReportCardTopic(topic_id=c["topic_id"], title=c["topic"]["title"]), reaction=c["review"])
                   for c in selected],
            profile_facts=ReportProfileFacts(**ctx.profile_facts.model_dump()),
            life_facts=[ReportLifeFact(fact_id=f.fact_id, title=f.title, content=f.content) for f in ctx.life_facts],
            transcript=Transcript(duration_ms=ms, segments=segments))
        with step("리포트와 변경 제안 만들기"):
            kw = {"model": config.model, "api_key": config.api_key, "attempts": roles.MAX_ATTEMPTS, "on_retry": roles.on_retry}
            result = combine(request.analysis_id, generate_report(request, **kw), generate_proposals(request, **kw))
        visit["report"] = {"title": result.title, "body": result.body,
                           "card_summaries": [{"position": by_card[s.card_id]["position"], "summary": s.summary}
                                              for s in result.card_summaries]}
        tracing.emit("output", visit=n, what="리포트", data=visit["report"])
        topics = []
        for p in result.topic_proposals:
            card = by_card[p.card_id]
            topics.append({"index": len(topics), "card_position": card["position"], "card_title": card["card_title"],
                           "topic_name": card["topic"]["title"], "topic_description": card["topic"]["description"],
                           "suggested_action": p.suggested_action, "reason": p.reason})
        facts = [{"index": i, **f.model_dump()} for i, f in enumerate(result.life_fact_proposals)]
        tracing.emit("output", visit=n, what="변경 제안", data={"facts": facts, "topics": topics})

        # 8 변경 사항 확인
        with step("변경 사항 확인"):
            ch = roles.caregiver_changes(model, persona, visit["report"], turns, facts, topics, learned)
            tracing.emit("output", visit=n, what="보호자 확인", data=ch.model_dump())
        topic_ch = {c.index: c for c in ch.topics}
        fact_ch = {c.index: c for c in ch.facts}

        # 9 반영
        decided_at = started + timedelta(hours=3)
        applied_facts, applied_feedback, manual = [], [], []
        with psycopg.connect(url) as rw, rw.transaction():
            session = rw.execute(
                "INSERT INTO visit_sessions (profile_id, started_at, evaluation_satisfaction, evaluation_reaction, "
                "evaluation_note, evaluated_at, report_title, report_body, report_model, report_prompt_version, "
                "report_generated_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'sim', %s) RETURNING session_id",
                (pid, started, sat, review.reaction, review.note or None, started + timedelta(hours=1), result.title,
                 result.body, config.name, started + timedelta(hours=2))).fetchone()[0]
            backend.attach_cards(rw, session, cards, {s["position"]: s["summary"] for s in visit["report"]["card_summaries"]})
            for f in facts:
                d = fact_ch.get(f["index"])
                keep = d.keep if d else True  # 빼지 않으면 반영된다
                f["decision"] = d.model_dump() if d else {"keep": True, "why": "따로 손대지 않음"}
                title = d.new_title if d and d.new_title else f["title"]
                content = d.new_content if d and d.new_content else f["content"]
                proposal = rw.execute(
                    "INSERT INTO life_fact_proposals (session_id, profile_id, title, content, reason, status) "
                    "VALUES (%s, %s, %s, %s, %s, 'settled') RETURNING proposal_id",
                    (session, pid, f["title"], f["content"], f["reason"])).fetchone()[0]
                if keep:
                    rw.execute("INSERT INTO life_facts (profile_id, title, content, source_proposal_id, created_at) "
                               "VALUES (%s, %s, %s, %s, %s)", (pid, title, content, proposal, decided_at))
                    applied_facts.append({"title": title, "content": content, "edited": bool(d and (d.new_title or d.new_content))})
            for t in topics:
                d = topic_ch.get(t["index"])
                t["decision"] = d.model_dump() if d else {"keep": True, "action": t["suggested_action"], "why": "따로 손대지 않음"}
                card = next(c for c in cards if c["position"] == t["card_position"])
                done = backend.apply_adjustment(rw, pid, session, decided_at, card, t, d)
                if done:
                    applied_feedback.append(done)
            for m in ch.manual_stories:
                rw.execute("INSERT INTO life_facts (profile_id, title, content, created_at) VALUES (%s, %s, %s, %s)",
                           (pid, m.title, m.content, decided_at))
                manual.append({"title": m.title, "content": m.content})
        with step("평가: 저장된 이야기와 숨은 생애 대조"):
            saved = applied_facts + manual
            links = roles.story_match(model, persona, [{"index": i, **f} for i, f in enumerate(saved)]).links if saved else []
            for link in links:
                if 0 <= link.index < len(saved):
                    saved[link.index].update(story_id=link.story_id, fabricated=link.fabricated)
        visit.update(cards=[backend.strip(c) for c in cards], proposals={"facts": facts, "adjustments": topics},
                     applied={"facts": applied_facts, "feedback": applied_feedback, "manual": manual},
                     state_after=backend.state(url, pid))
        take_snapshot(run, backend, url, pid, f"v{n}-applied", "변경 반영 직후", n)
        visit["timings"]["total"] = round(time.monotonic() - t0)
        visit["llm_retries"] = list(roles.RETRIES)
        roles.RETRIES.clear()
        run["visits"].append(visit)
        out_path.write_text(json.dumps(run, ensure_ascii=False, indent=1, default=str))
        tracing.emit("visit_end", visit=n, seconds=visit["timings"]["total"], applied=visit["applied"])
        print(f"[{n}회차] 끝: 고른 카드 {len(chosen)}장(+추가 {len(added)}), 대화 {len(turns)}턴, 이야기 후보 {len(facts)}개 중 "
              f"{len(applied_facts)}개 저장(+직접 {len(manual)}), 조정 {len(applied_feedback)}건, {visit['timings']['total']}초", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--persona", required=True)
    ap.add_argument("--recommender", choices=["topics"], default="topics")
    ap.add_argument("--visits", type=int)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    url = os.environ.get(DB_ENV)
    if not url:
        print(f"{DB_ENV}가 없습니다", file=sys.stderr)
        return 2
    out = simulate(Path(args.persona), args.recommender, args.visits, args.seed, url)
    return 0 if json.loads(out.read_text())["failure"] is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
