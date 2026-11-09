from datetime import UTC, datetime
from typing import Literal
from urllib.parse import urlsplit

from pydantic import AwareDatetime, Field, PrivateAttr, field_validator, model_validator

from app.schemas.common import ApiModel

# 결과를 돌려준 STT 서버. 기본 서버에 연결하지 못해 예비 서버로 보낸 경우가 `backup`이다.
SttServer = Literal["primary", "backup"]


class S3AudioSource(ApiModel):
    """AI 서버가 다운로드할 S3 음성 파일 정보."""

    type: Literal["s3PresignedGet"]
    download_url: str = Field(alias="downloadUrl", min_length=1)
    download_url_expires_at: AwareDatetime = Field(
        alias="downloadUrlExpiresAt"
    )
    size_bytes: int = Field(alias="sizeBytes", gt=0)
    sha256: str = Field(pattern=r"^[0-9a-fA-F]{64}$")

    @field_validator("download_url")
    @classmethod
    def _require_https(cls, value: str) -> str:
        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.hostname:
            raise ValueError("downloadUrl은 HTTPS URL이어야 합니다.")
        return value


class SpeechAnalysisRequest(ApiModel):
    """백엔드가 AI 서버에 전달하는 STT·화자 분리 요청."""

    schema_version: Literal[1] = Field(alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId", min_length=1, max_length=128)
    language: Literal["ko"] = "ko"
    speaker_count: int = Field(alias="speakerCount", ge=1, le=8)
    audio_source: S3AudioSource = Field(alias="audioSource")
    data_expires_at: AwareDatetime = Field(alias="dataExpiresAt")

    @model_validator(mode="after")
    def _validate_expirations(self) -> "SpeechAnalysisRequest":
        now = datetime.now(UTC)
        if self.audio_source.download_url_expires_at <= now:
            raise ValueError("downloadUrlExpiresAt이 이미 지났습니다.")
        if self.data_expires_at <= now:
            raise ValueError("dataExpiresAt이 이미 지났습니다.")
        if self.audio_source.download_url_expires_at > self.data_expires_at:
            raise ValueError(
                "downloadUrlExpiresAt은 dataExpiresAt보다 늦을 수 없습니다."
            )
        return self


class SpeechAnalysisWord(ApiModel):
    start_ms: int = Field(alias="startMs", ge=0)
    end_ms: int = Field(alias="endMs", ge=0)
    text: str
    probability: float = Field(ge=0.0, le=1.0)


class SpeechAnalysisSegment(ApiModel):
    start_ms: int = Field(alias="startMs", ge=0)
    end_ms: int = Field(alias="endMs", ge=0)
    speaker_label: str | None = Field(alias="speakerLabel")
    text: str
    words: list[SpeechAnalysisWord]


class SpeechAnalysisResult(ApiModel):
    """AI 서버에서 검증해 받은 STT·화자 분리 성공 결과."""

    schema_version: Literal[1] = Field(alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    language: Literal["ko"]
    duration_ms: int = Field(alias="durationMs", ge=0)
    text: str
    segments: list[SpeechAnalysisSegment]

    # 처리 기록용. JSON으로 읽고 쓰지 않으며 `AiServerClient`가 채운다. `model_copy`로 만든 결과도
    # 이어받는다. 저장된 전사로 다시 만든 결과는 `None`이다.
    _stt_server: SttServer | None = PrivateAttr(default=None)

    @property
    def stt_server(self) -> SttServer | None:
        return self._stt_server

    def served_by(self, server: SttServer) -> "SpeechAnalysisResult":
        """결과를 돌려준 STT 서버를 적고 자신을 돌려준다."""
        self._stt_server = server
        return self


SpeechAnalysisPublicStatus = Literal[
    "queued",
    "transcribing",
    "sttCompleted",
    "generatingReport",
    "completed",
    "failed",
]


class SpeechAnalysisAccepted(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    session_id: str = Field(alias="sessionId")
    status: Literal[
        "queued", "transcribing", "sttCompleted", "generatingReport"
    ] = "queued"


class SpeechAnalysisStatusResponse(ApiModel):
    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    session_id: str = Field(alias="sessionId")
    status: SpeechAnalysisPublicStatus
    error_code: str | None = Field(default=None, alias="errorCode")
