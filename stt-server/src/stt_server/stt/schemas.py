from typing import Literal

from pydantic import BaseModel, Field


class AsrWord(BaseModel):
    """Whisper가 인식한 단어 하나의 결과.

    Attributes:
        start_ms: 단어 발화가 시작된 시각을 밀리초로 나타낸 값이다.
        end_ms: 단어 발화가 끝난 시각을 밀리초로 나타낸 값이다.
        text: Whisper가 인식한 단어 문자열이다.
        probability: Whisper가 계산한 단어의 인식 확률이다.
    """

    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    text: str
    probability: float


class AsrSegment(BaseModel):
    """Whisper가 구분한 전사 구간 하나의 결과.

    Attributes:
        start_ms: 전사 구간이 시작된 시각을 밀리초로 나타낸 값이다.
        end_ms: 전사 구간이 끝난 시각을 밀리초로 나타낸 값이다.
        text: 해당 구간에서 인식된 전체 문장이다.
        avg_log_prob: 해당 구간 토큰들의 평균 로그 확률이다.
        no_speech_probability: 해당 구간이 음성이 아닐 확률이다.
        compression_ratio: 반복적인 전사 결과를 확인할 때 사용하는 압축률이다.
        words: 해당 구간에 포함된 단어별 전사 결과다.
    """

    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    text: str
    avg_log_prob: float = Field(alias="avgLogProb")
    no_speech_probability: float = Field(alias="noSpeechProbability")
    compression_ratio: float = Field(alias="compressionRatio")
    words: list[AsrWord]


class AsrResult(BaseModel):
    """음성 파일 하나에 대한 전체 Whisper 전사 결과.

    Attributes:
        analysis_id: 요청에서 전달받은 음성 분석 작업의 식별자다.
        language: Whisper가 전사에 사용한 언어 코드다.
        language_probability: Whisper가 계산한 언어 감지 확률이다.
        duration_ms: 입력 음성의 전체 길이를 밀리초로 나타낸 값이다.
        text: 모든 전사 구간을 합친 전체 텍스트다.
        segments: 시간순으로 정렬된 전사 구간 목록이다.
    """

    analysis_id: str = Field(alias="analysisId")
    language: str
    language_probability: float = Field(alias="languageProbability")
    duration_ms: int = Field(alias="durationMs")
    text: str
    segments: list[AsrSegment]


class DiarizationSegment(BaseModel):
    """화자 분리 모델이 찾은 한 화자의 연속된 발화 구간."""

    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    speaker: str


class DiarizationResult(BaseModel):
    """일반 구간과 ASR 정렬용 exclusive 구간을 함께 보존한 결과."""

    segments: list[DiarizationSegment]
    exclusive_segments: list[DiarizationSegment] = Field(alias="exclusiveSegments")


class SpeakerTranscriptSegment(BaseModel):
    """동일한 diarization 발화 구간에 배정된 전사 결과."""

    start_ms: int = Field(alias="startMs")
    end_ms: int = Field(alias="endMs")
    speaker_label: str | None = Field(alias="speakerLabel")
    text: str
    words: list[AsrWord]


class SpeechAnalysisResult(BaseModel):
    """ASR과 화자 분리 결과를 시간축으로 결합한 최종 결과."""

    schema_version: Literal[1] = Field(default=1, alias="schemaVersion")
    analysis_id: str = Field(alias="analysisId")
    language: str
    duration_ms: int = Field(alias="durationMs")
    text: str
    segments: list[SpeakerTranscriptSegment]
