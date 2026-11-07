"""사진 속 대상을 맞히게 하는 질문 검사 (실제 LLM 미호출)."""

import pytest

from card_generation._steps.write import _CardText, _problems, _WritingResult


def _with_follow_up(question: str) -> _WritingResult:
    return _WritingResult(cards=[_CardText(position=1, description="설명", primary_question="이 사진은 어디서 찍으셨어요?",
                                           follow_up_questions=["누구랑 가셨어요?", "그때는 어땠어요?", question])])


@pytest.mark.parametrize("question", [
    "사진 속 모종은 무엇을 심은 모습인가요?",   # 2026-11-03 실제 모델 점검 카드 B 출력
    "사진 속 사람은 누구예요?",
    "사진에 있는 분은 누구세요?",
    "이분이 누군지 아세요?",
    "여기가 어딘지 아시겠어요?",
    "이게 뭔지 아세요?",
])
def test_photo_quiz_question_is_sent_back(question):
    problems = _problems(_with_follow_up(question), [1])
    assert len(problems) == 1 and "맞히게" in problems[0]


@pytest.mark.parametrize("question", [
    "이 사진은 어디서 찍으셨어요?",
    "사진 속 텃밭에서는 무엇을 기르셨어요?",
    "사진 속 밭일은 누구랑 하셨어요?",
    "사진 속 아이들과 무엇을 하며 노셨어요?",
    "그 사진을 찍을 때는 누가 함께 있었어요?",
    "이런 장터 풍경을 보시면 어떤 일이 떠오르세요?",
    "어떤 음식인지 들려주실 수 있어요?",
])
def test_open_photo_question_passes(question):
    assert _problems(_with_follow_up(question), [1]) == []


def test_writing_prompt_forbids_photo_quiz():
    """실제 모델 동작이 아니라 v1 문안 프롬프트에 규칙 문장이 있는지만 확인함."""
    from card_generation._versions import VERSIONS

    text = VERSIONS[1].writing_prompt()
    assert "사진 속 사물, 사람, 장소를 알아맞히게 하지 않는다" in text
    assert "경험과 느낌을 여쭙는다" in text
