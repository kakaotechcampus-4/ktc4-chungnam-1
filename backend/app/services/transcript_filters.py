"""무음이나 잡음에서 STT가 지어내는 알려진 문장을 걸러낸다.

Whisper 계열 모델은 말소리가 없는 구간에 영상 끝맺음 같은 문장을 만들어 낸다.
2026-11-07 Galaxy S22 실기기 시험에서 아무도 말하지 않은 녹음이 두 번(세부 정보
음성 입력, 15초 면회 녹음) 모두 "다음 영상에서 만나요."로 옮겨졌고, 면회 쪽은 그
문장으로 리포트 제목까지 만들어졌다. 11/8 무음 녹음에서는 백업 STT가 "한글자막 by
한효정"을 반복하거나 자막과 유료 광고 안내 문구를 만들었다.

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
    }
)
# 문장 전체가 이 꼴이면 버린다(공백과 문장부호를 지운 소문자 기준).
_PATTERNS = (
    # 방송 끝맺음("MBC 뉴스 OOO입니다"). 이름 자리는 2~4자다.
    re.compile(r"^(mbc|kbs|sbs|ytn|jtbc)뉴스[가-힣]{2,4}입니다$"),
    # 자막 제작자 표시("한글자막 by 한효정", "자막 제공 OOO").
    re.compile(r"^(한글)?자막(제작|제공|편집)?(by|제공|협찬)[가-힣a-z0-9]{0,20}$"),
    # 영상 앞머리의 광고 안내("이 영상은 유료 광고를 포함하고 있습니다").
    re.compile(r"^(이|본)?영상은?(유료)?광고를?포함하고있습니다$"),
    re.compile(r"^자막(제공)?및광고를?포함하고있습니다$"),
)
_NOT_WORD = re.compile(r"[\s\W_]+", re.UNICODE)


def _normalize(text: str) -> str:
    return _NOT_WORD.sub("", text).lower()


def is_known_hallucination(text: str) -> bool:
    """구간 문장 전체가 무음에서 나오는 알려진 문장인지."""
    normalized = _normalize(text)
    if not normalized:
        return False
    if normalized in _KNOWN_HALLUCINATIONS:
        return True
    return any(pattern.match(normalized) for pattern in _PATTERNS)


def drop_known_hallucinations(result: SpeechAnalysisResult) -> SpeechAnalysisResult:
    """알려진 문장만으로 된 구간을 빼고 전체 문장을 남은 구간으로 다시 만든다.

    뺀 구간이 없으면 받은 결과를 그대로 돌려준다. 모두 빠지면 구간이 비고, 부르는
    쪽의 빈 전사 처리(EMPTY_TRANSCRIPT, 음성 입력의 "알아듣지 못함")를 따른다.
    """
    kept = [segment for segment in result.segments if not is_known_hallucination(segment.text)]
    if len(kept) == len(result.segments):
        return result
    logger.info(
        "known_hallucination_dropped analysis_id=%s dropped=%d kept=%d",
        result.analysis_id,
        len(result.segments) - len(kept),
        len(kept),
    )
    text = " ".join(segment.text.strip() for segment in kept if segment.text.strip())
    return result.model_copy(update={"segments": kept, "text": text})
