"""엘리스 Claude 연결 준비. 운영 GPT 경로나 자동 전환에 등록하지 않는다.

사용자 제공 엘리스 API 설명(2026-11-11)에서 모델 별칭, Chat Completions,
구조화 출력과 도구 호출 지원을 확인했다. 실제 주소와 연동 동작은 미검증이다.
"""
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from common.llm import RetryingChatOpenAI


@dataclass(frozen=True)
class EliceClaudeConfig:
    base_url: str = field(repr=False)
    api_key: str = field(repr=False)
    model: str = "anthropic/claude-haiku-5-5"
    timeout: float = 120
    max_tokens: int = 16000


def elice_claude_model(config: EliceClaudeConfig) -> RetryingChatOpenAI:
    """확인한 엘리스 주소를 명시해야 생성 가능. 키를 다른 호스트로 보내지 않는다."""
    url = urlsplit(config.base_url)
    if (url.scheme != "https" or url.hostname != "mlapi.run" or url.username
            or url.password or url.query or url.fragment or url.port not in (None, 443)
            or not url.path.rstrip("/").endswith("/v1")):
        raise ValueError("확인된 https://mlapi.run/.../v1 엘리스 호출 주소가 필요합니다")
    if not config.api_key or not config.model or config.timeout <= 0 or config.max_tokens <= 0:
        raise ValueError("Claude 모델, 키와 양수인 호출 제한이 필요합니다")
    return RetryingChatOpenAI(
        model=config.model, base_url=config.base_url, api_key=config.api_key,
        timeout=config.timeout, max_tokens=config.max_tokens, max_retries=0,
        # 제공 문서의 허용 목록에 없는 stream_options·GPT 전용 추론 옵션을 보내지 않는다.
        use_responses_api=False, streaming=True, stream_usage=False,
    )
