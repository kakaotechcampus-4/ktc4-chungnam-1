from pathlib import Path

from faster_whisper import WhisperModel

from stt_server.progress import logger as progress_logger
from stt_server.runtime_settings import RuntimeSettings
from stt_server.stt.schemas import AsrResult, AsrSegment, AsrWord


class AsrRuntime:
    """Whisper 모델을 한 번 불러오고 WAV 파일을 전사한다."""

    def __init__(self, settings: RuntimeSettings | None = None) -> None:
        settings = settings if settings is not None else RuntimeSettings.from_environment()
        self.settings = settings
        self.model = WhisperModel(
            "large-v3-turbo",
            device="cuda",
            device_index=settings.cuda_device_index,
            compute_type=settings.asr_compute_type,
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
            vad_filter=self.settings.asr_vad_filter,
            condition_on_previous_text=self.settings.asr_condition_on_previous_text,
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
        # VAD가 말소리를 얼마나 남겼는지 길이만 남긴다(전사 내용과 파일 이름은 남기지 않음).
        # 빈 전사가 늘었을 때 VAD 때문인지(소리가 작은지) 가를 수 있게 한다.
        progress_logger.info(
            "stage=asr_vad vad=%s duration_s=%.1f after_vad_s=%.1f segments=%d",
            self.settings.asr_vad_filter,
            info.duration,
            getattr(info, "duration_after_vad", info.duration),
            len(asr_segments),
        )

        return AsrResult(
            analysisId=analysis_id,
            language=info.language,
            languageProbability=info.language_probability,
            durationMs=round(info.duration * 1000),
            text=full_text,
            segments=asr_segments,
        )
