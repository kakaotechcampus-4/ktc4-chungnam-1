"""페르소나 시뮬레이션의 LLM 역할. 역할마다 볼 수 있는 정보를 여기서 갈라 놓는다.

  보호자(온보딩·고르기·소감·변경 확인)  보호자 페르소나, 보호자가 아는 생애(처음 아는 것 + 앱에 저장된 것), 그 화면의 내용
  어르신(대화 한 턴)                    어르신 페르소나(숨은 생애사 포함)와 지금까지의 대화. 카드는 모른다
  보호자(대화 한 턴)                    보호자가 아는 것, 고른 카드와 보충 카드, 지난 면회 메모, 지금까지의 대화
  사진 분석(VLM)                        사진 내용 글(truth)만
  평가자(이야기 대조, 주제 크기)          숨은 생애사와 저장된 이야기·주제. 시스템에는 영향을 주지 않는다

시스템 쪽은 여기 없음. 카드 추천은 card_generation, 리포트·변경 제안은 report_generation, proposal_generation을 부름.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Literal

from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel, Field

from common.structured import invoke_structured

from .tracing import emit

PROMPTS = Path(__file__).resolve().parent / "prompts"
Reaction = Literal["positive", "neutral", "negative", "notUsed"]
Action = Literal["more", "less", "exclude"]
MAX_ATTEMPTS = 3
TIRED_MIN_TURNS = 8  # 어르신이 지쳐 하실 때 보호자가 마무리할 수 있는 최소 턴
STALL_TURNS = 6  # 새 이야기도 카드도 없이 이만큼 지나면 이야기가 끊긴 것으로 본다
RETRIES: list[dict[str, str]] = []  # 실행 기록에 남기려고 모은다


def on_retry(info: dict[str, str]) -> None:
    RETRIES.append(info)
    emit("retry", **info)


def _call(model: BaseChatModel, schema: type[BaseModel], prompt: str, payload: dict[str, Any]) -> BaseModel:
    """시뮬레이션 역할 호출. 프롬프트 파일과 JSON 입력을 보낸다. 형식이 깨지면 MAX_ATTEMPTS번까지 다시 보내고 RETRIES에 남긴다."""
    path = PROMPTS / prompt
    return invoke_structured(model, schema, [("system", path.read_text()), ("user", json.dumps(payload, ensure_ascii=False))],
                             path.name, MAX_ATTEMPTS, on_retry)


def _call_messages(model: BaseChatModel, schema: type[BaseModel], label: str, messages: list[tuple[str, str]]) -> BaseModel:
    """system 프롬프트와 대화 메시지를 그대로 보내는 호출. 재시도 방식은 _call과 같다."""
    return invoke_structured(model, schema, messages, label, MAX_ATTEMPTS, on_retry)


EMOTION = {"positive": "즐거운 기억", "painful": "아픈 기억", "mixed": "좋기도 하고 아쉽기도 한 기억", "neutral": "담담한 기억"}


def caregiver_persona_text(persona: dict[str, Any], learned: list[dict[str, str]]) -> str:
    c = persona["caregiver"]
    known = [s["text"] for s in persona["patient"]["life_story"] if s["id"] in c["knows"]]
    known += [f"{f['title']}: {f['content']}" for f in learned]
    calls = c.get("calls_patient", "어머님")
    lines = [f"너는 {c['summary']}", c.get("life", ""), f"너와 {calls}의 관계: {c.get('relationship', '')}",
             f"면회 때 하는 일: {c.get('visit_habits', '')}", f"말투: {c.get('speech', '')}",
             "말투 예시: " + " / ".join(f"\"{x}\"" for x in c.get("speech_examples", [])),
             f"부르는 말: {calls}",
             f"피하고 싶은 것: {c.get('wants_to_avoid', '')}", f"바라는 것: {c.get('hopes', '')}",
             "", f"{calls}에 대해 네가 아는 것:", *[f"- {k}" for k in known]]
    return "\n".join(x for x in lines if x is not None)


def patient_persona_text(persona: dict[str, Any]) -> str:
    p = persona["patient"]
    lines = [f"너는 {p['summary']}", f"성격: {p.get('personality', '')}", f"말투: {p.get('speech', '')}",
             "말투 예시: " + " / ".join(f"\"{x}\"" for x in p.get("speech_examples", [])),
             f"요즘 상태: {p.get('cognition', '')}", f"대화 버릇: {p.get('conversation_habits', '')}"]
    if p.get("relationship_to_caregiver"):
        lines.append(f"찾아오는 사람과의 사이: {p['relationship_to_caregiver']}")
    return "\n".join(lines)


def _cards_text(cards: list[dict[str, Any]]) -> str:
    if not cards:
        return "없음"
    out = []
    for c in cards:
        follow = " / ".join(c.get("follow_up_questions", []))
        out.append(f"#{c['position']} {c['card_title']}: {c.get('description', '')}\n  첫 질문: {c['primary_question']}"
                   + (f"\n  이어서 물을 것: {follow}" if follow else ""))
    return "\n".join(out)


def _visit_note(persona: dict[str, Any], visit_no: int) -> str:
    """보호자가 면회를 다니기 시작한 지 얼마 안 된 페르소나(caregiver.visits_before가 있음)만 몇 번째 면회인지 알려 준다.
    어르신이 횟수를 세는 게 아니라, 낯이 익어 가는 정도를 대화에 담으려는 것이다."""
    before = persona["caregiver"].get("visits_before")
    if before is None:
        return ""
    n = before + visit_no
    return (f"이 사람이 면회를 온 것은 이번이 {'첫' if n == 1 else n} 번째다. 너는 횟수를 정확히 세지는 않지만, "
            "얼굴이 얼마나 낯익은지는 느낀다.")


def _setting_text(persona: dict[str, Any]) -> str:
    return "\n".join(f"- {v}" for v in persona.get("setting", {}).values())


def caregiver_view(persona: dict[str, Any], learned: list[dict[str, str]] | None = None) -> dict[str, Any]:
    """보호자가 아는 것만 담은 페르소나. learned는 보호자가 앱에서 승인하거나 직접 넣은 이야기다(보호자도 이제 안다)."""
    c = persona["caregiver"]
    known = [s for s in persona["patient"]["life_story"] if s["id"] in c["knows"]]
    return {"setting": persona.get("setting", {}), "caregiver": {k: v for k, v in c.items() if k != "knows"},
            "known_story": [{"period": s["period"], "text": s["text"]} for s in known]
            + [{"period": "앱에 저장됨", "text": f"{f['title']}: {f['content']}"} for f in learned or []]}


# ── 온보딩 ──────────────────────────────────────────
class BasicInfo(BaseModel):
    name: str
    gender: Literal["male", "female"]
    birth_year: int
    birth_month: int
    birth_day: int
    condition_stage: Literal["mildCognitiveImpairment", "mildDementia", "unknown"]


class LifeAnswers(BaseModel):
    occupation: str | None
    hometown: str | None
    hobby: str | None
    family: str | None


class Onboarding(BaseModel):
    basic: BasicInfo
    answers: LifeAnswers
    photo_id: str | None = Field(description="앨범에서 넣은 사진 번호. 건너뛰면 null")
    why: str


def caregiver_onboarding(model, persona) -> Onboarding:
    album = [{"photo_id": a["id"], "what_caregiver_sees": a["truth"]} for a in persona.get("album", [])]
    return _call(model, Onboarding, "caregiver_onboarding.md", {**caregiver_view(persona), "album_preview": album})


class PhotoAnalysis(BaseModel):
    description: str
    tag_candidates: list[str]


def vlm_photo(model, truth: str) -> PhotoAnalysis:
    return _call(model, PhotoAnalysis, "vlm_photo.md", {"truth": truth})


class TagChoice(BaseModel):
    chosen: list[str]
    why: str


def caregiver_tags(model, persona, photo_truth: str, candidates: list[str]) -> TagChoice:
    return _call(model, TagChoice, "caregiver_tags.md",
                 {**caregiver_view(persona), "photo_memory": photo_truth, "tag_candidates": candidates})


# ── 카드 고르기 ──────────────────────────────────────
class Pick(BaseModel):
    position: int
    why: str


class Selection(BaseModel):
    selected: list[Pick]
    skipped: list[Pick]


def caregiver_select(model, persona, cards: list[dict[str, Any]], learned=None) -> Selection:
    return _call(model, Selection, "caregiver_select.md", {**caregiver_view(persona, learned), "cards": cards})


# ── 대화: 두 에이전트가 한 턴씩 ─────────────────────
class PatientTurn(BaseModel):
    text: str
    story_ids: list[str]
    state: Literal["talking", "tired", "asleep"] = Field(
        description="talking: 이야기할 기운이 있다. tired: 지쳐서 그만 쉬고 싶다. asleep: 눈을 감고 잠이 들었다")


class CaregiverTurn(BaseModel):
    text: str
    card_position: int | None
    add_cards: list[int]
    end: bool


def dialogue(model, persona, visit_no: int, mood: str, cards: list[dict[str, Any]], reserve: list[dict[str, Any]],
             notes: list[str], learned: list[dict[str, str]], today: str = "", heard: list[str] = (),
             max_turns: int = 44, min_turns: int = 12,
             probe: tuple[str, int] | None = None) -> tuple[list[dict], list[str], list[int]]:
    """두 에이전트가 한 턴씩 주고받는다. 각자 system 프롬프트에 자기 페르소나를 두고, 대화는 채팅 메시지로 받는다.
    보호자 차례에는 어르신 말이 user, 자기 말이 assistant다. 어르신 차례에는 그 반대다.
    today는 회차마다 다른 보호자 쪽 사정(사 온 간식, 집안 소식)이고, heard는 지난 면회들에서 어르신이 직접 한 이야기다.
    둘이 없으면 보호자는 매번 같은 간식을 들고 와 같은 질문을 한다.
    어르신이 잠들면 녹음을 끈 것으로 보고 끝낸다. 지쳐 하시면 최소 턴과 상관없이 보호자가 마무리할 수 있다.
    probe는 시험용이다. (보호자가 꺼낼 이야기, 그 턴 번호)를 주면 그 턴부터 보호자에게 그 이야기를 지금 꺼내라고 알린다.
    보호자 페르소나의 '오늘 사정'에 적어 두기만 하면 모델이 아픈 이야기를 피해 가서 따로 둔다.
    새 이야기도 카드도 없이 STALL_TURNS가 지나면 보호자에게 이야기가 끊겼다고 알린다("옆에 있을게요"만 오가는 일이 있었다).
    (턴 목록, 어르신이 꺼낸 생애 id, 면회 중 추가한 카드 번호)."""
    p = persona["patient"]
    patient_system = ((PROMPTS / "patient_turn.md").read_text()
                      .replace("{persona}", patient_persona_text(persona))
                      .replace("{life_story}", "\n".join(f"- [{s['id']}] ({s['period']}, {EMOTION.get(s['emotion'], s['emotion'])}) {s['text']}"
                                                          for s in p["life_story"]))
                      .replace("{setting}", _setting_text(persona)).replace("{mood}", mood)
                      .replace("{caregiver}", persona["caregiver"].get("relation", "보호자"))
                      .replace("{visit_note}", _visit_note(persona, visit_no)))
    calls = persona["caregiver"].get("calls_patient", "어머님")
    patient_is = persona["caregiver"].get("patient_is", "시어머니")
    in_hand = list(cards)
    left = list(reserve)
    added: list[int] = []
    turns: list[dict[str, Any]] = []
    revealed: list[str] = []
    opening = f"[진행 메모] 면회실에 막 들어왔다. {calls}께서 자리에 앉아 계신다."
    wants_to_leave = False
    patient_state = "talking"
    last_card: int | None = None
    tired_mood = mood in ("조금 피곤함", "기운 없음")
    since_progress = 0  # 어르신이 새 이야기를 꺼내거나 보호자가 카드를 꺼낸 뒤 지난 턴 수
    probe_done = probe is None

    def history(me: str) -> list[tuple[str, str]]:
        msgs: list[tuple[str, str]] = []
        for t in turns:
            msgs.append(("assistant" if t["speaker"] == me else "user", t["text"]))
        if not msgs or msgs[0][0] != "user":
            msgs.insert(0, ("user", opening))
        return msgs

    while len(turns) < max_turns:
        i = len(turns)
        if i % 2 == 0:  # 보호자
            remaining = max(0, (max_turns - i) // 2 - 1)
            system = ((PROMPTS / "caregiver_turn.md").read_text()
                      .replace("{persona}", caregiver_persona_text(persona, learned))
                      .replace("{setting}", _setting_text(persona)).replace("{cards}", _cards_text(in_hand))
                      .replace("{reserve}", _cards_text(left))
                      .replace("{notes}", "\n".join(f"- {n}" for n in notes) or "없음. 첫 면회다.")
                      .replace("{today}", today or "특별한 일은 없다.")
                      .replace("{heard}", "\n".join(f"- {h}" for h in heard) or "없음. 첫 면회다.")
                      .replace("{calls}", calls).replace("{patient_is}", patient_is))
            msgs = history("caregiver")
            note = (f"{calls}께서 잠드셨다. 깨우지 말고 조용히 인사하고 녹음을 끈다." if patient_state == "asleep" else
                    "면회 시간이 거의 다 됐다. 마무리하고 인사한다." if remaining <= 1 else
                    f"오늘 마음먹고 온 이야기를 지금 꺼낸다. 네 말투로 자연스럽게 여쭌다: {probe[0]}"
                    if not probe_done and i >= probe[1] else
                    f"{calls}께서 피곤해 하시지만 아직 막 도착했다. 바로 일어서지 말고, 곁에 앉아 대답하기 쉬운 가벼운 이야기를 조금 더 한다."
                    if patient_state == "tired" and i < TIRED_MIN_TURNS else
                    f"{calls}께서 지쳐 하신다. 붙잡지 말고 짧게 마무리해도 된다." if patient_state == "tired" else
                    "슬슬 마무리할 때다." if remaining <= 3 else
                    "이야기가 한동안 끊겼다. 같은 말을 되풀이하지 말고, 카드에서 하나 골라 네 말투로 꺼내 보거나 네 소식을 하나 전한다."
                    if since_progress >= STALL_TURNS and patient_state == "talking" else
                    "아직 면회 시간이 넉넉히 남았다. 인사하고 나가지 말고 이야기를 이어 간다." if wants_to_leave else "")
            if note:
                role, text = msgs[-1]
                msgs[-1] = (role, f"{text}\n\n[진행 메모] {note}")
            t = _call_messages(model, CaregiverTurn, "대화: 보호자", [("system", system), *msgs])
            for pos in t.add_cards:
                card = next((c for c in left if c["position"] == pos), None)
                if card:
                    left.remove(card)
                    in_hand.append(card)
                    added.append(pos)
                    emit("card_added", visit=visit_no, position=pos, card_title=card["card_title"])
            valid = {c["position"] for c in in_hand}
            # 모델이 앞 턴의 카드 번호를 맞장구 턴에도 그대로 붙여 오는 일이 잦다. 새로 꺼낸 턴에만 남긴다.
            pos = t.card_position if t.card_position in valid and t.card_position != last_card else None
            last_card = t.card_position if t.card_position in valid else None
            turn = {"speaker": "caregiver", "text": t.text, "card_position": pos}
            if not probe_done and i >= probe[1]:
                turn["probe"] = True  # 시험용 진행 메모를 받고 한 말
                probe_done = True
            since_progress = 0 if pos else since_progress + 1
            turns.append(turn)
            emit("turn", visit=visit_no, **turn)
            # 지쳐 하셔도 면회 초반(TIRED_MIN_TURNS 전)에는 끝내지 않는다. 피곤한 날 인사만 하고 나가는 일이 있었다
            if patient_state == "asleep" or (t.end and (i >= min_turns or (patient_state == "tired" and i >= TIRED_MIN_TURNS))):
                break
            wants_to_leave = t.end
        else:
            msgs = history("patient")
            if tired_mood and i >= max_turns * 0.5:  # 기운 좋은 날까지 매번 졸다 끝나지 않게, 지친 날에만
                role, text = msgs[-1]
                msgs[-1] = (role, f"{text}\n\n[진행 메모] 면회가 길어져 기운이 떨어진다.")
            t = _call_messages(model, PatientTurn, "대화: 어르신", [("system", patient_system), *msgs])
            ids = [x for x in t.story_ids if any(s["id"] == x for s in p["life_story"])]
            revealed += [x for x in ids if x not in revealed]
            patient_state = t.state
            since_progress = 0 if ids else since_progress + 1
            turn = {"speaker": "patient", "text": t.text, "card_position": None, "story_ids": ids, "state": t.state}
            turns.append(turn)
            emit("turn", visit=visit_no, **turn)
    return turns, revealed, added


# ── 소감 ────────────────────────────────────────────
class CardReview(BaseModel):
    position: int
    reaction: Reaction | None


class Review(BaseModel):
    satisfaction: int = Field(description="1~5")
    reaction: Literal["pleased", "calm", "angry", "lowEnergy", "unknown"]
    card_reviews: list[CardReview]
    note: str


def caregiver_review(model, persona, cards, turns, learned=None) -> Review:
    return _call(model, Review, "caregiver_review.md",
                 {**caregiver_view(persona, learned), "cards": cards, "transcript": turns})


# ── 보호자: 변경 사항 확인과 이야기 직접 추가 ──────────
class TopicChange(BaseModel):
    index: int
    keep: bool
    action: Action
    new_name: str | None
    new_description: str | None
    scope: str | None
    why: str


class FactChange(BaseModel):
    index: int
    keep: bool
    new_title: str | None
    new_content: str | None
    why: str


class ManualStory(BaseModel):
    title: str
    content: str


class Changes(BaseModel):
    topics: list[TopicChange]
    facts: list[FactChange]
    manual_stories: list[ManualStory]


def caregiver_changes(model, persona, report: dict, turns, facts: list[dict], topics: list[dict], learned=None) -> Changes:
    return _call(model, Changes, "caregiver_changes.md", {
        **caregiver_view(persona, learned), "report": report, "transcript": turns, "facts": facts, "topics": topics})


# ── 평가자: 저장된 이야기와 숨은 생애 대조 ─────────────
class StoryLink(BaseModel):
    index: int
    story_id: str | None
    fabricated: bool


class StoryMatch(BaseModel):
    links: list[StoryLink]


def story_match(model, persona, facts: list[dict]) -> StoryMatch:
    return _call(model, StoryMatch, "story_match.md",
                 {"life_story": persona["patient"]["life_story"], "facts": facts})
