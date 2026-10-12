from card_generation._steps.match import _apply_match, _Assignment, _MatchResult, _NewTopic
from card_generation._steps.research.candidates import CardCandidate
from card_generation._steps.research.tools import TopicView


def _topic(tid: str, excluded: bool = False, score: float = 0.0) -> TopicView:
    return TopicView(topic_id=tid, title=f"주제 {tid}", description="설명", excluded=excluded, score=score,
                     times_offered=0, times_selected=0, last_selected_visits_ago=None)


def _cand(title: str, link: str | None = None) -> CardCandidate:
    return CardCandidate(linked_topic_id=link, new_topic_title=None if link else title,
                         new_topic_description=None if link else "설명", card_title=title, angle="장면",
                         kind="general", evidence=[], discover_field=None, reason="이유")


TOPICS = [_topic("t-ok"), _topic("t-ex", excluded=True), _topic("t-low", score=-1.0)]


def _a(no: int, topic_id: str | None = None, new_key: str | None = None) -> _Assignment:
    return _Assignment(candidate_id=f"c{no}", topic_id=topic_id, new_key=new_key, reason="판정")


def test_new_candidates_grouped_by_key():
    cands = [_cand("한복 색"), _cand("재봉 도구"), _cand("겨울 아랫목")]
    result = _MatchResult(assignments=[_a(1, new_key="n1"), _a(2, new_key="n1"), _a(3, new_key="n2")],
                         new_topics=[_NewTopic(new_key="n1", title="재봉 일", description="d"),
                                     _NewTopic(new_key="n2", title="겨울", description="d")])
    out = _apply_match(cands, TOPICS, result)
    assert [m.new_key for m in out.kept] == ["n1", "n1", "n2"]
    assert set(out.new_topics) == {"n1", "n2"}


def test_only_excluded_dropped_even_if_agent_said_new():
    """점수가 낮은 주제는 빼지 않고 선정의 추첨에 맡긴다. 확실히 빼는 건 excluded뿐이다."""
    cands = [_cand("장터 국밥"), _cand("학교"), _cand("노래", link="t-ok")]
    result = _MatchResult(assignments=[_a(1, "t-ex"), _a(2, "t-low"), _a(3, "t-ok")], new_topics=[])
    out = _apply_match(cands, TOPICS, result)
    assert [m.no for m in out.kept] == [2, 3]
    assert [d["no"] for d in out.dropped] == [1]
    assert "excluded" in out.dropped[0]["reason"]


def test_unverified_candidates_dropped():
    cands = [_cand("a"), _cand("b"), _cand("c"), _cand("d")]
    result = _MatchResult(assignments=[_a(1, "t-unknown"), _a(2, "t-ok", "n1"), _a(3, new_key="n9")],
                         new_topics=[])
    out = _apply_match(cands, TOPICS, result)
    assert out.kept == []
    reasons = [d["reason"] for d in out.dropped]
    assert reasons[0] == "판정이 없는 주제를 가리킴"
    assert reasons[1] == "판정이 기존 주제와 새 주제 중 하나를 고르지 않음"
    assert "n9" in reasons[2]
    assert reasons[3] == "판정 결과가 없음"


def test_agent_link_kept_for_comparison():
    out = _apply_match([_cand("x", link="t-ok")], TOPICS,
                      _MatchResult(assignments=[_a(1, new_key="n1")],
                                  new_topics=[_NewTopic(new_key="n1", title="새", description="d")]))
    assert out.kept[0].agent_topic_id == "t-ok" and out.kept[0].topic_id is None
