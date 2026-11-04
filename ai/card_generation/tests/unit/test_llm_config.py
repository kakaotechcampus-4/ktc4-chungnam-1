"""모델 전환의 호출 설정 검사. 외부 모델은 호출하지 않는다."""

import pytest

from common.llm import ChatConfig, ENDPOINTS, chat_model
from simulation.llm_env import config_from_env


@pytest.mark.parametrize("model", ["gpt-6-luna", "gpt-5.6-luna"])
def test_registered_models_keep_responses_streaming_and_token_limit(model):
    config = ChatConfig(model=model, api_key="synthetic-only")
    client = chat_model(config)
    payload = client._get_request_payload("합성 시험")

    assert str(client.root_client.base_url).rstrip("/") == ENDPOINTS[model]
    assert payload["model"] == model
    assert payload["max_output_tokens"] == 16000
    assert payload["reasoning"] == {"effort": "low"}
    assert payload["store"] is False
    assert payload["stream"] is True
    assert client.max_retries == 0
    assert client.request_timeout == 300
    assert "synthetic-only" not in repr(config)


def test_explicit_token_limit_and_effort_are_preserved():
    client = chat_model(ChatConfig(model="gpt-5.6-luna", api_key="synthetic-only",
                                   max_tokens=8000, effort="medium", timeout=30))
    payload = client._get_request_payload("합성 시험")
    assert payload["max_output_tokens"] == 8000
    assert payload["reasoning"] == {"effort": "medium"}
    assert client.request_timeout == 30


def test_simulation_default_and_explicit_model_override(monkeypatch):
    monkeypatch.setenv("ML_API_KEY", "synthetic-only")
    assert config_from_env().model == "gpt-6-luna"
    assert config_from_env().max_tokens == 16000
    assert config_from_env(model="gpt-5.6-luna").model == "gpt-5.6-luna"


def test_unknown_model_is_not_silently_replaced():
    with pytest.raises(ValueError, match="모르는 모델"):
        chat_model(ChatConfig(model="unregistered", api_key="synthetic-only"))


def test_missing_key_still_rejects_request():
    with pytest.raises(RuntimeError, match="키가 필요"):
        chat_model(ChatConfig(model="gpt-6-luna", api_key=""))
