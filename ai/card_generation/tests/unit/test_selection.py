import random

import pytest

from card_generation._steps.match import Matched, MatchOutcome
from card_generation._steps.research.candidates import CardCandidate, CardCandidateSubmission, submission_problems
from card_generation._steps.research.tools import TopicView
from card_generation._steps.select import SelectionFailed, select_cards
from card_generation._versions import LATEST, SelectionRules

RULES = LATEST.selection


def _cand(title: str, link: str | None = None, new: str | None = None, kind: str = "general") -> CardCandidate:
    return CardCandidate(linked_topic_id=link, new_topic_title=new, new_topic_description="설명" if new else None,
                         card_title=title, angle="장면", kind=kind, evidence=[], discover_field=None, reason="이유")


def _topic(tid: str, score: float = 0.0) -> TopicView:
    return TopicView(topic_id=tid, title=tid, description="d", excluded=False, score=score, times_offered=0,
                     times_selected=0, last_selected_visits_ago=None)


def _m(no: int, topic_id: str | None = None, new_key: str | None = None) -> Matched:
    return Matched(no=no, candidate=_cand(f"카드{no}"), topic_id=topic_id, new_key=new_key, reason="", agent_topic_id=None)


def test_new_reserved_existing_drawn_and_interleaved():
    topics = [_topic(f"t{i}", score=1.0) for i in range(8)]
    kept = [_m(i + 1, f"t{i}") for i in range(8)] + [_m(9, "t3")]
    kept += [_m(10 + i, new_key=f"n{i}") for i in range(6)]
    sel = select_cards(MatchOutcome(kept=kept), topics, RULES, random.Random(1))
    buckets = [p.bucket for p in sel.picked]
    # 새 이야기 5장을 먼저 잡고, 남은 7자리는 기존 주제 8개에서 뽑는다. 위치는 기존·새 이야기를 번갈아 놓는다
    assert buckets == ["existing", "new"] * 5 + ["existing", "existing"]
    reasons = {d["no"]: d["reason"] for d in sel.dropped}
    assert reasons[9] == "같은 주제의 4번 후보가 먼저 있음"
    assert reasons[15] == "12장이 다 참"   # 새 이야기 6번째는 기존 주제가 남아 있으면 들어가지 못함
    assert len(sel.picked) == 12 and len(sel.dropped) == 3


def test_new_stories_fill_when_existing_runs_short():
    kept = [_m(1, "t0")] + [_m(2 + i, new_key=f"n{i}") for i in range(11)]
    sel = select_cards(MatchOutcome(kept=kept), [_topic("t0")], RULES)
    assert [p.bucket for p in sel.picked].count("new") == 11
    assert sel.picked[-1].reason == "새 이야기(남은 자리)"


def test_higher_score_is_drawn_more_often():
    """한 자리를 점수 2인 주제 하나와 점수 0인 주제 넷이 다툰다. 뽑힐 확률은 e²/(e²+4) ≈ 0.65."""
    topics = [_topic("hi", score=2.0)] + [_topic(f"r{i}") for i in range(4)]
    kept = [_m(1, "hi")] + [_m(2 + i, f"r{i}") for i in range(4)]
    rules = SelectionRules(card_count=1, min_new=0, temperature=1.0)
    rng = random.Random(0)
    wins = sum(select_cards(MatchOutcome(kept=kept), topics, rules, rng).picked[0].matched.topic_id == "hi"
               for _ in range(2000))
    assert 0.61 < wins / 2000 < 0.69
    cold = SelectionRules(card_count=1, min_new=0, temperature=0.05)
    assert all(select_cards(MatchOutcome(kept=kept), topics, cold, rng).picked[0].matched.topic_id == "hi"
               for _ in range(50))


def test_low_score_topic_can_still_be_drawn():
    """less를 눌러 점수가 음수인 주제도 추첨에 들어간다."""
    topics = [_topic("low", score=-1.0), _topic("zero")]
    kept = [_m(1, "low"), _m(2, "zero")]
    rules = SelectionRules(card_count=1, min_new=0, temperature=1.0)
    rng = random.Random(3)
    picks = [select_cards(MatchOutcome(kept=kept), topics, rules, rng).picked[0] for _ in range(2000)]
    low = [p for p in picks if p.matched.topic_id == "low"]
    assert 0.23 < len(low) / 2000 < 0.31   # e^-1 / (e^-1 + 1) ≈ 0.27
    assert low[0].reason.startswith("기존 주제. 점수 -1.00")


def test_same_seed_same_draw():
    topics = [_topic(f"t{i}", score=i / 10) for i in range(10)]
    kept = [_m(i + 1, f"t{i}") for i in range(10)]
    rules = SelectionRules(card_count=4, min_new=0, temperature=1.0)
    runs = [[p.matched.topic_id for p in select_cards(MatchOutcome(kept=kept), topics, rules, random.Random(7)).picked]
            for _ in range(2)]
    assert runs[0] == runs[1]
    assert "뽑힐 확률" in select_cards(MatchOutcome(kept=kept), topics, rules, random.Random(7)).picked[0].reason


def test_not_enough_topics_fails():
    kept = [_m(i + 1, new_key=f"n{i}") for i in range(11)]
    with pytest.raises(SelectionFailed):
        select_cards(MatchOutcome(kept=kept), [], RULES)


def test_rules_are_adjustable():
    kept = [_m(i + 1, new_key=f"n{i}") for i in range(3)]
    assert len(select_cards(MatchOutcome(kept=kept), [], SelectionRules(card_count=3, min_new=5, temperature=1.0)).picked) == 3


# ── 제출 검증(Pydantic) ───────────────────────────────
def _sub(cands):
    return CardCandidateSubmission.model_construct(candidates=cands)


def test_submission_needs_enough_distinct_topics():
    cands = [_cand(f"c{i}", new=f"주제{i % 10}") for i in range(20)]
    assert any("서로 다른 주제가 10개" in p for p in submission_problems(_sub(cands), LATEST))


def test_submission_limits_per_topic_and_shape():
    cands = [_cand(f"c{i}", new=f"주제{i}") for i in range(14)] + [_cand(f"x{i}", link="t1") for i in range(4)]
    cands.append(_cand("빈 것"))
    problems = submission_problems(_sub(cands), LATEST)
    assert any("3개를 넘는다: t1" in p for p in problems)
    assert any(p.startswith("19번: 기존 주제에 연결하거나") for p in problems)


def test_submission_rejects_mixed_evidence_and_long_title():
    from card_generation._steps.research.candidates import Evidence
    mixed = _cand("섞임", new="주제x", kind="personal").model_copy(update={"evidence": [
        Evidence(fact_id="f1", photo_id=None, field=None), Evidence(fact_id=None, photo_id=None, field="hobby")]})
    long = _cand("가" * 101, new="주제y")
    problems = submission_problems(_sub([mixed, long]), LATEST)
    assert any(p.startswith("1번: evidence는 한 종류로만") for p in problems)
    assert any(p.startswith("2번: 카드 제목과 새 주제 제목은 100자") for p in problems)


def test_submission_needs_new_stories():
    cands = [_cand(f"c{i}", link=f"t{i}") for i in range(12)] + [_cand(f"n{i}", new=f"새{i}") for i in range(4)]
    assert any("새 주제(기존 주제에 연결하지 않은 이야기)가 4개" in p for p in submission_problems(_sub(cands), LATEST))
