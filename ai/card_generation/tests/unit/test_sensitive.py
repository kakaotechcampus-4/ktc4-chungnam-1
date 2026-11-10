"""아픈 경험 카드(sensitive) 검증. 실제 LLM과 DB 없이 2판 프롬프트 문구, 제출 검사, 결과 전달만 봄(PM 결정, 2026-11-09)."""

import pytest

from card_generation import generate as gen
from card_generation._steps.match import Matched, MatchOutcome, _NewTopic
from card_generation._steps.research.agent import AgentRun
from card_generation._steps.research.candidates import (
    CardCandidate,
    CardCandidateSubmission,
    Evidence,
    submission_problems,
)
from card_generation._steps.select import Picked, Selection
from card_generation._steps.write import _CardText, _WritingResult
from card_generation._versions import LATEST, VERSIONS
from card_generation.contract import CardContext, GenerationRequest


def _cand(no: int, kind: str = "general", sensitive: bool = False, fact: str | None = None,
          photo: str | None = None) -> CardCandidate:
    evidence = [Evidence(fact_id=fact, photo_id=None, field=None)] if fact else \
        [Evidence(fact_id=None, photo_id=photo, field=None)] if photo else []
    return CardCandidate(linked_topic_id=None, new_topic_title=f"새 주제 {no}", new_topic_description="설명",
                         card_title=f"카드 {no}", angle="장면", kind=kind, evidence=evidence,
                         discover_field=None, sensitive=sensitive, reason="이유")


def test_v3_is_latest_and_older_versions_are_kept():
    assert LATEST is VERSIONS[3]
    assert {1, 2} <= set(VERSIONS)   # backend가 새 버전으로 옮기기 전까지 이전 버전을 지우지 않음(backend 기본은 v2)


def test_v3_changes_only_general_description():
    """v3는 조사 프롬프트와 같은 이야기 기준의 general 설명만 바꿈. 판정과 문안 프롬프트, 정해 둔 값은 v2와 같음."""
    v2, v3 = VERSIONS[2], VERSIONS[3]
    assert v3.sensitive_cards and v3.selection == v2.selection and v3.decay == v2.decay
    for name in ("match.md", "writing_topics.md"):
        assert (v3.prompts / name).read_text(encoding="utf-8") == (v2.prompts / name).read_text(encoding="utf-8")
    assert "연령대에 맞는 보편적인 옛 추억" in v2.agent_prompt()
    assert "연령대에 맞는 보편적인 옛 추억" not in v3.agent_prompt()
    assert "모르는 생활상을 전제하지 않는다" in v3.agent_prompt()


def test_v2_agent_prompt_allows_stored_painful_stories_as_sensitive():
    v1, v2 = VERSIONS[1].agent_prompt(), VERSIONS[2].agent_prompt()
    assert "아픈 경험은 주제로 삼지 않는다" in v1   # 1판은 그대로
    assert "아픈 경험은 주제로 삼지 않는다" not in v2
    assert "쌓아온 이야기나 초기 정보에 나온 것만 personal 후보로 낼 수 있다" in v2
    assert "sensitive를 true로 한다" in v2
    # 최근 기억을 시험하는 카드는 그대로 막음
    assert "최근 일을 기억하는지 시험하는 주제는 내지 않는다" in v2


def test_v2_prompts_add_no_middle_dot():
    for name in ("agent.md", "match.md", "same_story.md", "writing_topics.md"):
        assert "\u00b7" not in (VERSIONS[2].prompts / name).read_text(encoding="utf-8"), name


def test_sensitive_candidate_needs_stored_story_or_profile_evidence():
    ok = _cand(1, kind="personal", sensitive=True, fact="f1")
    guessed = _cand(2, sensitive=True)                     # general로 아픈 경험을 꺼냄
    plain = _cand(3)
    from_photo = _cand(4, kind="personal", sensitive=True, photo="p1")   # personal이지만 사진 설명만 근거
    problems = submission_problems(
        CardCandidateSubmission.model_construct(candidates=[ok, guessed, plain, from_photo]), LATEST)
    assert any(p.startswith("2번: 아픈 경험(sensitive) 후보는") for p in problems)
    assert any(p.startswith("4번: 아픈 경험(sensitive) 후보는") for p in problems)
    assert not any(p.startswith(("1번: 아픈 경험", "3번: 아픈 경험")) for p in problems)


