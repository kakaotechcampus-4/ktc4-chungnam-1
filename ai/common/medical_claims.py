"""의료 효과를 직접 보장하는 대표 문구 검사. 임상적 사실 여부를 판정하지 않는다."""
import re
import unicodedata

# 병원, 약, 치매라는 단어만으로 차단하지 않는다. 생성물이 앱이나 대화의
# 치료 효과를 보장하는 구문을 검사한다. 인용 여부나 모든 우회 표현을 이해하는
# 의미 검사는 아니므로 실제 모델 출력 평가를 대신할 수 없다.
_DIRECT = re.compile(
    r"(?:치매|알츠하이머)(?:를|는|가|의)?\s*"
    r"(?:치료할\s*수\s*있|완치할\s*수\s*있|예방할\s*수\s*있|"
    r"치료합니다|치료해요|완치합니다|완치해요|예방합니다|예방해요)"
)
_SERVICE_EFFECT = re.compile(
    r"(?:새록|이\s*앱|이\s*서비스|(?:이|이번)\s*(?:대화|면회|활동)|대화(?:는|가|로))"
    r"[^.!?。\n]{0,100}"
    r"(?:치매|알츠하이머|기억력|인지\s*기능|기억)"
    r"[^.!?。\n]{0,40}"
    r"(?:치료하는\s*효과|치료\s*효과가\s*있|예방하는\s*효과|"
    r"회복시킵니다|회복시켜요|향상시킵니다|향상시켜요|개선합니다|개선해요|"
    r"회복됩니다|향상됩니다|개선됩니다)"
)


def has_medical_effect_claim(text: str) -> bool:
    normalized = unicodedata.normalize("NFKC", text)
    return bool(_DIRECT.search(normalized) or _SERVICE_EFFECT.search(normalized))
