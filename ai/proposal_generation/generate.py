"""변경 제안 생성. 이야기 후보와 주제 조정을 LLM 두 번으로 따로 받고 #106 규칙으로 거름.

시스템 프롬프트는 prompts/proposals.md 하나에서 나눠 씀. 첫 출력 절 제목 앞은 공통 부분이라 두 호출 모두 받고,
'## 새 이야기 후보' 절은 이야기 후보 호출만, '## 주제 조정 후보' 절은 주제 조정 호출만 받음.
이야기 후보는 대화 전체에서 빠짐없이 찾게 하려고 추론 강도를 medium으로 올림(PM 결정, 2026-11-09). 주제 조정은 기본값(low).
주제 조정은 이야기 후보 결과를 쓰지 않으므로 두 호출을 동시에 보냄. backend에서 리포트 호출과 제한 시간 하나를 나눠 쓰기 때문.
"""

from __future__ import annotations

__all__ = ["generate_proposals", "PROMPT", "PROMPT_VERSION"]

import contextvars
import logging
import threading
from concurrent.futures import Future
from dataclasses import replace
from pathlib import Path
from typing import Callable, TypeVar

from pydantic import BaseModel, Field

from common.llm import ENDPOINTS, ChatConfig, chat_model, llm_down
from common.structured import invoke_structured
from common.retry import RetryBlocked
from common.visit_report import (
    Action,
    LifeFactProposalOut,
    ProposalResult,
    StoryCategory,
    TopicProposalOut,
    VisitReportError,
    VisitReportRequest,
    card_refs,
    llm_payload,
)

PROMPT = Path(__file__).resolve().parent / "prompts/proposals.md"
PROMPT_VERSION = "proposals-10"  # 프롬프트나 거르는 규칙을 바꾸면 올림
_FACT_TITLE_MAX = 100            # #106 응답 검증과 같은 길이
_FACT_MAX = 30                   # 이야기 후보 안전 상한(PM 결정, 2026-11-09). 넘으면 앞에서부터 이만큼만 쓰고 기록을 남김
_LIFE_EFFORT = "medium"
_LIFE_HEADING = "## 새 이야기 후보(life_fact_proposals)"
_TOPIC_HEADING = "## 주제 조정 후보(topic_proposals)"

_log = logging.getLogger(__name__)
T = TypeVar("T", bound=BaseModel)


def generate_proposals(request: VisitReportRequest, *, model: str, api_key: str, attempts: int = 1,
                       on_retry: Callable[[dict[str, str]], None] | None = None,
                       before_call: Callable[[], None] | None = None) -> ProposalResult:
    """model은 common/llm.py ENDPOINTS에 있는 이름. attempts와 on_retry는 형식이 깨진 응답을 다시 받을 때 씀(시뮬레이션은 3).
    이야기 후보 호출은 따로 띄운 스레드에서, 주제 조정 호출은 부른 스레드에서 동시에 보냄. 둘 다 끝난 뒤 돌려줌.
    before_call은 두 모델 호출을 보내기 직전에 각각 부른 스레드에서 부름. 예외를 내면 그 뒤 호출은 보내지 않고 그 예외가
    그대로 올라감(backend 마감 확인용). 이미 보낸 이야기 후보 호출은 끊을 수 없어서 기다리지 않고 결과를 버림.
    실패는 VisitReportError. 둘 다 실패하면 이야기 후보 쪽 실패를 올림.
    """
    if model not in ENDPOINTS:
        raise VisitReportError("INVALID_REQUEST", f"모르는 model: {model}")
    refs = card_refs(request)
    payload = llm_payload(request, refs, with_facts=True)
    life_prompt, topic_prompt = split_prompt(PROMPT.read_text(encoding="utf-8"))
    # 두 호출이 다른 스레드에서 더하므로 토큰 수는 호출마다 따로 모아 끝에 합침
    life_usage: dict[str, int] = {}
    topic_usage: dict[str, int] = {}

    def call(schema: type[T], prompt: str, label: str, effort: str | None, usage: dict[str, int]) -> T:
        config = ChatConfig(model=model, api_key=api_key)
        if effort is not None:
            config = replace(config, effort=effort)
        try:
            return invoke_structured(chat_model(config), schema, [("system", prompt), ("user", payload)],
                                     label, attempts, on_retry, usage=usage)
        except RetryBlocked as blocked:
            raise blocked.original
        except Exception as error:
            code = "LLM_UNAVAILABLE" if llm_down(error) else "GENERATION_FAILED"
            failed = VisitReportError(code, f"{type(error).__name__}: {error}")
            failed.token_usage = usage  # 처리 기록용 숫자. 끊긴 응답 수(incomplete_responses)가 여기 담김
            raise failed from error

    if before_call is not None:
        before_call()
    life_future = _in_background(lambda: call(_LifeFacts, life_prompt, "이야기 후보", _LIFE_EFFORT, life_usage))
    if before_call is not None:
        before_call()
    try:
        topics = call(_Topics, topic_prompt, "주제 조정", None, topic_usage)
    except VisitReportError:
        life_future.result()   # 이야기 후보 호출이 끝나기를 기다림. 그쪽도 실패했으면 그 실패가 올라감
        raise
    life = life_future.result()
    return ProposalResult(model=model, prompt_version=PROMPT_VERSION, life_fact_proposals=_facts(life),
                          topic_proposals=_topics(topics, request, refs),
                          life_fact_proposals_returned=len(life.life_fact_proposals),
                          topic_proposals_returned=len(topics.topic_proposals),
                          token_usage=_add_usage(life_usage, topic_usage))


