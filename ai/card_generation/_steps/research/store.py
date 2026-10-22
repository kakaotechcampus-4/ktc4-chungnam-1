"""backend가 넘긴 context를 에이전트 도구가 조회하는 형태로 바꿈. DB에 접속하지 않음.

context에는 이 프로필 정보만 있음. 이름·성별·생년월일·건강 정보·면회 평가 메모·리포트 본문·승인 전 제안은 backend가 넣지 않음.
시점은 날짜 대신 면회 몇 번 전(visits_ago, 0이 가장 최근 면회)으로 줌.

번호표(_Aliases): 모델에게 UUID 대신 t1, f3, p2를 보여 주고, 모델이 적은 번호표를 UUID로 되돌림.
모델이 36자 UUID를 베끼다 글자를 빠뜨리는 일이 시뮬레이션에서 반복돼 만듦. 번호표는 등록 순서대로 매김.

선호 점수(_topic_state): 보호자 결정(topic_feedback)을 면회 횟수 기준으로 감쇠해 더함.

    score = Σ 값(행동) × decay^(그 행동 뒤에 시작한 면회 수),  more = +1, less = -1

평균이 아니라 합. more 한 번과 다섯 번을 구분함. 날짜가 아니라 면회 횟수로 감쇠. 보호자마다 면회 간격이 다름.
PM 결정(#44, 2026-09-19): 미사용·미응답만으로 추천에서 빼거나 순위를 낮추지 않음. 보호자가 추천하지 않기를 고른 주제만 뺌.
그래서 점수에는 보호자가 승인한 결정(more·less·exclude)만 넣고 카드 반응은 넣지 않음.
exclude를 고른 주제는 점수와 상관없이 후보에서 빠짐. 나머지는 선정에서 점수를 softmax 확률로 바꿔 뽑음.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from card_generation._steps.research.tools import (
    FIELD_LABELS,
    INITIAL_FIELDS,
    Action,
    Counts,
    DecisionView,
    EvidenceText,
    LifeFactPage,
    LifeFactView,
    PastCard,
    PhotoPage,
    PhotoView,
    ProfileView,
    TopicDetail,
    TopicPage,
    TopicView,
    Usage,
)
from card_generation.contract import CardContext

_MAX_FACT_PAGE = 30
_MAX_PHOTO_PAGE = 30
_MAX_TOPIC_PAGE = 100
_MAX_FACT_IDS = 20
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_GONE = "지워짐"
_ACTION_VALUE = {"more": 1.0, "less": -1.0}


class ProfileStore:
    """backend context 하나를 감싸 에이전트 도구와 다른 단계가 쓰는 조회를 제공함.
    점수, 사용 이력, 정렬, 페이지, 번호표를 여기서 계산함.
    """
    def __init__(self, context: CardContext, decay: float) -> None:
        """decay는 판의 선호 점수 감쇠값. 면회를 최근 순으로 세워 카드 묶음(set_id)마다 면회 몇 번 전인지 미리 계산함."""
        self._ctx = context
        self._decay = decay
        visits = sorted(context.visits, key=lambda v: (v.started_at, v.session_id), reverse=True)
        self._visits_ago = {v.set_id: i for i, v in enumerate(visits) if v.set_id}
        self._starts = [v.started_at for v in context.visits]
        self._aliases: _Aliases | None = None

    # ── 도구가 부르는 조회 ──────────────────────────────
    def get_profile(self) -> ProfileView:
        """도구 get_profile. 연령대, 초기 정보 네 칸, 비어 있는 칸, 이야기·사진·주제·면회 개수."""
        details = self._initial_details()
        counts = Counts(life_facts=len(self._ctx.life_facts), photos=len(self._ctx.photos),
                        topics=len(self._ctx.topics), visits=len(self._ctx.visits))
        return ProfileView(age_band=f"{self._ctx.age_range[:-1]}대", initial_details=details,
                           empty_fields=[f for f in INITIAL_FIELDS if not details[f]], counts=counts)

    def list_life_facts(self, order: str = "least_used", offset: int = 0, limit: int = 20) -> LifeFactPage:
        """도구 list_life_facts. 이야기를 덜 다룬 순, 최신 순, 오래된 순으로 페이지 단위로 줌. 이야기마다 사용 이력을 붙임."""
        facts, usage = self._facts(), self._usage("factId")
        if order == "newest":
            facts.reverse()
        elif order == "least_used":
            def key(i_row: tuple[int, dict[str, Any]]) -> tuple[int, int, int]:
                u = usage.get(i_row[1]["fact_id"], Usage())
                # 덜 고른 것, 그다음 오래전에 고른 것(visits_ago가 큰 것), 그다음 먼저 등록된 것
                last = u.last_selected_visits_ago
                return (u.times_selected, -(last if last is not None else 10**6), i_row[0])
            facts = [row for _, row in sorted(enumerate(facts), key=key)]
        elif order != "oldest":
            raise ValueError("order는 least_used, newest, oldest 중 하나")
        offset, limit = max(0, int(offset)), _clamp(limit, 1, _MAX_FACT_PAGE)
        return LifeFactPage(total=len(facts), offset=offset,
                            facts=[self._fact_view(r, usage) for r in facts[offset:offset + limit]])

    def get_life_facts(self, fact_ids: list[str]) -> list[LifeFactView]:
        """도구 get_life_facts. ID로 이야기 원문과 사용 이력을 줌. 없는 ID는 빼고 돌려줌."""
        ids = [i for i in dict.fromkeys(fact_ids) if i][:_MAX_FACT_IDS]
        usage = self._usage("factId")
        by_id = {r["fact_id"]: r for r in self._facts()}
        return [self._fact_view(by_id[i], usage) for i in ids if i in by_id]

    def list_photos(self, offset: int = 0, limit: int = 20) -> PhotoPage:
        """도구 list_photos. 사진 설명과 사용 이력을 페이지 단위로 줌."""
        rows = self._photos()
        usage = self._usage("photoId")
        offset, limit = max(0, int(offset)), _clamp(limit, 1, _MAX_PHOTO_PAGE)
        return PhotoPage(total=len(rows), offset=offset,
                         photos=[PhotoView(photo_id=r["photo_id"], description=r["description"],
                                           usage=usage.get(r["photo_id"], Usage()))
                                 for r in rows[offset:offset + limit]])

    def list_topics(self, offset: int = 0, limit: int = 50) -> TopicPage:
        """도구 list_topics. 주제마다 점수, 제외 여부, 사용 이력을 붙여 페이지 단위로 줌."""
        views = self.all_topics()
        offset, limit = max(0, int(offset)), _clamp(limit, 1, _MAX_TOPIC_PAGE)
        return TopicPage(total=len(views), offset=offset, topics=views[offset:offset + limit])

    def get_topic(self, topic_id: str) -> TopicDetail:
        """도구 get_topic. 주제 하나의 결정 이력, 근거 글, 이 주제로 나갔던 지난 카드. 없는 주제면 found=False."""
        topic = next((t for t in self._topics() if t.topic_id == topic_id), None)
        if topic is None:
            return TopicDetail(found=False)
        details = self._initial_details()
        evidence = [EvidenceText(ref=dict(r), text=self._evidence_text(r, details)) for r in topic.evidence]
        return TopicDetail(
            found=True, topic=self._topic_view(topic, self._visited_cards()),
            decisions=[DecisionView(action=d.action, visits_ago=d.visits_since) for d in topic.decisions],
            evidence=evidence,
            evidence_deleted=bool(evidence) and all(e.text is None for e in evidence),
            cards=[PastCard(card_title=c["card_title"], primary_question=c["primary_question"],
                            visits_ago=c["visits_ago"], selected=c["selected"],
                            review_reaction=c["review_reaction"]) for c in self._visited_cards(topic_id)])

    # ── 제출 검증, 연결 판정, 선정, 문안이 부르는 조회 ──────
    def all_topics(self) -> list[TopicView]:
        """주제 전체의 TopicView. 연결 판정과 선정, 다시 찾기 글이 씀."""
        cards = self._visited_cards()
        return [self._topic_view(t, cards) for t in self._topics()]

    def evidence_texts(self, refs: list[dict[str, str]]) -> list[str | None]:
        """근거 참조의 지금 글. 없거나 지워진 근거는 None."""
        details = self._initial_details()
        return [self._evidence_text(r, details) for r in refs]

    def aliases(self) -> _Aliases:
        """모델에게 보여 줄 번호표. 한 번만 만듦."""
        if self._aliases is None:
            self._aliases = _Aliases([r["fact_id"] for r in self._facts()], [r["photo_id"] for r in self._photos()],
                                    [t.topic_id for t in self._topics()])
        return self._aliases

    def known_ids(self) -> dict[str, set[str]]:
        """제출 검증에 쓰는 이 프로필의 ID와 빈 칸."""
        details = self._initial_details()
        return {
            "facts": {r["fact_id"] for r in self._facts()},
            "photos": {r["photo_id"] for r in self._photos()},
            "topics": {t.topic_id for t in self._topics()},
            "empty_fields": {f for f in INITIAL_FIELDS if not details[f]},
        }

    # ── context 읽기 ──────────────────────────────────
    def _initial_details(self) -> dict[str, str | None]:
        """초기 정보 네 칸. 빈 문자열은 None으로 바꿈."""
        facts = self._ctx.profile_facts
        return {f: (getattr(facts, f) or None) for f in INITIAL_FIELDS}

    def _facts(self) -> list[dict[str, Any]]:
        """이야기 목록을 등록 시각 순으로. from_visit은 면회 뒤 제안을 승인해 생긴 이야기인지."""
        facts = sorted(enumerate(self._ctx.life_facts),
                       key=lambda i_f: (i_f[1].created_at is None, i_f[1].created_at or 0, i_f[0]))
        return [{"fact_id": f.fact_id, "title": f.title, "content": f.content, "from_visit": f.source == "visit"}
                for _, f in facts]

    def _photos(self) -> list[dict[str, Any]]:
        """사진 목록."""
        return [{"photo_id": p.photo_id, "description": p.description} for p in self._ctx.photos]

    def _topics(self) -> list[_Topic]:
        """주제 목록을 만든 순으로. 결정마다 그 뒤에 시작한 면회 수를 세어 _Decision으로 바꿈."""
        topics = sorted(enumerate(self._ctx.topics),
                        key=lambda i_t: (i_t[1].created_at is None, i_t[1].created_at or 0, i_t[0]))
        out = []
        for _, t in topics:
            # 결정 뒤에 시작한 면회 수만큼 감쇠
            decisions = [_Decision(f.action, sum(1 for s in self._starts if s > f.decided_at))
                         for f in sorted(t.feedback, key=lambda f: f.decided_at)]
            out.append(_Topic(t.topic_id, t.title, t.description, [dict(r) for r in t.evidence], decisions))
        return out

    def _visited_cards(self, topic_id: str | None = None) -> list[dict[str, Any]]:
        """면회에 쓰인 카드 목록을 최근 면회 순으로. topic_id를 주면 그 주제의 카드만."""
        cards = [{"card_id": c.card_id, "topic_id": c.topic_id, "card_title": c.card_title,
                  "primary_question": c.primary_question, "selected": c.selected, "review_reaction": c.review_reaction,
                  "evidence": [dict(r) for r in c.evidence], "visits_ago": self._visits_ago.get(c.set_id),
                  "position": c.position}
                 for c in self._ctx.past_cards if topic_id is None or c.topic_id == topic_id]
        cards.sort(key=lambda c: (c["visits_ago"] is None, c["visits_ago"] or 0, c["position"]))
        return cards

    # ── 내부 계산 ─────────────────────────────────────
    def _usage(self, key: str) -> dict[str, Usage]:
        """근거 키(factId, photoId)별 사용 이력. 면회에 쓰인 묶음의 카드만 셈."""
        usage: dict[str, Usage] = {}
        for card in self._visited_cards():
            if card["visits_ago"] is None:
                continue
            for ref in card["evidence"] or []:
                if key not in ref:
                    continue
                u = usage.setdefault(ref[key], Usage())
                u.times_offered += 1
                if card["selected"]:
                    u.times_selected += 1
                    if u.last_selected_visits_ago is None or card["visits_ago"] < u.last_selected_visits_ago:
                        u.last_selected_visits_ago = card["visits_ago"]
        return usage

    def _fact_view(self, row: dict[str, Any], usage: dict[str, Usage]) -> LifeFactView:
        """이야기 한 줄을 도구 결과 형식으로."""
        return LifeFactView(fact_id=row["fact_id"], title=row["title"], content=row["content"],
                            from_visit=row["from_visit"], usage=usage.get(row["fact_id"], Usage()))

    def _topic_view(self, t: _Topic, cards: list[dict[str, Any]]) -> TopicView:
        """주제 하나를 도구 결과 형식으로. 점수·제외 여부와 묶음에 들어간 횟수, 고른 횟수, 마지막 시점을 계산함."""
        score, excluded = _topic_state(t.decisions, self._decay)
        mine = [c for c in cards if c["topic_id"] == t.topic_id and c["visits_ago"] is not None]
        picked = [c["visits_ago"] for c in mine if c["selected"]]
        return TopicView(topic_id=t.topic_id, title=t.title, description=t.description, excluded=excluded,
                         score=round(score, 3), times_offered=len(mine), times_selected=len(picked),
                         last_selected_visits_ago=min(picked) if picked else None,
                         last_offered_visits_ago=min(c["visits_ago"] for c in mine) if mine else None)

    def _evidence_text(self, ref: dict[str, str], details: dict[str, str | None]) -> str | None:
        """근거 항목 하나의 지금 글. "고향: 강원도 태백", "제목: 내용", "사진: 설명" 꼴. 지워진 근거는 None."""
        if "profileField" in ref:
            text = details.get(ref["profileField"])
            return f"{FIELD_LABELS[ref['profileField']]}: {text}" if text else None
        if "factId" in ref:
            row = next((f for f in self._facts() if f["fact_id"] == ref["factId"]), None)
            return f"{row['title']}: {row['content']}" if row else None
        if "photoId" in ref:
            row = next((p for p in self._photos() if p["photo_id"] == ref["photoId"]), None)
            return f"사진: {row['description']}" if row else None
        return None


class _Aliases:
    """번호표 표. 이야기는 f, 사진은 p, 주제는 t에 등록 순서대로 번호를 붙임."""
    def __init__(self, facts: list[str], photos: list[str], topics: list[str]) -> None:
        """이야기·사진·주제 UUID 목록을 받아 양방향 표를 만듦."""
        self._to_alias: dict[str, str] = {}
        self._to_uuid: dict[str, str] = {}
        for prefix, ids in (("f", facts), ("p", photos), ("t", topics)):
            for i, uid in enumerate(ids, 1):
                self._to_alias[uid] = f"{prefix}{i}"
                self._to_uuid[f"{prefix}{i}"] = uid

    def alias(self, uid: str) -> str:
        """UUID를 번호표로. 이 프로필에 없는 UUID는 "지워짐"."""
        return self._to_alias.get(uid, _GONE)

    def uuid(self, alias: str | None) -> str | None:
        """모르는 번호표는 그대로 돌려줌. 뒤의 조회가 '없음'으로 답함."""
        if alias is None:
            return None
        return self._to_uuid.get(alias.strip(), alias)

    def known(self, alias: str | None, prefix: str) -> bool:
        """번호표가 이 프로필에 있고 접두어(t, f, p)도 맞는지. 제출 검사에서 씀."""
        return alias is not None and alias.strip().startswith(prefix) and alias.strip() in self._to_uuid

    def hide(self, value: Any) -> Any:
        """도구 결과 안의 UUID를 번호표로 바꿈. 이 프로필에 없는 UUID(지워진 근거 등)는 '지워짐'."""
        if isinstance(value, dict):
            return {k: self.hide(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self.hide(v) for v in value]
        if isinstance(value, str) and _UUID_RE.match(value):
            return self.alias(value)
        return value


@dataclass(frozen=True)
class _Decision:
    """보호자 결정 하나. visits_since는 이 결정 뒤에 시작한 면회 수(감쇠 지수)."""
    action: Action
    visits_since: int  # 이 행동을 정한 뒤 시작한 면회 수


@dataclass
class _Topic:
    """context의 주제 하나를 점수 계산에 쓰기 좋게 바꾼 것."""
    topic_id: str
    title: str
    description: str
    evidence: list[dict[str, str]]
    decisions: list[_Decision]


def _topic_state(decisions: list[_Decision], decay: float) -> tuple[float, bool]:
    """(점수, 제외 여부). 제외된 주제의 점수는 0."""
    if any(d.action == "exclude" for d in decisions):
        return 0.0, True
    return sum(_ACTION_VALUE.get(d.action, 0.0) * decay ** d.visits_since for d in decisions), False


def _clamp(value: int, low: int, high: int) -> int:
    """value를 low~high 안으로 자름. 도구 인자의 페이지 크기 상한에 씀."""
    return max(low, min(int(value), high))
