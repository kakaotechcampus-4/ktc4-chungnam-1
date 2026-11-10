from pathlib import Path
from urllib.parse import urlparse

from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, ConfigDict, Field, field_validator

from common.llm import ChatConfig, ENDPOINTS, chat_model, llm_down
from common.retry import RetryBlocked

PROMPT = Path(__file__).parent / "prompts" / "description.md"
PROMPT_VERSION = "photo-2"


class PhotoDescription(BaseModel):
    model_config = ConfigDict(extra="forbid")
    description: str = Field(min_length=1)

    @field_validator("description")
    @classmethod
    def nonblank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("사진 설명이 비어 있습니다.")
        return value.strip()


class PhotoAnalysisError(RuntimeError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def analyze_photo(download_url: str, *, model: str, api_key: str,
                  timeout_seconds: int = 120) -> PhotoDescription:
    """BE가 발급한 HTTPS URL만 받는다. URL과 응답 원문을 오류에 담지 않는다."""
    parsed = urlparse(download_url)
    if model not in ENDPOINTS or parsed.scheme != "https" or not parsed.hostname:
        raise PhotoAnalysisError("INVALID_IMAGE_REQUEST")
    try:
        llm = chat_model(ChatConfig(model=model, api_key=api_key,
                                   timeout=timeout_seconds))
        result = llm.with_structured_output(
            PhotoDescription, method="json_schema", strict=True,
        ).invoke([
            SystemMessage(PROMPT.read_text(encoding="utf-8")),
            HumanMessage(content=[
                {"type": "text", "text": "이 사진에서 직접 보이는 장면을 설명하세요."},
                {"type": "image_url", "image_url": {"url": download_url}},
            ]),
        ])
        return PhotoDescription.model_validate(result)
    except RetryBlocked as blocked:
        raise blocked.original
    except Exception as error:
        code = "LLM_UNAVAILABLE" if llm_down(error) else "INVALID_IMAGE_ANALYSIS_RESULT"
        raise PhotoAnalysisError(code) from None
