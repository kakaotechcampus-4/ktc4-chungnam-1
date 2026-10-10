"""PR #84 스키마에 합성 데이터를 넣고 backend와 같은 context로 조립해 도구 조회를 확인한다. 기대값은 tests/unit/seed.py 머리말의 계산이다."""

from __future__ import annotations

import json

import pytest

from card_generation._steps.research.store import ProfileStore
from card_generation._steps.research.tools import build_tools
from card_generation._versions import LATEST

FORBIDDEN = ("합성이름", "합성 증상 메모", "mildDementia", "합성 평가 메모", "승인 전 제안", "synthetic/")


def _all_tool_output(store: ProfileStore, seeded) -> str:
    calls = [
        store.get_profile(), store.list_life_facts(limit=30), store.list_photos(), store.list_topics(),
        *[store.get_topic(t) for t in seeded.topics.values()],
    ]
    return json.dumps([c.model_dump(mode="json") if hasattr(c, "model_dump") else
                       [x.model_dump(mode="json") for x in c] for c in calls], ensure_ascii=False)


# ── 접근 제한 ─────────────────────────────────────────
def test_hidden_columns_never_appear(store, seeded):
    out = _all_tool_output(store, seeded)
    for word in FORBIDDEN:
        assert word not in out, word


def test_other_profile_is_invisible(store, seeded):
    assert store.get_topic(seeded.topic_b).found is False
    assert store.get_life_facts([seeded.fact_b]) == []


def test_bad_ids_are_not_found(store):
    assert store.get_topic("not-a-uuid").found is False
    assert store.get_life_facts(["not-a-uuid"]) == []


# ── 프로필 ────────────────────────────────────────────
def test_profile(store):
    p = store.get_profile()
    assert p.age_band == "80대"
    assert p.empty_fields == ["hobby"]
    assert p.initial_details["hometown"] == "강원도 태백"
    assert p.counts.model_dump() == {"life_facts": 5, "photos": 1, "topics": 6, "visits": 4}


# ── 이야기 ────────────────────────────────────────────
def test_fact_usage_counts_only_visited_sets(store, seeded):
    facts = {f.fact_id: f for f in store.list_life_facts(limit=30).facts}
    coal, sea = facts[seeded.facts["coal"]].usage, facts[seeded.facts["sea"]].usage
    assert (coal.times_offered, coal.times_selected, coal.last_selected_visits_ago) == (2, 2, 1)
    assert (sea.times_offered, sea.times_selected, sea.last_selected_visits_ago) == (1, 1, 3)
    assert facts[seeded.facts["market"]].from_visit is True


def test_least_used_order(store, seeded):
    order = [f.fact_id for f in store.list_life_facts(order="least_used", limit=30).facts]
    f = seeded.facts
    assert order == [f["song"], f["wedding"], f["market"], f["sea"], f["coal"]]


def test_newest_and_paging(store, seeded):
    page = store.list_life_facts(order="newest", offset=1, limit=2)
    assert page.total == 5 and page.offset == 1
    assert [x.fact_id for x in page.facts] == [seeded.facts["wedding"], seeded.facts["song"]]


def test_page_limit_is_clamped(store):
    assert len(store.list_life_facts(limit=1000).facts) == 5


# ── 사진 ──────────────────────────────────────────────
def test_only_completed_photos(store, seeded):
    page = store.list_photos()
    assert page.total == 1 and page.photos[0].photo_id == seeded.photos["beach"]


# ── 주제 ──────────────────────────────────────────────
def test_topic_scores_and_excluded(store, seeded):
    topics = {t.topic_id: t for t in store.list_topics().topics}
    t = seeded.topics
    expected = {"coal": (False, 1.19), "sea": (False, -0.343), "home": (False, -1.0),
                "market": (True, 0.0), "song": (False, 0.0), "gone": (False, 0.0)}
    for key, (excluded, score) in expected.items():
        assert (topics[t[key]].excluded, topics[t[key]].score) == (excluded, pytest.approx(score)), key


def test_topic_usage(store, seeded):
    topics = {t.topic_id: t for t in store.list_topics().topics}
    coal = topics[seeded.topics["coal"]]
    assert (coal.times_offered, coal.times_selected, coal.last_selected_visits_ago) == (3, 3, 1)
    gone = topics[seeded.topics["gone"]]
    assert (gone.times_offered, gone.times_selected, gone.last_selected_visits_ago) == (1, 0, None)


def test_get_topic_detail(store, seeded):
    d = store.get_topic(seeded.topics["coal"])
    assert [(x.action, x.visits_ago) for x in d.decisions] == [("more", 2), ("more", 1)]
    assert [c.visits_ago for c in d.cards] == [1, 2, 3]
    assert d.evidence[0].text == "탄광 동료들: 태백 탄광에서 일할 때 동료들과 도시락을 나눠 먹으며 지내셨다."
    assert d.evidence_deleted is False


def test_get_topic_field_evidence_and_unvisited_card(store, seeded):
    home = store.get_topic(seeded.topics["home"])
    assert home.evidence[0].text == "고향: 강원도 태백"
    sea = store.get_topic(seeded.topics["sea"])
    assert [c.visits_ago for c in sea.cards] == [3]  # 면회에 쓰인 묶음의 카드만 context에 들어옴(#99 4-1 처리)


def test_get_topic_deleted_evidence(store, seeded):
    gone = store.get_topic(seeded.topics["gone"])
    assert gone.evidence_deleted is True and gone.evidence[0].text is None