def test_v1_does_not_check_sensitive():
    """1판(지금 운영)은 아픈 경험 카드를 내지 않으므로 sensitive 때문에 제출을 다시 받지 않음."""
    assert not VERSIONS[1].sensitive_cards and VERSIONS[2].sensitive_cards
    guessed = _cand(1, sensitive=True)
    problems = submission_problems(CardCandidateSubmission.model_construct(candidates=[guessed]), VERSIONS[1])
    assert not any("아픈 경험" in p for p in problems)


@pytest.mark.parametrize("prompt_version,expected", [
    (2, [False, True] + [False] * 10),
    (1, [False] * 12),   # 1판은 모델이 true를 적어도 내보내지 않음
])
def test_sensitive_reaches_the_card_result(monkeypatch, prompt_version, expected):
    """2판에서는 에이전트 후보의 sensitive가 결과 카드(backend 저장용 JSON의 sensitive)까지 그대로 감."""
    cands = [_cand(i, kind="personal" if i == 2 else "general", sensitive=i == 2,
                   fact="f-uuid" if i == 2 else None) for i in range(1, 13)]
    picked = [Picked(Matched(no=i, candidate=c, topic_id=None, new_key=f"n{i}", reason="판정", agent_topic_id=None),
                     "new", "새 이야기") for i, c in enumerate(cands, 1)]
    match = MatchOutcome(kept=[p.matched for p in picked],
                         new_topics={f"n{i}": _NewTopic(new_key=f"n{i}", title=f"새 주제 {i}", description="설명")
                                     for i in range(1, 13)})
    rec = gen.Recommendation(agent=AgentRun(candidates=cands), match=match, selection=Selection(picked=picked))

    def write(model, profile, cards, prompt, deadline):
        return _WritingResult(cards=[_CardText(position=c["position"], description="설명", primary_question="어떠셨어요?",
                                               follow_up_questions=["누구와요?", "어디서요?", "그다음은요?"])
                                     for c in cards]), []

    monkeypatch.setattr(gen, "chat_model", lambda config: object())
    monkeypatch.setattr(gen, "recommend", lambda *args, **kwargs: rec)
    monkeypatch.setattr(gen, "write_cards", write)
    request = GenerationRequest(model="gpt-5.6-luna", prompt_version=prompt_version,
                                context=CardContext.model_validate({"ageRange": "80s", "profileFacts": {}}))
    result = gen.generate_cards(request, api_key="synthetic", time_limit=30, seed=1)
    assert [c.sensitive for c in result.cards] == expected
    cards = result.model_dump(mode="json", by_alias=True)["cards"]
    assert [c["sensitive"] for c in cards] == expected


# ── 아픈 기억으로 표시된 이야기(PM 결정, 2026-11-10) ──────────────────────
# backend가 lifeFacts[].sensitive로 넘기는 표시. 2판은 이 이야기를 근거로 한 카드를 모델이 무엇을 적든 아픈 경험 카드로 냄.
_PAINFUL = "00000000-0000-4000-8000-000000000111"
_PLAIN = "00000000-0000-4000-8000-000000000112"


def _context_with_painful_story() -> CardContext:
    return CardContext.model_validate({
        "ageRange": "80s", "profileFacts": {},
        "lifeFacts": [
            {"factId": _PAINFUL, "title": "남편분과 사별", "content": "합성 내용", "source": "visit", "sensitive": True},
            {"factId": _PLAIN, "title": "장터 구경", "content": "합성 내용", "source": "caregiver"}]})


def test_life_fact_sensitive_is_optional_and_defaults_to_false():
    """backend가 이 필드를 보내기 전 형식도 받음(받지 않는 키는 거절하는 형식이라 필드를 둠)."""
    facts = _context_with_painful_story().life_facts
    assert [f.sensitive for f in facts] == [True, False]
    assert CardContext.model_validate({"ageRange": "80s", "profileFacts": {}}).life_facts == []


def test_story_tools_show_the_mark_only_in_versions_that_make_sensitive_cards():
    """2판 도구 결과에는 sensitive가 붙고, 1판 도구 결과는 이 키 없이 예전과 같음."""
    import json

    from card_generation._steps.research.store import ProfileStore
    from card_generation._steps.research.tools import build_tools

    def facts_seen(version):
        store = ProfileStore(_context_with_painful_story(), version.decay, show_sensitive=version.sensitive_cards)
        tools = {t.name: t for t in build_tools(store)}
        listed = json.loads(tools["list_life_facts"].invoke({"order": "oldest"}))["facts"]
        fetched = json.loads(tools["get_life_facts"].invoke({"fact_ids": ["f1", "f2"]}))
        assert listed == fetched
        return store, listed

    store, v2 = facts_seen(VERSIONS[2])
    assert [(f["fact_id"], f["sensitive"]) for f in v2] == [("f1", True), ("f2", False)]
    assert store.sensitive_fact_ids() == {_PAINFUL}
    _, v1 = facts_seen(VERSIONS[1])
    assert all("sensitive" not in f for f in v1)
    assert set(v1[0]) == {"fact_id", "title", "content", "from_visit", "usage"}


