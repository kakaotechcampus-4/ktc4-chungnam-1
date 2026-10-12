from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


class ApiModel(BaseModel):
    """공통 API 모델 설정."""

    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class S3AudioSource(ApiModel):
    """S3 Presigned GET URL로 전달되는 운영용 음성 입력."""

    type: Literal["s3PresignedGet"]
    download_url: str = Field(alias="downloadUrl", min_length=1)
    download_url_expires_at: datetime = Field(alias="downloadUrlExpiresAt")
    size_bytes: int = Field(alias="sizeBytes", gt=0)
    sha256: str = Field(pattern=r"^[0-9a-fA-F]{64}$")

    @field_validator("download_url")
    @classmethod
    def validate_download_url(cls, value: str) -> str:
        """서명된 쿼리를 바꾸지 않고 HTTPS URL의 기본 형태만 검증한다."""

        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.hostname:
            raise ValueError("downloadUrl은 유효한 HTTPS URL이어야 합니다.")
        return value

    @field_validator("download_url_expires_at")
    @classmethod
    def validate_download_url_expiry(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("downloadUrlExpiresAt에는 시간대가 포함되어야 합니다.")
        return value


class LocalAudioSource(ApiModel):
    """허가된 로컬 WAV 폴더를 사용하는 개발·테스트용 음성 입력."""

    type: Literal["localFile"]
    audio_file_name: str = Field(alias="audioFileName", min_length=1)


AudioSource = Annotated[
    S3AudioSource | LocalAudioSource,
    Field(discriminator="type"),
]


class SpeechAnalysisRequest(ApiModel):
    """백엔드 또는 로컬 개발 환경에서 보내는 음성 분석 요청."""

    schema_version: Literal[1] = Field(alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId", min_length=1, max_length=128)
    language: Literal["ko"] = "ko"
    speaker_count: int = Field(alias="speakerCount", ge=1)
    audio_source: AudioSource = Field(alias="audioSource")
    data_expires_at: datetime | None = Field(default=None, alias="dataExpiresAt")

    @model_validator(mode="after")
    def validate_source_specific_fields(self) -> SpeechAnalysisRequest:
        if self.data_expires_at is not None:
            if (
                self.data_expires_at.tzinfo is None
                or self.data_expires_at.utcoffset() is None
            ):
                raise ValueError("dataExpiresAt에는 시간대가 포함되어야 합니다.")

        if isinstance(self.audio_source, S3AudioSource):
            if self.data_expires_at is None:
                raise ValueError("S3 요청에는 dataExpiresAt이 필요합니다.")
            if self.audio_source.download_url_expires_at > self.data_expires_at:
                raise ValueError(
                    "downloadUrlExpiresAt은 dataExpiresAt보다 늦을 수 없습니다."
                )
        elif self.data_expires_at is not None:
            raise ValueError(
                "로컬 파일 요청에는 dataExpiresAt을 전달하지 않습니다."
            )
        return self


class LocalSpeechAnalysisRequest(ApiModel):
    """기존 로컬 실행 스크립트를 위한 호환 요청 모델."""

    analysis_id: str = Field(alias="analysisId", min_length=1, max_length=128)
    language: Literal["ko"] = "ko"
    speaker_count: int = Field(default=2, alias="speakerCount", ge=1)
    audio_file_name: str = Field(
        default="generated/A0051_S0001_0_G0101_G0102.wav",
        alias="audioFileName",
        min_length=1,
    )

    def to_speech_analysis_request(self) -> SpeechAnalysisRequest:
        """운영 파이프라인과 동일한 요청 형태로 변환한다."""

        return SpeechAnalysisRequest(
            schemaVersion=1,
            analysisId=self.analysis_id,
            language=self.language,
            speakerCount=self.speaker_count,
            audioSource={
                "type": "localFile",
                "audioFileName": self.audio_file_name,
            },
        )
