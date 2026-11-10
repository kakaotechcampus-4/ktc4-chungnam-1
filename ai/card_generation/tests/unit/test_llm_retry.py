"""합성 장애·로컬 HTTP 대역만 사용하며 외부 API는 호출하지 않는다."""
import importlib

import httpx2 as httpx
import openai
import pytest
from langchain_openai import ChatOpenAI
from langchain_core.messages import AIMessageChunk
from langchain_core.outputs import ChatGenerationChunk
from pydantic import BaseModel

from common.elice_claude import ELICE_CLAUDE_BASE_URL, EliceClaudeConfig, elice_claude_model
from common.llm import ChatConfig, chat_model
from common.retry import RetryBlocked, invoke_with_retry, retry_scope
from common.structured import invoke_structured

retry = importlib.import_module("common.retry")


def error(status=503, code=None, headers=None):
    response = httpx.Response(status, headers=headers or {},
                              request=httpx.Request("POST", "https://synthetic.invalid/v1"))
    return openai.APIStatusError("synthetic", response=response, body={"error": {"code": code}})


@pytest.fixture
def clock(monkeypatch):
    class Clock:
        now = 0.0

        def __init__(self):
            self.waits = []

        def sleep(self, delay):
            self.waits.append(delay)
            self.now += delay

    clock = Clock()
    monkeypatch.setattr(retry.time, "monotonic", lambda: clock.now)
    monkeypatch.setattr(retry.time, "sleep", clock.sleep)
    monkeypatch.setattr(retry.random, "uniform", lambda *_: 1.0)
    return clock


@pytest.mark.parametrize("enabled,count", [(False, 1), (True, 2)])
def test_retry_never_exceeds_one(clock, enabled, count):
    calls = []

    def fail(timeout):
        calls.append(timeout)
        raise error()

    with retry_scope(enabled=enabled), pytest.raises(openai.APIStatusError):
        invoke_with_retry(fail, timeout=10)
    assert len(calls) == count
    assert calls[-1] == 10 - (count - 1)


@pytest.mark.parametrize("status,code", [(400, None), (401, None), (403, None),
                                        (429, "insufficient_quota"),
                                        (429, "organization_usage_limit_exceeded")])
def test_permanent_error_is_not_retried(clock, status, code):
    def fail(timeout):
        raise error(status, code)

    with retry_scope(enabled=True), pytest.raises(openai.APIStatusError):
        invoke_with_retry(fail, timeout=10)
    assert clock.waits == []


@pytest.mark.parametrize("status", [408, 429, 500, 502, 503, 504])
def test_transient_failure_then_success_shares_deadline(clock, status):
    calls = []

    def call(timeout):
        calls.append(timeout)
        if len(calls) == 1:
            clock.now += 2
            raise error(status)
        return "ok"

    with retry_scope(enabled=True):
        assert invoke_with_retry(call, timeout=10) == "ok"
    assert calls == [10, 7]


def test_retry_after_waits_or_skips_retry_when_budget_is_short(clock):
    calls = []

    def call(timeout):
        calls.append(timeout)
        if len(calls) == 1:
            raise error(429, headers={"retry-after": "4"})
        return "ok"

    with retry_scope(enabled=True):
        assert invoke_with_retry(call, timeout=10) == "ok"
    assert clock.waits == [4]
    calls.clear()
    with retry_scope(enabled=True), pytest.raises(openai.APIStatusError):
        invoke_with_retry(call, timeout=3)
    assert len(calls) == 1


def test_cancelled_job_blocks_second_send(clock):
    calls = []
    blocked = RuntimeError("synthetic inactive job")

    def fail(timeout):
        calls.append(timeout)
        raise error()

    def check(_):
        raise blocked

    with retry_scope(enabled=True, before_retry=check), pytest.raises(RetryBlocked) as caught:
        invoke_with_retry(fail, timeout=10)
    assert caught.value.original is blocked
    assert len(calls) == 1


def test_timeout_does_not_get_another_full_timeout(clock):
    calls = []

    def fail(timeout):
        calls.append(timeout)
        clock.now += 10
        raise error()

    with retry_scope(enabled=True), pytest.raises(openai.APIStatusError):
        invoke_with_retry(fail, timeout=10)
    assert len(calls) == 1


def test_outer_deadline_and_nested_policy_are_preserved(clock):
    calls = []

    def call(timeout):
        calls.append(timeout)
        if len(calls) == 1:
            raise error()
        return "ok"

    with retry_scope(enabled=True), retry_scope(remaining=lambda: 3 - clock.now):
        assert invoke_with_retry(call, timeout=10) == "ok"
    assert calls == [3, 2]


