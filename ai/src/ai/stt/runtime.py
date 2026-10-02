from pathlib import Path

from faster_whisper import WhisperModel

from ai.stt.schemas import AsrResult, AsrSegment, AsrWord


class AsrRuntime:
    """Whisper 모델을 한 번 불러오고 WAV 파일을 전사한다."""

    def __init__(self) -> None:
        self.model = WhisperModel(
            "large-v3-turbo",
            device="cuda",
            compute_type="float16",
        )

    def transcribe(
        self,
        analysis_id: str,
        audio_path: Path,
        language: str,
    ) -> AsrResult:
        """WAV 파일을 전사하고 API에서 반환할 ASR 결과를 만든다."""

        segments, info = self.model.transcribe(
            str(audio_path),
            language=language,
            word_timestamps=True,
        )

        asr_segments: list[AsrSegment] = []

        for segment in segments:
            words = [
                AsrWord(
                    startMs=round(word.start * 1000),
                    endMs=round(word.end * 1000),
                    text=word.word.strip(),
                    probability=word.probability,
                )
                for word in segment.words or []
            ]

            asr_segments.append(
                AsrSegment(
                    startMs=round(segment.start * 1000),
                    endMs=round(segment.end * 1000),
                    text=segment.text.strip(),
                    avgLogProb=segment.avg_logprob,
                    noSpeechProbability=segment.no_speech_prob,
                    compressionRatio=segment.compression_ratio,
                    words=words,
                )
            )

        full_text = " ".join(segment.text for segment in asr_segments)

        return AsrResult(
            analysisId=analysis_id,
            language=info.language,
            languageProbability=info.language_probability,
            durationMs=round(info.duration * 1000),
            text=full_text,
            segments=asr_segments,
        )
