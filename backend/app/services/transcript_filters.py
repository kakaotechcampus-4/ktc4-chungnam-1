"""무음이나 잡음에서 STT가 지어내는 알려진 문장을 걸러낸다.

Whisper 계열 모델은 말소리가 없는 구간에 영상 끝맺음 같은 문장을 만들어 낸다.
2026-11-07 Galaxy S22 실기기 시험에서 아무도 말하지 않은 녹음이 두 번(세부 정보
음성 입력, 15초 면회 녹음) 모두 "다음 영상에서 만나요."로 옮겨졌고, 면회 쪽은 그
문장으로 리포트 제목까지 만들어졌다. 11/8 무음 녹음에서는 백업 STT가 "한글자막 by
한효정"을 반복하거나 자막과 유료 광고 안내 문구를 만들었다.

11/8 운영 안정성 시험에서는 문 두드리는 소리(ESC-50)가 세 번 모두 "다음 영상에서 만나요."로
옮겨졌는데, STT가 이 문장을 "다음"과 "영상에서 만나요." 두 구간으로 나눠 보내 구간별 비교를
빠져나갔다. 그래서 이어진 구간을 몇 개까지 합쳐서도 본다. 같은 시험에서 식당 소음은
"한국국토정보공사"를 세 번 되풀이했고, 옛 뉴스 영상은 "기상캐스터 배혜지"를 되풀이했다.

구간 문장 전체가 아래 목록과 같을 때만 버린다. 대화 안에 섞인 말은 건드리지 않고,
"감사합니다"처럼 면회에서 실제로 할 만한 말은 목록에 넣지 않는다. 확률이나 무음
비율 같은 인식 임계값은 AI 담당 결정과 실측이 필요해 여기서 정하지 않는다.
"""

from __future__ import annotations

import logging
import re

from app.schemas.speech_analysis import SpeechAnalysisResult

logger = logging.getLogger("saerok.transcript_filters")

# 공백과 문장부호를 지운 꼴로 적는다.
_KNOWN_HALLUCINATIONS = frozenset(
    {
        "다음영상에서만나요",
        "다음영상에서뵙겠습니다",
        "다음영상에서또만나요",
        "시청해주셔서감사합니다",
        "시청해주셔서고맙습니다",
        "시청해주셔서감사합니다다음영상에서만나요",
        "구독과좋아요부탁드립니다",
        "구독과좋아요눌러주세요",
        "구독좋아요알림설정부탁드립니다",
        "구독과좋아요알림설정부탁드립니다",
        "구독과좋아요그리고알림설정부탁드립니다",
        "오늘영상은여기까지입니다",
        "오늘영상은여기까지",
        # 11/8 안정성 시험: 식당 소음(DEMAND, Commons)에서 되풀이해 나왔다.
        "한국국토정보공사",
        # 자막 제작자 이름만 따로 나온다(11/8 무음 회차, 아리랑 음악 시험).
        "한효정",
    }
)
# 문장 전체가 이 꼴이면 버린다(공백과 문장부호를 지운 소문자 기준).
_PATTERNS = (
    # 방송 끝맺음("MBC 뉴스 OOO입니다"). 이름 자리는 2~4자다.
    re.compile(r"^(mbc|kbs|sbs|ytn|jtbc)뉴스[가-힣]{2,4}입니다$"),
    # 날씨 끝맺음("기상캐스터 배혜지", "MBC 뉴스 기상캐스터 OOO입니다").
    re.compile(r"^((mbc|kbs|sbs|ytn|jtbc)?(뉴스)?)기상캐스터[가-힣]{2,4}(입니다)?$"),
    # 자막 제작자 표시("한글자막 by 한효정", "자막 제공 OOO").
    re.compile(r"^(한글)?자막(제작|제공|편집)?(by|제공|협찬)[가-힣a-z0-9]{0,20}$"),
    # 영상 앞머리의 광고 안내("이 영상은 유료 광고를 포함하고 있습니다").
    re.compile(r"^(이|본)?영상은?(유료)?광고를?포함하고있습니다$"),
    re.compile(r"^자막(제공)?및광고를?포함하고있습니다$"),
)
_NOT_WORD = re.compile(r"[\s\W_]+", re.UNICODE)
_SENTENCE_END = re.compile(r"[.!?。！？]+")
# STT가 한 문장을 나눠 보내는 구간 수. 11/8 실측은 2구간이었고 여유를 둔다.
_MAX_JOINED_SEGMENTS = 4


def _normalize(text: str) -> str:
    return _NOT_WORD.sub("", text).lower()


def _is_known_normalized(normalized: str) -> bool:
    if not normalized:
        return False
    if normalized in _KNOWN_HALLUCINATIONS or any(p.match(normalized) for p in _PATTERNS):
        return True
    # 같은 문장을 되풀이한 꼴("한국국토정보공사 한국국토정보공사 ...")도 본다.
    size = len(normalized)
    for period in range(2, size // 2 + 1):
        if size % period == 0 and normalized[:period] * (size // period) == normalized:
            unit = normalized[:period]
            return unit in _KNOWN_HALLUCINATIONS or any(p.match(unit) for p in _PATTERNS)
    return False


def is_known_hallucination(text: str) -> bool:
    """구간 문장 전체가 무음에서 나오는 알려진 문장(또는 그 문장들만의 묶음)인지."""
    if _is_known_normalized(_normalize(text)):
        return True
    # "시청해 주셔서 감사합니다. 다음 영상에서 만나요."처럼 알려진 문장만 이어 붙은 경우.
    sentences = [_normalize(part) for part in _SENTENCE_END.split(text)]
    sentences = [s for s in sentences if s]
    return len(sentences) > 1 and all(_is_known_normalized(s) for s in sentences)


def _known_segment_indexes(texts: list[str]) -> set[int]:
    """알려진 문장에 해당하는 구간 번호. 이어진 구간을 합쳐야 문장이 되는 경우도 찾는다."""
    found: set[int] = set()
    index = 0
    while index < len(texts):
        longest = min(_MAX_JOINED_SEGMENTS, len(texts) - index)
        size = next(
            (n for n in range(longest, 0, -1) if is_known_hallucination(" ".join(texts[index:index + n]))),
            0,
        )
        if size:
            found.update(range(index, index + size))
            index += size
        else:
            index += 1
    return found


def drop_known_hallucinations(result: SpeechAnalysisResult) -> SpeechAnalysisResult:
    """알려진 문장만으로 된 구간을 빼고 전체 문장을 남은 구간으로 다시 만든다.

    뺀 구간이 없으면 받은 결과를 그대로 돌려준다. 모두 빠지면 구간이 비고, 부르는
    쪽의 빈 전사 처리(EMPTY_TRANSCRIPT, 음성 입력의 "알아듣지 못함")를 따른다.
    """
    if not result.segments:
        # 구간 없이 전체 문장만 온 경우에도 같은 기준을 쓴다.
        if is_known_hallucination(result.text):
            logger.info("known_hallucination_dropped analysis_id=%s dropped=text kept=0", result.analysis_id)
            return result.model_copy(update={"text": ""})
        return result
    drop = _known_segment_indexes([segment.text for segment in result.segments])
    if not drop:
        return result
    kept = [segment for i, segment in enumerate(result.segments) if i not in drop]
    logger.info(
        "known_hallucination_dropped analysis_id=%s dropped=%d kept=%d",
        result.analysis_id,
        len(result.segments) - len(kept),
        len(kept),
    )
    text = " ".join(segment.text.strip() for segment in kept if segment.text.strip())
    return result.model_copy(update={"segments": kept, "text": text})
