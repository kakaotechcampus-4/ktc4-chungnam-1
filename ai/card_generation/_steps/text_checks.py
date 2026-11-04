"""카드에 치료 효과가 있다고 직접 단정하는 구문만 검사한다."""
import re


# 문장 전체가 긍정 서술일 때만 일치한다. 부정·전언의 뒷부분을 잘라내지 않는다.
_CARD_TREATMENT_CLAIMS = tuple(re.compile(pattern) for pattern in (
    r"(?:이\s*)?카드(?:는|가)\s*(?:치매|알츠하이머병)(?:를|을)\s*치료(?:합니다|해요|한다)",
    r"(?:(?:이\s*)?카드(?:는|가|에는|에)\s*)?(?:치매\s*)?치료\s*효과(?:가|는)\s*(?:있습니다|있어요|있다)",
    r"(?:이\s*)?카드(?:는|가)\s*(?:치매\s*)?치료에\s*효과적(?:입니다|이에요|이다)",
))


def has_card_treatment_claim(text: str) -> bool:
    return any(pattern.fullmatch(sentence.strip())
               for sentence in re.split(r"[.!。！\n]+", text)
               for pattern in _CARD_TREATMENT_CLAIMS)
