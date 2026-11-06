"""리포트와 변경 제안에서 의료 효과를 직접 보장하는 문장 검사. 임상적 사실 여부를 판정하지 않는다."""
import re
import unicodedata

# 병원, 약, 치매라는 단어만으로 차단하지 않는다. 문장 하나가 통째로 앱이나 대화의
# 치료 효과를 단정할 때만 일치한다(카드 문안 검사와 같은 방식). 어르신이나 가족의 말을
# 옮긴 문장("...라고 하셨어요"), 들은 이야기, 부정과 유보는 문장 전체가 주장이 아니므로
# 걸리지 않는다. 모든 우회 표현을 이해하는 의미 검사는 아니므로 실제 모델 출력 평가를
# 대신할 수 없다.
_SUBJECT = r"(?:새록|이\s*앱|이\s*서비스|(?:이|이번)\s*(?:대화|면회|활동)|대화|면회)"
_SUBJECT_PARTICLE = r"(?:은|는|이|가|로|으로|를\s*통해)"
_CAN = r"할\s*수\s*있(?:습니다|어요|다)"
_DIRECT = re.compile(
    rf"(?:{_SUBJECT}{_SUBJECT_PARTICLE}\s*)?"
    r"(?:치매|알츠하이머(?:병)?)(?:를|을|는|가)?\s*"
    rf"(?:치료{_CAN}|완치{_CAN}|예방{_CAN}|"
    r"치료합니다|치료해요|치료한다|완치합니다|완치해요|완치한다|예방합니다|예방해요|예방한다)"
)
_SERVICE_EFFECT = re.compile(
    rf"{_SUBJECT}{_SUBJECT_PARTICLE}\s*"
    r"(?:어르신의\s*)?(?:치매|알츠하이머(?:병)?|기억력|인지\s*기능|기억)(?:을|를|이|가|에)?\s*"
    r"(?:치료하는\s*효과가\s*있(?:습니다|어요|다)|치료\s*효과가\s*있(?:습니다|어요|다)|"
    r"예방하는\s*효과가\s*있(?:습니다|어요|다)|"
    r"회복시킵니다|회복시켜요|회복시킨다|향상시킵니다|향상시켜요|향상시킨다|"
    r"개선합니다|개선해요|개선한다|회복됩니다|회복돼요|회복된다|향상됩니다|향상돼요|향상된다|"
    r"개선됩니다|개선돼요|개선된다)"
)
_SENTENCE_END = re.compile(r"[.!?。！？\n]+")


def has_medical_effect_claim(text: str) -> bool:
    """문장 하나가 통째로 치료, 예방, 기억 회복 효과를 단정하면 참이다."""
    normalized = unicodedata.normalize("NFKC", text)
    return any(
        pattern.fullmatch(sentence.strip())
        for sentence in _SENTENCE_END.split(normalized)
        for pattern in (_DIRECT, _SERVICE_EFFECT)
    )