def test_langchain_internal_stream_error_is_retried_once(monkeypatch, clock):
    calls = []

    def stream(self, messages, stop=None, **kwargs):
        calls.append(kwargs["timeout"])
        raise error()
        yield

    monkeypatch.setattr(ChatOpenAI, "_stream", stream)
    model = chat_model(ChatConfig(model="gpt-6-luna", api_key="synthetic", timeout=10))
    with retry_scope(enabled=True), pytest.raises(openai.APIStatusError):
        model.invoke("합성 입력")
    assert calls == [10, 9]


def test_partial_stream_is_discarded_before_successful_retry(monkeypatch, clock):
    calls = []

    def stream(self, messages, stop=None, **kwargs):
        calls.append(kwargs["timeout"])
        if len(calls) == 1:
            yield ChatGenerationChunk(message=AIMessageChunk(content="버릴 합성 조각"))
            raise error()
        yield ChatGenerationChunk(message=AIMessageChunk(content="완료된 합성 응답"))

    monkeypatch.setattr(ChatOpenAI, "_stream", stream)
    model = chat_model(ChatConfig(model="gpt-6-luna", api_key="synthetic", timeout=10))
    with retry_scope(enabled=True):
        assert model.invoke("합성 입력").content == "완료된 합성 응답"
    assert len(calls) == 2


def test_structured_attempts_do_not_multiply_transport_retries(monkeypatch, clock):
    calls = []

    class Answer(BaseModel):
        word: str

    def stream(self, messages, stop=None, **kwargs):
        calls.append(1)
        raise error()
        yield

    monkeypatch.setattr(ChatOpenAI, "_stream", stream)
    model = chat_model(ChatConfig(model="gpt-6-luna", api_key="synthetic", timeout=10))
    with retry_scope(enabled=True), pytest.raises(openai.APIStatusError):
        invoke_structured(model, Answer, [("user", "합성 입력")], "합성", attempts=3)
    assert len(calls) == 2


def test_claude_uses_chat_completions_without_gpt_reasoning_settings():
    config = EliceClaudeConfig(base_url="https://mlapi.run/synthetic/v1", api_key="synthetic-only")
    model = elice_claude_model(config)
    payload = model._get_request_payload("합성 입력")
    assert payload["model"] == "anthropic/claude-haiku-5-5"
    assert model.use_responses_api is False
    assert model.max_retries == 0
    assert "reasoning" not in payload and "include" not in payload
    assert "stream_options" not in payload
    assert payload["max_completion_tokens"] == 16000
    assert "synthetic-only" not in repr(config)


def test_claude_default_uses_user_provided_elice_address_without_network():
    model = elice_claude_model(EliceClaudeConfig(api_key="synthetic-only"))
    assert str(model.root_client.base_url).rstrip("/") == ELICE_CLAUDE_BASE_URL
    assert model.model_name == "anthropic/claude-haiku-5-5"


@pytest.mark.parametrize("url", ["https://api.openai.com/v1", "http://mlapi.run/id/v1",
                                  "https://mlapi.run.attacker.invalid/id/v1",
                                  "https://user:password@mlapi.run/id/v1"])
def test_claude_rejects_non_elice_urls(url):
    with pytest.raises(ValueError):
        elice_claude_model(EliceClaudeConfig(base_url=url, api_key="synthetic"))


def test_actual_sdk_mock_transport_retries_without_network(clock):
    seen = []

    def handler(request):
        seen.append(request)
        if len(seen) == 1:
            return httpx.Response(503, json={"error": {"message": "synthetic"}})
        return httpx.Response(200, json={
            "id": "synthetic", "object": "chat.completion", "created": 0,
            "model": "anthropic/claude-haiku-5-5",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "합성 응답"},
                         "finish_reason": "stop"}],
        })

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        model = elice_claude_model(EliceClaudeConfig(base_url="https://mlapi.run/synthetic/v1",
                                                   api_key="synthetic"))
        sdk = openai.OpenAI(base_url="https://mlapi.run/synthetic/v1", api_key="synthetic",
                            max_retries=0, http_client=client)
        model.root_client, model.client = sdk, sdk.chat.completions
        model.streaming = False
        with retry_scope(enabled=True):
            assert model.invoke("합성 입력").content == "합성 응답"
    assert len(seen) == 2
    assert all(r.url.path.endswith("/chat/completions") for r in seen)
    assert seen[1].extensions["timeout"]["read"] < seen[0].extensions["timeout"]["read"]