def test_v2_agent_prompt_keeps_marked_stories_and_points_to_gentle_cards():
    v1, v2 = VERSIONS[1].agent_prompt(), VERSIONS[2].agent_prompt()
    assert "아프다는 이유로 피하지 말고 다른 이야기처럼 후보로 낸다" in v2
    assert "이 이야기를 근거로 한 후보는 sensitive를 true로 한다" in v2
    assert "그분과의 좋았던 기억이나 그 시절의 일상으로 잡는다" in v2
    assert "아프다는 이유로 피하지 말고" not in v1   # 1판은 그대로
    writing = VERSIONS[2].writing_prompt()
    assert "sensitive(아픈 경험을 다루는 카드인지)" in writing
    assert "근거 글에 아픈 일이 있다는 이유로 카드를 빼거나 바꾸지 않는다" in writing
    assert VERSIONS[1].writing_prompt() == (VERSIONS[1].prompts / "writing_topics.md").read_text(encoding="utf-8")


def _generate_with(monkeypatch, prompt_version, cands):
    """후보 12장을 그대로 고른 것으로 두고 generate_cards를 돌림. 문안 단계에 넘긴 카드 입력도 돌려줌."""
    picked = [Picked(Matched(no=i, candidate=c, topic_id=None, new_key=f"n{i}", reason="판정", agent_topic_id=None),
                     "new", "새 이야기") for i, c in enumerate(cands, 1)]
    match = MatchOutcome(kept=[p.matched for p in picked],
                         new_topics={f"n{i}": _NewTopic(new_key=f"n{i}", title=f"새 주제 {i}", description="설명")
                                     for i in range(1, 13)})
    rec = gen.Recommendation(agent=AgentRun(candidates=cands), match=match, selection=Selection(picked=picked))
    written = []

    def write(model, profile, cards, prompt, deadline):
        written.extend(cards)
        return _WritingResult(cards=[_CardText(position=c["position"], description="설명", primary_question="어떠셨어요?",
                                               follow_up_questions=["누구와요?", "어디서요?", "그다음은요?"])
                                     for c in cards]), []

    monkeypatch.setattr(gen, "chat_model", lambda config: object())
    monkeypatch.setattr(gen, "recommend", lambda *args, **kwargs: rec)
    monkeypatch.setattr(gen, "write_cards", write)
    request = GenerationRequest(model="gpt-5.6-luna", prompt_version=prompt_version, context=_context_with_painful_story())
    return gen.generate_cards(request, api_key="synthetic", time_limit=30, seed=1), written


def test_v2_card_built_on_a_marked_story_is_always_sensitive(monkeypatch):
    """E2E(11/10)에서 사별 이야기로 만든 카드도 sensitive=false였음. 모델이 false로 적어도 코드가 true로 냄."""
    cands = [_cand(i) for i in range(1, 13)]
    cands[0] = _cand(1, kind="personal", fact=_PAINFUL)                    # 모델이 표시하지 않음
    cands[1] = _cand(2, kind="personal", fact=_PLAIN)                      # 아프지 않은 이야기
    cands[2] = _cand(3, kind="personal", sensitive=True, fact=_PLAIN)      # 모델이 표시함(그대로 둠)
    result, written = _generate_with(monkeypatch, 2, cands)

    assert [c.sensitive for c in result.cards] == [True, False, True] + [False] * 9
    assert [c["sensitive"] for c in written] == [True, False, True] + [False] * 9   # 문안 규칙 8이 적용되게
    assert result.log["sensitiveFromStories"] == 1
    assert result.model_dump(mode="json", by_alias=True)["cards"][0]["sensitive"] is True


def test_v1_ignores_the_story_mark(monkeypatch):
    """1판 결과와 기록은 예전과 같음."""
    cands = [_cand(i) for i in range(1, 13)]
    cands[0] = _cand(1, kind="personal", fact=_PAINFUL)
    result, written = _generate_with(monkeypatch, 1, cands)

    assert [c.sensitive for c in result.cards] == [False] * 12
    assert [c["sensitive"] for c in written] == [False] * 12
    assert "sensitiveFromStories" not in result.log
