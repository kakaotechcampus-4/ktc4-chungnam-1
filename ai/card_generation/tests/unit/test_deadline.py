"""전체 제한 시간 검증 (실제 LLM 미호출)."""

import time

import pytest
from langchain_core.language_models import GenericFakeChatModel
from langchain_core.messages import AIMessage

from card_generation._steps.deadline import (
    Deadline,
    TimeLimitExceeded,
    _StopStreaming,
)
from card_generation.contract import (
    CardContext,
    CardGenerationError,
    GenerationRequest,
)
from card_generation.generate import generate_cards
from common.llm import ChatConfig

CONFIG = ChatConfig(model="gpt-5.6-luna", api_key="x", timeout=120)


def test_call_gets_remaining_time_as_timeout():
    assert Deadline(CONFIG, 30).model("문안 작성").request_timeout <= 30


def test_no_new_call_after_time_limit():
    with pytest.raises(TimeLimitExceeded):
        Deadline(CONFIG, 0).model("연결 판정")


def test_streaming_call_is_cut_after_time_limit():
    deadline = Deadline(CONFIG, 30)
    model = GenericFakeChatModel(
        messages=iter([AIMessage(content="하나 둘 셋")]),
        callbacks=[_StopStreaming(deadline, "문안 작성")],
    )
    deadline.end = time.monotonic() - 1
    with pytest.raises(TimeLimitExceeded):
        list(model.stream("질문"))


def test_generate_cards_fails_as_llm_unavailable_at_time_limit():
    request = GenerationRequest(
        model="gpt-5.6-luna",
        prompt_version=1,
        context=CardContext.model_validate(
            {"ageRange": "80s", "profileFacts": {}}
        ),
    )
    with pytest.raises(CardGenerationError) as e:
        generate_cards(request, api_key="x", time_limit=0)
    assert e.value.code == "LLM_UNAVAILABLE"
