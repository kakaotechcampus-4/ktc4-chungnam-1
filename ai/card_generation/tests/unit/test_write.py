"""문안 검사 (실제 LLM 미호출)."""

from card_generation._steps.write import _CardText, _problems, _WritingResult


def _text(pos: int, description: str = "설명") -> _CardText:
    return _CardText(position=pos, description=description, primary_question="어떤 노래였어요?",
                     follow_up_questions=["누구랑 불렀어요?", "어디서 불렀어요?", "또 부르고 싶으세요?"])


def test_blank_description_is_sent_back():
    result = _WritingResult(cards=[_text(1), _text(2, description=" ")])
    assert _problems(result, [1, 2]) == ["2번: 설명이 비어 있다."]
