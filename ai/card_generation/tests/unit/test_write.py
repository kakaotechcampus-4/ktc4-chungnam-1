"""문안 검사 (실제 LLM 미호출)."""

from card_generation._steps.write import _CardText, _problems, _WritingResult

import pytest
from card_generation._steps import write


def _text(pos: int, description: str = "설명") -> _CardText:
    return _CardText(position=pos, description=description, primary_question="어떤 노래였어요?",
                     follow_up_questions=["누구랑 불렀어요?", "어디서 불렀어요?", "또 부르고 싶으세요?"])


def test_blank_description_is_sent_back():
    result = _WritingResult(cards=[_text(1), _text(2, description=" ")])
    assert _problems(result, [1, 2]) == ["2번: 설명이 비어 있다."]


@pytest.mark.parametrize("description", ["이 카드는 치매를 치료합니다.", "이 카드에는 치료 효과가 있습니다.", "치료 효과가 있어요."])
def test_description_rejects_direct_medical_effect_claim(description):
    problems = _problems(_WritingResult(cards=[_text(1, description)]), [1])
    assert len(problems) == 1 and "설명" in problems[0]


@pytest.mark.parametrize("description", [
    "좋아하는 노래 이야기를 나누는 카드예요.",
    "오늘 대화에서 함께 볼 카드예요.",
    "병원에서 일하던 경험을 나누는 카드예요.",
    "치매를 치료하는 기능은 아니에요.",
    "치료 효과가 있다고 볼 수 없어요.",
    "약을 드셨는지 보호자가 적은 소감을 참고해요.",
])
def test_normal_description_does_not_use_question_only_rules(description):
    assert _problems(_WritingResult(cards=[_text(1, description)]), [1]) == []


@pytest.mark.parametrize("still_unsafe", [False, True])
def test_unsafe_description_is_rewritten_once_or_fails(monkeypatch, still_unsafe):
    calls = []

    def invoke(*args):
        calls.append(args)
        unsafe = len(calls) == 1 or still_unsafe
        return _WritingResult(cards=[_text(1, "이 카드는 치매를 치료합니다." if unsafe else "노래 이야기예요.")])

    monkeypatch.setattr(write, "invoke_structured", invoke)
    if still_unsafe:
        with pytest.raises(write.WritingFailed):
            write.write_cards(object(), {}, [{"position": 1}], "합성 시험 지시")
    else:
        result, problems = write.write_cards(object(), {}, [{"position": 1}], "합성 시험 지시")
        assert result.cards[0].description == "노래 이야기예요." and problems
    assert len(calls) == 2