# ── LangChain 도구 ────────────────────────────────────
def test_tools_do_not_take_profile_id(store):
    tools = build_tools(store)
    assert [t.name for t in tools] == ["get_profile", "list_life_facts", "get_life_facts", "list_photos",
                                       "list_topics", "get_topic"]
    for t in tools:
        assert "profile" not in json.dumps(t.args), t.name


def test_tools_show_aliases_not_uuids(store, seeded):
    import re
    tools = {t.name: t for t in build_tools(store)}
    outputs = [tools["list_topics"].invoke({"offset": 0, "limit": 50}),
               tools["list_life_facts"].invoke({"order": "oldest", "offset": 0, "limit": 30}),
               tools["list_photos"].invoke({"offset": 0, "limit": 30})]
    a = store.aliases()
    outputs += [tools["get_topic"].invoke({"topic_id": a.alias(t)}) for t in seeded.topics.values()]
    for out in outputs:
        assert not re.search(r"[0-9a-f]{8}-[0-9a-f]{4}-", out), out[:200]
    topics = json.loads(outputs[0])["topics"]
    assert [t["topic_id"] for t in topics] == [f"t{i}" for i in range(1, 7)]


def test_tool_takes_aliases_and_hides_deleted_evidence(store, seeded):
    tools = {t.name: t for t in build_tools(store)}
    a = store.aliases()
    coal = json.loads(tools["get_topic"].invoke({"topic_id": a.alias(seeded.topics["coal"])}))
    assert coal["topic"]["excluded"] is False and coal["topic"]["score"] == pytest.approx(1.19)
    assert coal["evidence"][0]["ref"] == {"factId": a.alias(seeded.facts["coal"])}
    gone = json.loads(tools["get_topic"].invoke({"topic_id": a.alias(seeded.topics["gone"])}))
    assert gone["evidence"][0]["ref"] == {"factId": "지워짐"}
    facts = json.loads(tools["get_life_facts"].invoke({"fact_ids": [a.alias(seeded.facts["sea"]), "f99"]}))
    assert [f["title"] for f in facts] == ["고기잡이"]
    assert json.loads(tools["get_topic"].invoke({"topic_id": "t99"}))["found"] is False


def test_last_offered_counts_unselected_cards(store, seeded):
    topics = {t.topic_id: t for t in store.all_topics()}
    gone = topics[seeded.topics["gone"]]  # 면회 0번 전 묶음에 있었지만 고르지 않음
    assert (gone.last_selected_visits_ago, gone.last_offered_visits_ago) == (None, 0)


def test_submission_checks_aliases_and_code_fills_uuids(store, seeded):
    from card_generation._steps.research.agent import _resolve_ids, _submission_model
    from card_generation._steps.research.candidates import CardCandidate, Evidence

    a = store.aliases()
    Model = _submission_model(store, LATEST)

    def cand(i, link=None, fact=None):
        return CardCandidate(linked_topic_id=link, new_topic_title=None if link else f"새{i}",
                             new_topic_description=None if link else "설명", card_title=f"c{i}", angle="장면",
                             kind="personal" if fact else "general",
                             evidence=[Evidence(fact_id=fact, photo_id=None, field=None)] if fact else [],
                             discover_field=None, reason="이유")

    good = [cand(0, link=a.alias(seeded.topics["coal"]), fact=a.alias(seeded.facts["coal"]))] + \
           [cand(i) for i in range(1, 16)]
    sub = Model(candidates=good)
    resolved = _resolve_ids(store, sub.candidates)
    assert resolved[0].linked_topic_id == seeded.topics["coal"]
    assert resolved[0].evidence[0].fact_id == seeded.facts["coal"]
    with pytest.raises(ValueError, match="t99는 없는 주제"):
        Model(candidates=[cand(0, link="t99")] + [cand(i) for i in range(1, 16)])
    with pytest.raises(ValueError, match="없는 이야기"):
        Model(candidates=[cand(0, link=a.alias(seeded.topics["coal"]), fact=seeded.facts["coal"])] +
                         [cand(i) for i in range(1, 16)])  # UUID를 그대로 적으면 거부


def test_refill_request_uses_aliases_and_lists_merges(store, seeded):
    from card_generation._steps.match import Matched, MatchOutcome, _NewTopic
    from card_generation._steps.research.candidates import CardCandidate
    from card_generation.generate import _refill_request

    def cand(t):
        return CardCandidate(linked_topic_id=None, new_topic_title=t, new_topic_description="d", card_title=t,
                             angle="a", kind="general", evidence=[], discover_field=None, reason="r")

    coal = seeded.topics["coal"]
    kept = [Matched(1, cand("도시락"), coal, None, "", None), Matched(2, cand("동료"), coal, None, "", None),
            Matched(3, cand("노래"), None, "n1", "", None)]
    out = MatchOutcome(kept=kept, dropped=[{"no": 4, "card_title": "장터", "reason": "excluded 주제 '장터 구경'"}],
                       new_topics={"n1": _NewTopic(new_key="n1", title="옛 노래", description="d")})
    text = _refill_request(store, out, 12)
    assert "서로 다른 주제가 2개뿐" in text
    assert f"1번 도시락, 2번 동료 → {store.aliases().alias(coal)} '탄광 시절'" in text
    assert "4번 장터" in text and coal not in text
