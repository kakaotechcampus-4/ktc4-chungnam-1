from pathlib import Path
from typing import Any

from ai.stt.schemas import DiarizationResult, DiarizationSegment


class DiarizationRuntime:
    """로드된 pyannote 파이프라인으로 화자 구간을 생성한다."""

    def __init__(self, pipeline: Any) -> None:
        self._pipeline = pipeline

    def diarize(
        self,
        audio_path: Path,
        speaker_count: int,
    ) -> DiarizationResult:
        output = self._pipeline(
            audio_path,
            num_speakers=speaker_count,
        )

        segments = [
            DiarizationSegment(
                startMs=round(turn.start * 1000),
                endMs=round(turn.end * 1000),
                speaker=str(speaker),
            )
            for turn, speaker in output.speaker_diarization
        ]
        exclusive_segments = [
            DiarizationSegment(
                startMs=round(turn.start * 1000),
                endMs=round(turn.end * 1000),
                speaker=str(speaker),
            )
            for turn, speaker in output.exclusive_speaker_diarization
        ]

        return DiarizationResult(
            segments=segments,
            exclusiveSegments=exclusive_segments,
        )
