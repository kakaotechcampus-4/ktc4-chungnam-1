from datetime import datetime, timedelta, timezone
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from pyannote.audio.pipelines.speaker_diarization import DiarizeOutput
from pyannote.core import Annotation, Segment

from ai.api.routes.speech_analyses import run_stt_pipeline
from ai.api.schemas import SpeechAnalysisRequest
from ai.audio.providers import AudioSourceError, AudioSourceResolver, LocalAudioProvider
from ai.stt.diarization import DiarizationRuntime
from ai.stt.schemas import AsrResult, DiarizationResult, SpeechAnalysisResult
from ai.stt.service import SpeechAnalysisService
from tests.support import write_synthetic_wav


def make_asr_result() -> AsrResult:
    return AsrResult(
        analysisId="analysis_test_001",
        language="ko",
        languageProbability=1.0,
        durationMs=1_000,
        text="합성 전사",
        segments=[
            {
                "startMs": 0,
                "endMs": 1000,
                "text": "합성 전사",
                "avgLogProb": -0.1,
                "noSpeechProbability": 0.0,
                "compressionRatio": 1.0,
                "words": [
                    {
                        "startMs": 0,
                        "endMs": 1000,
                        "text": "합성 전사",
                        "probability": 0.9,
                    }
                ],
            }
        ],
    )


def make_diarization_result() -> DiarizationResult:
    return DiarizationResult(
        segments=[{"startMs": 0, "endMs": 1000, "speaker": "SPEAKER_00"}],
        exclusiveSegments=[
            {"startMs": 0, "endMs": 1000, "speaker": "SPEAKER_00"}
        ],
    )


class SpeechAnalysisServiceTest(unittest.TestCase):
    def test_runs_the_same_pipeline_for_a_local_audio_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audio_path = root / "sample.wav"
            write_synthetic_wav(audio_path)

            asr = Mock()
            asr.transcribe.return_value = make_asr_result()
            diarization = Mock()
            diarization.diarize.return_value = make_diarization_result()
            service = SpeechAnalysisService(
                audio_sources=AudioSourceResolver(
                    {"localFile": LocalAudioProvider(root, enabled=True)}
                ),
                asr=asr,
                diarization=diarization,
            )
            payload = SpeechAnalysisRequest(
                schemaVersion=1,
                analysisId="analysis_test_001",
                language="ko",
                speakerCount=1,
                audioSource={
                    "type": "localFile",
                    "audioFileName": "sample.wav",
                },
            )

            result = service.analyze(payload)

            self.assertEqual(result.schema_version, 1)
            self.assertEqual(result.text, "합성 전사")
            self.assertEqual(result.segments[0].speaker_label, "SPEAKER_00")
            asr.transcribe.assert_called_once_with(
                analysis_id="analysis_test_001",
                audio_path=audio_path,
                language="ko",
            )
            diarization.diarize.assert_called_once_with(
                audio_path=audio_path,
                speaker_count=1,
            )

    def test_rejects_an_s3_retention_period_over_24_hours(self) -> None:
        now = datetime.now(timezone.utc)
        audio_sources = Mock()
        service = SpeechAnalysisService(
            audio_sources=audio_sources,
            asr=Mock(),
            diarization=Mock(),
        )
        payload = SpeechAnalysisRequest(
            schemaVersion=1,
            analysisId="analysis_test_001",
            language="ko",
            speakerCount=1,
            audioSource={
                "type": "s3PresignedGet",
                "downloadUrl": "https://bucket.s3.amazonaws.com/audio.wav",
                "downloadUrlExpiresAt": now + timedelta(minutes=5),
                "sizeBytes": 1024,
                "sha256": "a" * 64,
            },
            dataExpiresAt=now + timedelta(hours=25),
        )

        with self.assertRaises(AudioSourceError):
            service.analyze(payload)

        audio_sources.materialize.assert_not_called()


class SpeechAnalysisRouteTest(unittest.TestCase):
    def test_returns_the_service_result_with_aliases(self) -> None:
        service = Mock()
        service.analyze.return_value = SpeechAnalysisResult(
            analysisId="analysis_test_001",
            language="ko",
            durationMs=1000,
            text="합성 전사",
            segments=[],
        )
        payload = SpeechAnalysisRequest(
            schemaVersion=1,
            analysisId="analysis_test_001",
            language="ko",
            speakerCount=1,
            audioSource={
                "type": "localFile",
                "audioFileName": "sample.wav",
            },
        )
        request = SimpleNamespace(
            app=SimpleNamespace(
                state=SimpleNamespace(speech_analysis_service=service)
            )
        )

        response = run_stt_pipeline(payload, request)

        self.assertEqual(
            response.model_dump(by_alias=True),
            {
                "schemaVersion": 1,
                "analysisId": "analysis_test_001",
                "language": "ko",
                "durationMs": 1000,
                "text": "합성 전사",
                "segments": [],
            },
        )
        service.analyze.assert_called_once()


class DiarizationRuntimeTest(unittest.TestCase):
    def test_returns_regular_and_exclusive_segments(self) -> None:
        exclusive_diarization = Annotation()
        exclusive_diarization[Segment(0.0, 1.25)] = "SPEAKER_00"
        exclusive_diarization[Segment(1.25, 2.5)] = "SPEAKER_01"
        pipeline_output = DiarizeOutput(
            speaker_diarization=exclusive_diarization,
            exclusive_speaker_diarization=exclusive_diarization,
        )
        pipeline = Mock(return_value=pipeline_output)
        runtime = DiarizationRuntime(pipeline)
        audio_path = Path("sample.wav")

        result = runtime.diarize(audio_path, speaker_count=2)

        self.assertEqual(
            result.model_dump(),
            {
                "segments": [
                    {"start_ms": 0, "end_ms": 1250, "speaker": "SPEAKER_00"},
                    {"start_ms": 1250, "end_ms": 2500, "speaker": "SPEAKER_01"},
                ],
                "exclusive_segments": [
                    {"start_ms": 0, "end_ms": 1250, "speaker": "SPEAKER_00"},
                    {"start_ms": 1250, "end_ms": 2500, "speaker": "SPEAKER_01"},
                ],
            },
        )
        pipeline.assert_called_once_with(audio_path, num_speakers=2)


if __name__ == "__main__":
    unittest.main()
