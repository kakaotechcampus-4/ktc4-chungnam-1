"""문안 작성(④). 고른 12장에 설명, 첫 질문, 꼬리 질문 3개를 씀(판의 writing_topics.md).

코드가 꼬리 질문 개수, 물음표, 금지 표현(기억 시험, 최근 일, 의료 표현)을 검사함.
꼬리 질문 3개는 API 명세 4절(#87). 금지 표현은 PM이 저장소 규칙(CLAUDE.md)에 정해 둔 "최근 기억을 시험하는 질문, 의료 진단 금지" 기준.
걸리면 걸린 곳을 알려 주고 한 번 다시 쓰게 함. 또 걸리면 실패.
"""

from __future__ import annotations

import json
import re
from typing import Any

from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel, Field

from common.structured import invoke_structured

_BANNED = [r"기억\s*나세요", r"기억\s*하세요", r"기억하시", r"기억나시", r"요즘", r"오늘", r"어제", r"방금", r"지난주",
          r"치매", r"증상", r"치료", r"병원", r"약을?\s*드"]


class WritingFailed(RuntimeError):
    """다시 쓰게 해도 검사에 걸린 실패. generate_cards가 TEXT_CHECK_FAILED로 바꿈."""
    pass


# 문안 LLM이 카드 한 장마다 내는 형식. 모델이 읽는 스키마라 docstring을 두지 않음
class _CardText(BaseModel):
    position: int
    description: str
    primary_question: str
    follow_up_questions: list[str] = Field(description="꼬리 질문 3개")


# 문안 LLM의 응답 형식. 12장 전체
class _WritingResult(BaseModel):
    cards: list[_CardText]


def write_cards(model: BaseChatModel, profile: dict[str, Any], cards: list[dict[str, Any]],
                prompt: str) -> tuple[_WritingResult, list[str]]:
    """(결과, 처음 검사에서 걸린 것). cards 원소에는 position, card_title, angle, kind, evidence_texts, topic이 들어감."""
    messages = [("system", prompt),
                ("user", json.dumps({"profile": profile, "cards": cards}, ensure_ascii=False))]
    result = invoke_structured(model, _WritingResult, messages, "문안 작성")
    first = _problems(result, [c["position"] for c in cards])
    if first:
        messages += [("assistant", result.model_dump_json()),
                     ("user", "아래를 고쳐서 12장 전체를 다시 써라.\n- " + "\n- ".join(first))]
        result = invoke_structured(model, _WritingResult, messages, "문안 작성")
        again = _problems(result, [c["position"] for c in cards])
        if again:
            raise WritingFailed("; ".join(again))
    return result, first


def _problems(result: _WritingResult, positions: list[int]) -> list[str]:
    """문안 검사. 카드 위치가 입력과 같은지, 꼬리 질문이 3개인지, 질문이 물음표로 끝나는지, 금지 표현(_BANNED)이 없는지.
    걸린 것을 문장 목록으로 돌려주고, 이 문장을 그대로 모델에게 보내 고치게 함.
    """
    out = []
    if sorted(c.position for c in result.cards) != sorted(positions):
        out.append(f"카드 위치가 입력과 다르다. 입력은 {positions}다.")
    for c in result.cards:
        if len(c.follow_up_questions) != 3:
            out.append(f"{c.position}번: 꼬리 질문이 {len(c.follow_up_questions)}개다. 3개여야 한다.")
        for q in [c.primary_question, *c.follow_up_questions]:
            if not q.strip().endswith("?"):
                out.append(f"{c.position}번: 질문이 물음표로 끝나지 않는다: {q}")
            hit = next((b for b in _BANNED if re.search(b, q)), None)
            if hit:
                out.append(f"{c.position}번: 쓰면 안 되는 표현({hit})이 있다: {q}")
    return out
