"""시뮬레이션과 평가에서 쓰는 모델 설정. 환경 변수에서 키를 읽음.

backend는 이 모듈을 쓰지 않고 자기 설정으로 ChatConfig를 만듦.
"""

from __future__ import annotations

import os

from common.llm import ChatConfig

MODEL = "gpt-5.6-luna"
API_KEY_ENV = "ML_API_KEY"


def config_from_env(**overrides) -> ChatConfig:
    key = os.environ.get(API_KEY_ENV, "")
    if not key:
        raise RuntimeError(f"{API_KEY_ENV}가 없습니다")
    return ChatConfig(**{"model": MODEL, "api_key": key, **overrides})
