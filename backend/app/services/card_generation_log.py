"""카드 생성 기록(`card_sets.generation_log`)에 남기는 형태.

PM 결정(2026-11-08): 기록에는 생성에 보낸 글을 복사하지 않고 ID만 남긴다. 보호자가 지운 이야기나
사진 설명이 기록에 계속 남지 않게 한다. 기록은 다음 생성 입력에 쓰지 않고 실패를 살펴볼 때만 본다.

    {
      "input": {"ageRange": "80s", "profileFields": ["hobby"], "lifeFactIds": [...],
                "photoIds": [...], "topicIds": [...], "visitSessionIds": [...], "pastCardIds": [...]},
      "log": {"candidates": 18, "refills": 1, "selectionSeed": 7, ...},
      "cards": [{"position": 1, "kind": "personal", "bucket": "new"}, ...]
    }

- `input`: 보낸 이야기, 사진, 주제, 회차, 지난 카드의 ID와 연령대, 값이 있던 세부 정보 칸의 이름.
  세부 정보 값, 이야기 제목과 내용, 사진 설명, 주제 제목과 설명, 지난 카드 문구는 넣지 않는다.
- `log`: 생성 쪽 실행 기록에서 숫자와 참거짓만 그대로 두고 목록은 개수로 바꾼다. 글과 객체는 버린다.
  다시 찾기 요청 글, 빠진 후보의 카드 제목과 이유, 문안 검사에 걸린 질문에 이야기 내용이 들어갈 수 있다.
- `cards`: 카드별 `extra`에서 정해진 값(`kind`, `bucket`)만 남긴다. `angle`과 고른 이유는 글이라 버린다.

`reference_log`는 예전의 글이 든 기록과 이 형태를 모두 받는다. 이 형태를 넣으면 그대로 돌려주므로
여러 번 적용해도 결과가 같다. migration `685f243e9f1f`도 이 함수로 기존 행을 고친다.
"""

import re
from typing import Any

# 세부 정보 네 칸. 4-1 context의 `profileFacts`와 근거 항목 `profileField`의 값
PROFILE_FIELDS = ("occupation", "hometown", "hobby", "family")
# 카드별 `extra`에서 남기는 값. ai/card_generation/contract.py의 CardExtra와 같은 값만 받음
CARD_EXTRA_VALUES = {
    "kind": {"personal", "photo", "discover", "general"},
    "bucket": {"new", "existing"},
}
_AGE_RANGE = re.compile(r"\d+0s")
_UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
# context의 목록 → (항목의 ID 키, 기록에 남기는 이름)
_ID_LISTS = {
    "lifeFacts": ("factId", "lifeFactIds"),
    "photos": ("photoId", "photoIds"),
    "topics": ("topicId", "topicIds"),
    "visits": ("sessionId", "visitSessionIds"),
    "pastCards": ("cardId", "pastCardIds"),
}


def _ids(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    return [value for value in values if isinstance(value, str) and _UUID.fullmatch(value)]


def reference_input(sent: Any) -> dict[str, Any] | None:
    """생성에 보낸 context(JSON 이름)를 ID만 남긴 형태로 바꿈. context가 없으면 `None`.

    context에 없던 목록은 기록에도 넣지 않음. 그래서 `{}`는 `{}`로 남음.
    """
    if not isinstance(sent, dict):
        return None
    out: dict[str, Any] = {}
    age_range = sent.get("ageRange")
    if isinstance(age_range, str) and _AGE_RANGE.fullmatch(age_range):
        out["ageRange"] = age_range
    profile_facts = sent.get("profileFacts")
    if isinstance(profile_facts, dict):
        out["profileFields"] = [
            field
            for field in PROFILE_FIELDS
            if isinstance(profile_facts.get(field), str) and profile_facts[field]
        ]
    elif isinstance(sent.get("profileFields"), list):
        out["profileFields"] = [field for field in PROFILE_FIELDS if field in sent["profileFields"]]
    for source, (key, name) in _ID_LISTS.items():
        if isinstance(sent.get(source), list):
            out[name] = _ids([item.get(key) for item in sent[source] if isinstance(item, dict)])
        elif name in sent:
            out[name] = _ids(sent[name])
    return out


def _run_counts(run: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in run.items():
        if isinstance(value, (bool, int, float)):
            out[key] = value
        elif isinstance(value, list):
            out[key] = len(value)
    return out


def _card(card: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    position = card.get("position")
    if isinstance(position, int) and not isinstance(position, bool):
        out["position"] = position
    for key, allowed in CARD_EXTRA_VALUES.items():
        value = card.get(key)
        if isinstance(value, str) and value in allowed:
            out[key] = value
    return out


def reference_log(log: Any) -> dict[str, Any]:
    """`generation_log` 전체를 ID만 남긴 형태로 바꿈. `input` 키는 늘 있음(CHECK)."""
    log = log if isinstance(log, dict) else {}
    out: dict[str, Any] = {"input": reference_input(log.get("input"))}
    if isinstance(log.get("log"), dict):
        out["log"] = _run_counts(log["log"])
    if isinstance(log.get("cards"), list):
        out["cards"] = [_card(card) for card in log["cards"] if isinstance(card, dict)]
    return out
