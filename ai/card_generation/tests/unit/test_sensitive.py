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


def test_v2_is_latest_and_v1_is_kept():
    assert LATEST is VERSIONS[2]
    assert 1 in VERSIONS   # backend가 2판으로 옮기기 전까지 1판을 지우지 않음


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
