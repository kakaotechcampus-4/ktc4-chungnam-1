"""카드 생성 기록을 ID만 남긴 형태로 바꾸는 규칙(`app/services/card_generation_log.py`). DB 없이 실행.

값은 모두 합성이다. 합성 글은 모두 한글이라 바꾼 기록에 한글이 없으면 글이 남지 않은 것이다.
"""

import json
import re

import pytest

from app.services.card_generation_log import reference_log
from tests.card_fixtures import (
    FULL_TEXT_GENERATION_LOG,
    LOG_FACT,
    REFERENCE_GENERATION_LOG,
)

HANGUL = re.compile(r"[가-힣]")


def test_full_text_log_keeps_only_ids_counts_and_fixed_values():
    converted = reference_log(FULL_TEXT_GENERATION_LOG)

    assert converted == REFERENCE_GENERATION_LOG
    assert not HANGUL.search(json.dumps(converted, ensure_ascii=False))


@pytest.mark.parametrize(
    "log",
    [REFERENCE_GENERATION_LOG, {"input": None}, {"input": {}}, {"input": {"ageRange": "80s"}}],
    ids=["converted", "no-input", "empty-input", "age-only"],
)
def test_log_without_text_is_left_as_it_is(log):
    assert reference_log(log) == log


def test_text_in_unexpected_places_is_dropped():
    converted = reference_log(
        {
            "input": {
                "ageRange": "합성 나이",
                "profileFields": ["hobby", "합성 취미"],
                "lifeFactIds": ["합성 제목", LOG_FACT],
                "photos": [{"photoId": "합성 사진 설명"}],
            },
            "log": {"note": "합성 메모", "detail": {"text": "합성 이야기"}},
            "cards": [{"position": 1, "kind": "합성 종류", "bucket": "new"}],
        }
    )

    assert converted == {
        "input": {"profileFields": ["hobby"], "lifeFactIds": [LOG_FACT], "photoIds": []},
        "log": {},
        "cards": [{"position": 1, "bucket": "new"}],
    }
