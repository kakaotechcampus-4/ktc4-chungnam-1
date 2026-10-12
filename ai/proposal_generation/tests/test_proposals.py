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


def test_facts_drop_blank_and_cut_title():
    out = _Proposals(topic_proposals=[], life_fact_proposals=[
        _LifeFact(title="가" * 120, content="내용", reason="이유"), _LifeFact(title="빈 이유", content="내용", reason=" ")])
    facts = _facts(out)
    assert len(facts) == 1 and len(facts[0].title) == 100
