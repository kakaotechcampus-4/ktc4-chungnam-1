"""카드 생성 단계별 입력과 출력을 시뮬레이션 기록에 남긴다. card_generation 코드는 고치지 않는다.

generate_cards가 부르는 이름(generate 모듈의 AgentSession, run_match, select_cards, write_cards와 match 모듈의 judge)을
같은 동작의 감싼 함수로 바꿔 끼우고, record() 안에서 부른 것만 모은다. 운영 backend는 이 모듈을 import하지 않는다.

  ① 조사     에이전트에게 보낸 요청, 도구 호출과 도구 결과 원문, 거부된 제출, 낸 후보(낸 순서)
  ② 연결 판정 판정 LLM 입력(번호표로 된 기존 주제와 후보), 판정 LLM 출력, 남은 후보와 빠진 후보. 다시 찾기마다 한 번씩
  ③ 선정     기존 주제의 점수와 추천하지 않기 여부, 고른 12장과 빠진 후보
  ④ 문안     문안 LLM 입력(카드 12장의 제목, angle, 근거 글, 주제), 출력, 첫 검사에서 걸린 것

도구 결과와 판정 입력은 모델이 보는 번호표(t1, f3, p2)를 쓴다. 후보와 선정 결과는 코드가 UUID로 되돌린 뒤의 값이다.
deadline.run이 생성 작업을 다른 스레드에서 돌릴 수 있어 contextvar가 아니라 프로세스 전역 기록을 쓴다.
한 프로세스에서 카드 생성을 동시에 두 번 돌리지 않는다는 가정이다(작업대는 실행을 하나씩 받는다).
"""

from __future__ import annotations

import json
import threading
import time
from contextlib import contextmanager
from typing import Any

from langchain_core.messages import AIMessage, HumanMessage, ToolMessage

import card_generation._steps.match as match_mod
import card_generation._steps.research.agent as agent_mod
import card_generation.generate as gen

_lock = threading.Lock()
_active: dict[str, Any] | None = None


def _parse(text: Any) -> Any:
    if not isinstance(text, str):
        return text
    try:
        return json.loads(text)
    except ValueError:
        return text


def _cand(no: int, c) -> dict[str, Any]:
    d = c.model_dump()
    d["evidence"] = [{k: v for k, v in e.items() if v is not None} for e in d["evidence"]]
    return {"no": no, **d}


class _Session(gen.AgentSession):
    """ask마다 그 사이에 오간 메시지에서 도구 호출과 결과 원문을 꺼낸다."""

    def ask(self, text: str = agent_mod._FIRST_REQUEST):
        start = len(self.messages)
        t = time.monotonic()
        out = super().ask(text)
        if _active is not None:
            new = self.messages[start:]
            results = {m.tool_call_id: m.content for m in new if isinstance(m, ToolMessage)}
            calls, turn = [], 0
            for m in new:
                if isinstance(m, HumanMessage):
                    calls.append({"kind": "request", "text": m.content})
                if not isinstance(m, AIMessage):
                    continue
                turn += 1
                for call in m.tool_calls:
                    calls.append({"kind": "tool", "turn": turn, "name": call["name"], "args": call["args"],
                                  "result": _parse(results.get(call["id"]))})
            _active["research"].append({"seconds": round(time.monotonic() - t, 1), "messages": calls,
                                        "rejected": out.rejected,
                                        "candidates": [_cand(i, c) for i, c in enumerate(out.candidates, 1)]})
        return out


_judge = match_mod.judge
_run_match = gen.run_match
_select = gen.select_cards
_write = gen.write_cards


def _judge_wrapped(model, payload, prompt):
    result = _judge(model, payload, prompt)
    if _active is not None:
        _active["_judge"] = {"input": payload, "output": result.model_dump()}
    return result


def _run_match_wrapped(model, store, candidates, prompt):
    t = time.monotonic()
    out = _run_match(model, store, candidates, prompt)
    if _active is not None:
        j = _active.pop("_judge", {})
        _active["match"].append({
            "seconds": round(time.monotonic() - t, 1), "input": j.get("input"), "output": j.get("output"),
            "kept": [{"no": m.no, "cardTitle": m.candidate.card_title, "kind": m.candidate.kind, "topicId": m.topic_id,
                      "newKey": m.new_key, "agentTopicId": m.agent_topic_id, "reason": m.reason} for m in out.kept],
            "dropped": out.dropped,
            "newTopics": {k: v.model_dump() for k, v in out.new_topics.items()}})
    return out


def _select_wrapped(outcome, topics, rules, rng=None):
    out = _select(outcome, topics, rules, rng)
    if _active is not None:
        _active["select"] = {
            "rules": {k: getattr(rules, k) for k in ("card_count", "min_new", "temperature") if hasattr(rules, k)},
            "topics": [{"topicId": t.topic_id, "title": t.title, "score": t.score, "excluded": t.excluded} for t in topics],
            "picked": [{"position": i, "no": p.matched.no, "cardTitle": p.matched.candidate.card_title,
                        "kind": p.matched.candidate.kind, "bucket": p.bucket, "reason": p.reason}
                       for i, p in enumerate(out.picked, 1)],
            "dropped": out.dropped}
    return out


def _write_wrapped(model, profile, cards, prompt, deadline=None):
    t = time.monotonic()
    res, first = _write(model, profile, cards, prompt, deadline)
    if _active is not None:
        _active["write"] = {"seconds": round(time.monotonic() - t, 1), "input": {"profile": profile, "cards": cards},
                            "output": res.model_dump(), "firstProblems": first}
    return res, first


gen.AgentSession = _Session
match_mod.judge = _judge_wrapped
gen.run_match = _run_match_wrapped
gen.select_cards = _select_wrapped
gen.write_cards = _write_wrapped


@contextmanager
def record():
    """이 안에서 부른 generate_cards 한 번의 단계 기록. 실패해도 그때까지 모은 것을 돌려준다."""
    global _active
    with _lock:
        _active = {"research": [], "match": [], "select": None, "write": None}
        try:
            yield _active
        finally:
            _active.pop("_judge", None)
            _active = None
