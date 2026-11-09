"""common.structured의 토큰 수 모으기. 실제 모델 없이 LangChain 응답 형식만 흉내 냄."""

import pytest
from langchain_core.messages import AIMessage
from pydantic import BaseModel

from common.structured import add_usage, invoke_structured


class _Shape(BaseModel):
    title: str


class _FakeRunnable:
    def __init__(self, outputs):
        self.outputs = outputs

    def invoke(self, messages):
        return self.outputs.pop(0)


class _FakeModel:
    """with_structured_output에 넘긴 옵션을 기록하고, 정해 둔 응답을 차례로 돌려줌."""

    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.options: dict = {}

    def with_structured_output(self, schema, **options):
        self.options = options
        return _FakeRunnable(self.outputs)


def _raw(input_tokens: int, output_tokens: int, reasoning: int | None = None) -> AIMessage:
    details = {} if reasoning is None else {"reasoning": reasoning}
    return AIMessage(content="", usage_metadata={"input_tokens": input_tokens, "output_tokens": output_tokens,
                                                 "total_tokens": input_tokens + output_tokens,
                                                 "output_token_details": details})


def test_without_usage_the_call_is_unchanged():
    model = _FakeModel([_Shape(title="합성")])
    assert invoke_structured(model, _Shape, [], "시험").title == "합성"
    assert model.options == {"method": "json_schema", "strict": True, "include_raw": False}


def test_usage_adds_tokens_of_retried_responses_too():
    broken = {"raw": _raw(5, 7, reasoning=3), "parsed": None, "parsing_error": ValueError("형식 깨짐")}
    good = {"raw": _raw(5, 9, reasoning=4), "parsed": _Shape(title="합성"), "parsing_error": None}
    model, usage, retries = _FakeModel([broken, good]), {}, []
    out = invoke_structured(model, _Shape, [], "시험", 2, retries.append, usage=usage)
    assert out.title == "합성" and model.options["include_raw"] is True
    assert usage == {"calls": 2, "input_tokens": 10, "output_tokens": 16, "total_tokens": 26, "reasoning_tokens": 7}
    assert [r["attempt"] for r in retries] == ["1"]


def test_format_error_is_raised_when_attempts_run_out():
    model, usage = _FakeModel([{"raw": _raw(1, 1), "parsed": None, "parsing_error": ValueError("형식 깨짐")}]), {}
    with pytest.raises(ValueError, match="형식 깨짐"):
        invoke_structured(model, _Shape, [], "시험", usage=usage)
    assert usage["calls"] == 1


def test_response_without_token_counts_only_counts_the_call():
    usage: dict[str, int] = {}
    add_usage(usage, AIMessage(content=""))
    add_usage(usage, None)
    assert usage == {"calls": 2}


def test_cut_off_response_is_counted_without_content():
    """출력 한도에 걸려 끊긴 응답은 incomplete_responses로 셈. 글은 보지 않음."""
    usage: dict[str, int] = {}
    cut = _raw(100, 16000)
    cut.response_metadata = {"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}}
    add_usage(usage, cut)
    add_usage(usage, _raw(10, 20))
    assert usage["incomplete_responses"] == 1
    assert usage["calls"] == 2


def test_failed_generation_keeps_token_usage():
    """형식이 깨져 실패해도 그때까지의 토큰 수가 오류에 담겨 처리 기록으로 감."""
    from common.visit_report import VisitReportError
    import report_generation.generate as rg

    cut = _raw(100, 16000)
    cut.response_metadata = {"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}}
    model = _FakeModel([{"raw": cut, "parsed": None, "parsing_error": ValueError("잘린 JSON")}])
    original = rg.chat_model
    rg.chat_model = lambda config: model
    try:
        with pytest.raises(VisitReportError) as caught:
            rg.generate_report(_report_request(), model=next(iter(rg.ENDPOINTS)), api_key="test")
    finally:
        rg.chat_model = original
    assert caught.value.token_usage["incomplete_responses"] == 1


def _report_request():
    from report_generation.tests.test_report import request
    return request("positive")
