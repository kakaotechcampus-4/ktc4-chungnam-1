import pytest

from common.medical_claims import has_medical_effect_claim


@pytest.mark.parametrize("text", [
    "새록은 치매를 치료합니다.",
    "치매를 완치할 수 있습니다.",
    "이번 대화는 치매를 치료하는 효과가 있습니다.",
    "이 앱은 기억력을 향상시킵니다.",
    "이 서비스는 인지 기능을 개선해요.",
    "이번 면회로 기억이 회복됩니다.",
    "대화로 기억력을 회복시켜요.",
])
def test_direct_effect_claims_are_flagged(text):
    assert has_medical_effect_claim(text)


@pytest.mark.parametrize("text", [
    "병원에 다녀왔다는 이야기를 나눴습니다.",
    "어르신은 치매 약을 복용하고 있다고 말했습니다.",
    "치매를 치료하지 않습니다.",
    "치매를 치료할 수 없습니다.",
    "이 앱의 치매 치료 효과를 주장할 수 없습니다.",
    "이 대화에 치료 효과가 있다는 근거는 없습니다.",
    "과거 기억을 이야기했습니다.",
    "가족과 나눈 이야기에서 웃음이 나왔습니다.",
    "내일 병원에 갈 계획을 이야기했습니다.",
    "인지 기능이 좋아졌는지는 판단할 수 없습니다.",
])
def test_medical_topic_and_denial_are_not_effect_claims(text):
    assert not has_medical_effect_claim(text)
