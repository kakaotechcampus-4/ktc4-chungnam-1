"""최소 치료 효과 규칙의 차단·통과 경계. 모두 합성 문장이다."""
import pytest

from card_generation._steps.text_checks import has_card_treatment_claim
from card_generation._steps.write import _CardText, _WritingResult, _problems


@pytest.mark.parametrize("text", [
    "이 카드는 치매를 치료합니다.",
    "카드가 치매를 치료해요.",
    "이 카드에는 치료 효과가 있습니다.",
    "이 카드에 치매 치료 효과가 있어요.",
    "치료 효과가 있어요.",
    "이 카드는 치매 치료에 효과적입니다.",
    "이 카드는 치료에 효과적이에요.",
    "이  카드에는  치료 효과가 있습니다!",
    "이 카드는 치매를 치료합니다。",
    "노래 이야기예요.\n이 카드에는 치료 효과가 있습니다.",
    "치료 효과는 없습니다. 이 카드는 치매를 치료합니다.",
])
def test_direct_treatment_claim(text):
    assert has_card_treatment_claim(text)


@pytest.mark.parametrize("text", [
    "이 카드는 치료 효과가 없습니다.",
    "이 카드는 치료 효과가 있는 것은 아닙니다.",
    "이 카드는 치매를 치료하지 않습니다.",
    "이 카드는 치매 치료에 효과적이지 않습니다.",
    "이 카드는 치매를 치료합니다라고 말하지 않습니다.",
    "‘이 카드는 치매를 치료합니다.’라는 주장은 하지 않습니다.",
    "이 카드에는 치료 효과가 있나요?",
    "이 카드에는 치료 효과가 있다는 뜻이 아닙니다.",
    "이 카드는 치매 치료에 효과적이라는 주장을 하지 않습니다.",
    "이 카드는 ‘치매’를 치료합니다라는 표현을 피합니다.",
    "이 카드에는 치료 효과가 있습니다?",
    "병원에서 일하던 경험을 나누는 카드예요.",
    "오늘은 어떤 노래를 같이 불러 볼까요?",
    "어제 무엇을 드셨는지 기억나세요?",
    "낱말을 맞히면 어떤 기분이 드셨어요?",
])
def test_denials_quotes_questions_and_normal_conversation_pass(text):
    assert not has_card_treatment_claim(text)


@pytest.mark.parametrize("field", ["description", "primary_question", "follow_up_questions"])
def test_treatment_claim_checked_in_each_written_field(field):
    card = _CardText(position=1, description="노래 이야기예요.",
                     primary_question="어떤 노래를 좋아하셨어요?",
                     follow_up_questions=["어떤 가수를 좋아하셨어요?"] * 3)
    text = "이 카드는 치매를 치료합니다. 어떤 노래를 좋아하셨어요?"
    setattr(card, field, [text, *card.follow_up_questions[1:]] if field == "follow_up_questions" else text)
    problems = _problems(_WritingResult(cards=[card]), [1])
    assert len(problems) == 1 and "의료 효과" in problems[0]