def _in_background(work: Callable[[], T]) -> Future[T]:
    """work를 daemon 스레드에서 돌리고 결과를 Future로 돌려줌. 부른 쪽의 contextvars(시뮬레이션 기록 단계 등)를 이어 씀.
    daemon이라 끝나지 않은 호출이 프로세스 종료를 막지 않음. ThreadPoolExecutor의 스레드는 종료 때 기다려서 쓰지 않음
    (backend worker의 --once가 멈춤. backend app/services/visit_report_generator.py의 _run_until과 같은 이유).
    """
    future: Future[T] = Future()
    context = contextvars.copy_context()

    def target() -> None:
        future.set_running_or_notify_cancel()
        try:
            future.set_result(context.run(work))
        except BaseException as error:
            future.set_exception(error)

    threading.Thread(target=target, name="proposal-life-facts", daemon=True).start()
    return future


def _add_usage(*usages: dict[str, int]) -> dict[str, int]:
    """호출마다 모은 토큰 수를 이름별로 더함."""
    total: dict[str, int] = {}
    for usage in usages:
        for name, count in usage.items():
            total[name] = total.get(name, 0) + count
    return total


def split_prompt(text: str) -> tuple[str, str]:
    """proposals.md를 (이야기 후보 호출, 주제 조정 호출)의 시스템 프롬프트로 나눔. 두 절 제목 앞은 공통 부분이라 둘 다 받음."""
    life_at, topic_at = text.find(_LIFE_HEADING), text.find(_TOPIC_HEADING)
    if not 0 <= life_at < topic_at:
        raise VisitReportError("GENERATION_FAILED", "변경 제안 프롬프트의 절 제목을 찾지 못함")
    common = text[:life_at]
    return common + text[life_at:topic_at].rstrip() + "\n", common + text[topic_at:]


# 변경 제안 LLM의 응답 형식. 모델이 읽는 스키마라 docstring을 두지 않음
class _LifeFact(BaseModel):
    title: str
    content: str
    story_category: StoryCategory = Field(
        description="family 가족, hobby 취미, work 일, hometown 고향, friend 친구, travel 여행, other 그 밖")
    sensitive: bool = Field(description="사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있으면 true")
    reason: str


class _LifeFacts(BaseModel):
    life_fact_proposals: list[_LifeFact]


class _TopicProposal(BaseModel):
    card: str = Field(description="카드 번호표(c1 같은 값)")
    suggested_action: Action
    reason: str


class _Topics(BaseModel):
    topic_proposals: list[_TopicProposal]


def _facts(out: _LifeFacts) -> list[LifeFactProposalOut]:
    """빈 칸이 있는 이야기 후보는 버리고, 제목은 #106 길이(100자)로 자름. 남은 후보가 _FACT_MAX개를 넘으면 앞에서부터 그만큼만 씀."""
    kept = [LifeFactProposalOut(title=f.title[:_FACT_TITLE_MAX], content=f.content, reason=f.reason,
                                story_category=f.story_category, sensitive=f.sensitive)
            for f in out.life_fact_proposals if f.title.strip() and f.content.strip() and f.reason.strip()]
    if len(kept) > _FACT_MAX:
        # 개수만 남김. 제목이나 내용은 기록하지 않음
        _log.warning("이야기 후보가 %d개라 앞 %d개만 씀", len(kept), _FACT_MAX)
    return kept[:_FACT_MAX]


def _topics(out: _Topics, request: VisitReportRequest, refs: dict[str, str]) -> list[TopicProposalOut]:
    """#106 규칙으로 거른 주제 조정. 없는 카드, 같은 카드의 두 번째 조정, 이유가 빈 조정, 반응이 notUsed거나 없는 카드의 less와 exclude는 버림.
    보호자가 아쉬웠다고 평가한(negative) 카드의 more도 버림(proposals-9). 앱은 AI 제안을 미리 골라 두므로, 보호자의 평가와
    거꾸로 가는 '더 자주'가 그대로 반영되지 않게 하려는 것. 버린 뒤 같은 카드의 다음 조정은 받음.
    """
    by_ref = {refs[c.card_id]: c for c in request.cards}
    kept, seen = [], set()
    for t in out.topic_proposals:
        card = by_ref.get(t.card.strip())
        if card is None or card.card_id in seen or not t.reason.strip():
            continue
        if t.suggested_action in ("less", "exclude") and card.reaction in ("notUsed", None):
            continue
        if t.suggested_action == "more" and card.reaction == "negative":
            continue
        seen.add(card.card_id)
        kept.append(TopicProposalOut(card_id=card.card_id, suggested_action=t.suggested_action, reason=t.reason))
    return kept
