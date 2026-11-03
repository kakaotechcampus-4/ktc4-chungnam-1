"""변경 제안 생성에서 LLM 없이 확인할 수 있는 것: #106 규칙으로 주제 조정과 이야기 후보 거르기."""

from common.visit_report import card_refs
from proposal_generation.generate import _facts, _LifeFact, _Proposals, _TopicProposal, _topics
from report_generation.tests.test_report import request


def test_topics_follow_106_rules():
    req = request("positive", "notUsed", None, "negative")
    out = _Proposals(life_fact_proposals=[], topic_proposals=[
        _TopicProposal(card="c1", suggested_action="more", reason="즐거워하심"),
        _TopicProposal(card="c1", suggested_action="less", reason="두 번째"),       # 같은 카드 두 번째는 버림
        _TopicProposal(card="c2", suggested_action="exclude", reason="안 씀"),       # notUsed에 exclude 금지
        _TopicProposal(card="c3", suggested_action="less", reason="반응 없음"),      # 무응답에 less 금지
        _TopicProposal(card="c3", suggested_action="more", reason="more는 허용"),
        _TopicProposal(card="c4", suggested_action="exclude", reason="피하심"),
        _TopicProposal(card="c9", suggested_action="more", reason="없는 카드")])
    kept = [(t.card_id, t.suggested_action) for t in _topics(out, req, card_refs(req))]
    assert kept == [("id-1", "more"), ("id-3", "more"), ("id-4", "exclude")]


def test_topic_with_blank_reason_is_dropped():
    """#106은 reason이 빈 조정이 하나라도 있으면 응답 전체를 거절함. 빈 것은 버리고 같은 카드의 다음 조정을 씀."""
    req = request("positive")
    out = _Proposals(life_fact_proposals=[], topic_proposals=[
        _TopicProposal(card="c1", suggested_action="more", reason=" "),
        _TopicProposal(card="c1", suggested_action="more", reason="즐거워하심")])
    assert [t.reason for t in _topics(out, req, card_refs(req))] == ["즐거워하심"]


def test_facts_drop_blank_and_cut_title():
    out = _Proposals(topic_proposals=[], life_fact_proposals=[
        _LifeFact(title="가" * 120, content="내용", reason="이유"), _LifeFact(title="빈 이유", content="내용", reason=" ")])
    facts = _facts(out)
    assert len(facts) == 1 and len(facts[0].title) == 100


def test_prompt_limits_painful_memory_exclude_to_that_experience():
    """#116: 아픈 기억 때문에 같은 시기나 장소의 다른 경험까지 빼지 않음. 실제 모델 동작이 아니라 프롬프트 문구만 확인함."""
    from proposal_generation.generate import PROMPT

    text = PROMPT.read_text(encoding="utf-8")
    assert "가장 가까운 카드의 주제로 exclude" not in text
    assert "그 아픈 경험을 다룬 주제에만" in text
    assert "같은 시기, 같은 장소, 같은 사람이 나오는 다른 경험의 주제에는 내지 않는다" in text
    assert "그 주제가 아닌 아픈 기억이 떠올랐다면, 그 카드에 less나 exclude를 내지 않는다" in text
