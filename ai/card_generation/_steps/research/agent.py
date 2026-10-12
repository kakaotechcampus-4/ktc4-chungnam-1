"""조사 에이전트(①). 읽기 도구로 프로필을 살펴보고 카드 후보 16~24개를 제출함.

제출은 Pydantic 모델로 받고 개수, 주제 수, 근거 형식, 번호표를 검사함. 걸리면 오류 문장을 모델에 돌려주고 다시 받음.
모델은 UUID 대신 번호표(t1, f3, p2)만 보고 씀. 제출 뒤 코드가 UUID로 되돌림.
턴 상한은 30. 마지막 턴에는 도구를 빼고 제출만 받음.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any

from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware
from langchain.agents.structured_output import ToolStrategy
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from pydantic import model_validator

from card_generation._steps.research.candidates import CardCandidate, submission_problems
from card_generation._steps.research.candidates import CardCandidateSubmission as BaseSubmission
from card_generation._steps.research.store import ProfileStore
from card_generation._steps.research.tools import build_tools
from card_generation._versions.base import Version

_SUBMIT = "CardCandidateSubmission"
_MAX_NUDGES = 2  # 제출 없이 끝났을 때 다시 요청하는 횟수
_FIRST_REQUEST = "이 어르신의 다음 면회에 쓸 대화 카드 후보를 도구로 살펴본 뒤 제출하라."


class AgentSession:
    """에이전트 대화 하나. 다시 찾기 때 같은 대화를 이어서 후보를 다시 받음."""

    def __init__(self, model: BaseChatModel, store: ProfileStore, v: Version, max_turns: int = 30) -> None:
        """도구 6개, 이 판의 시스템 프롬프트, 이 프로필 기준 제출 검사, 턴 상한을 묶어 LangChain 에이전트를 만듦."""
        self.store = store
        self.max_turns = max_turns
        self.budget = _TurnBudget(max_turns)
        self.agent = create_agent(model, build_tools(store), system_prompt=v.agent_prompt(),
                                  response_format=ToolStrategy(_submission_model(store, v),
                                                               handle_errors=True),
                                  middleware=[self.budget])
        self.messages: list[Any] = []
        self.started = time.monotonic()

    def ask(self, text: str = _FIRST_REQUEST) -> AgentRun:
        """text를 보내고 제출을 받을 때까지 돌림. 제출 없이 끝나면 _MAX_NUDGES번까지 다시 요청하고, 그래도 없으면 AgentFailed.
        같은 대화를 이어 가므로 다시 찾기 때는 판정 결과를 담은 글을 text로 넘김.
        """
        self.messages = [*self.messages, HumanMessage(text)]
        for _ in range(_MAX_NUDGES + 1):
            out = self.agent.invoke({"messages": self.messages}, {"recursion_limit": 4 * self.max_turns + 10})
            self.messages = out["messages"]
            submission = out.get("structured_response")
            if submission is not None:
                break
            self.messages = [*self.messages, HumanMessage("후보를 아직 제출하지 않았다. 제출 도구로 제출하라.")]
        else:
            raise AgentFailed("제출하라고 다시 말했지만 후보를 제출하지 않음")
        log, rejected = _tool_log(self.messages)
        return AgentRun(candidates=_resolve_ids(self.store, submission.candidates), tool_calls=log, rejected=rejected, seconds=round(time.monotonic() - self.started, 1))


@dataclass
class AgentRun:
    """조사 한 번의 결과. 후보(UUID로 되돌린 것), 도구 호출 기록, 거부된 제출의 오류 문장, 걸린 시간."""
    candidates: list[CardCandidate]
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    rejected: list[str] = field(default_factory=list)
    seconds: float = 0.0


class AgentFailed(RuntimeError):
    """턴 상한을 넘기거나 끝내 제출하지 않은 실패. generate_cards가 CARD_GENERATION_FAILED로 바꿈."""
    pass


class _TurnBudget(AgentMiddleware):
    """턴 상한. 마지막 턴에는 도구를 빼고, 넘기면 실패."""

    def __init__(self, max_turns: int) -> None:
        """max_turns는 모델 호출 상한."""
        super().__init__()
        self.max_turns = max_turns
        self.turn = 0

    def wrap_model_call(self, request, handler):
        """모델 호출마다 불림. 턴을 세고, 마지막 턴에는 도구를 빼서 제출만 하게 하고, 상한을 넘기면 AgentFailed.
        strict 모드도 여기서 켬(정해진 형식을 벗어난 출력 막기).
        """
        self.turn += 1
        if self.turn > self.max_turns:
            raise AgentFailed(f"{self.max_turns}턴 안에 받아들일 수 있는 후보를 제출하지 않음")
        overrides: dict[str, Any] = {"model_settings": {**request.model_settings, "strict": True}}
        if self.turn == self.max_turns:
            overrides["tools"] = []
        return handler(request.override(**overrides))


def _submission_model(store: ProfileStore, v: Version) -> type[BaseSubmission]:
    """이 프로필에 있는 번호표만 받는 제출 모델. 프로필마다 ID가 달라 실행할 때 만듦."""
    aliases = store.aliases()
    empty = store.known_ids()["empty_fields"]

    class CardCandidateSubmission(BaseSubmission):
        """대화 카드 후보 16~24개를 제출하고 조사를 끝낸다."""

        @model_validator(mode="after")
        def _check(self) -> "CardCandidateSubmission":
            # 개수 제한은 JSON Schema(minItems 등) 대신 여기서 검사. 모델 API마다 받는 키워드가 다름
            # ValueError를 내면 ToolStrategy가 문장을 모델에 돌려주고 다시 받음
            """판 기준 제출 검사와 번호표 검사를 함께 돌리고, 걸리면 문장을 모아 ValueError로 돌려보냄."""
            problems = submission_problems(self, v)
            for i, c in enumerate(self.candidates, 1):
                if c.linked_topic_id and not aliases.known(c.linked_topic_id, "t"):
                    problems.append(f"{i}번: linked_topic_id {c.linked_topic_id}는 없는 주제다. list_topics가 돌려준 t 번호표를 쓴다.")
                for e in c.evidence:
                    if e.fact_id and not aliases.known(e.fact_id, "f"):
                        problems.append(f"{i}번: fact_id {e.fact_id}는 없는 이야기다. 도구가 돌려준 f 번호표를 쓴다.")
                    if e.photo_id and not aliases.known(e.photo_id, "p"):
                        problems.append(f"{i}번: photo_id {e.photo_id}는 없는 사진이다. list_photos가 돌려준 p 번호표를 쓴다.")
                    if e.field and e.field in empty:
                        problems.append(f"{i}번: 초기 정보 {e.field} 칸은 비어 있어 근거가 될 수 없다.")
                if c.discover_field and c.discover_field not in empty:
                    problems.append(f"{i}번: discover_field {c.discover_field}는 비어 있는 칸이 아니다.")
            if problems:
                raise ValueError("제출을 받을 수 없다. 아래를 고쳐서 다시 제출하라.\n- " + "\n- ".join(problems))
            return self

    return CardCandidateSubmission


def _resolve_ids(store: ProfileStore, candidates: list[CardCandidate]) -> list[CardCandidate]:
    """번호표를 UUID로 되돌림."""
    aliases = store.aliases()
    out = []
    for c in candidates:
        evidence = [e.model_copy(update={"fact_id": aliases.uuid(e.fact_id), "photo_id": aliases.uuid(e.photo_id)})
                    for e in c.evidence]
        out.append(c.model_copy(update={"linked_topic_id": aliases.uuid(c.linked_topic_id), "evidence": evidence}))
    return out


def _tool_log(messages: list[Any], submit: str = _SUBMIT) -> tuple[list[dict[str, Any]], list[str]]:
    """도구 호출 기록과 거부된 제출의 오류 문장."""
    results = {m.tool_call_id: m.content for m in messages if isinstance(m, ToolMessage)}
    log, rejected, turn = [], [], 0
    for m in messages:
        if not isinstance(m, AIMessage):
            continue
        turn += 1
        for call in m.tool_calls:
            result = str(results.get(call["id"], ""))
            if call["name"] == submit:
                ok = "Error" not in result and "제출을 받을 수 없다" not in result
                log.append({"turn": turn, "call": "제출" if ok else "제출(거부됨)"})
                if not ok:
                    rejected.append(result)
                continue
            log.append({"turn": turn, "call": call["name"], "args": call["args"], "result_chars": len(result)})
    return log, rejected
