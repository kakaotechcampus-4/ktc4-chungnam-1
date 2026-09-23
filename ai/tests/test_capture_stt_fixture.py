from pathlib import Path
import tempfile
import unittest

from ai.api.schemas import LocalSpeechAnalysisRequest
from scripts.capture_stt_fixture import write_fixture
from ai.stt.alignment import align_asr_and_diarization
from ai.stt.schemas import AsrResult, DiarizationResult, SpeechAnalysisResult


FIXTURE_DIRECTORY = Path(__file__).parent / "fixtures" / "alignment"


class WriteFixtureTest(unittest.TestCase):
    def test_writes_reusable_model_outputs_and_refuses_silent_overwrite(self) -> None:
        payload = LocalSpeechAnalysisRequest(
            analysisId="analysis_alignment_fixture",
            speakerCount=2,
            audioFileName="synthetic.wav",
        )
        asr_result = AsrResult.model_validate_json(
            (FIXTURE_DIRECTORY / "asr.json").read_text(encoding="utf-8")
        )
        diarization_result = DiarizationResult.model_validate_json(
            (FIXTURE_DIRECTORY / "diarization.json").read_text(encoding="utf-8")
        )
        combined_result = align_asr_and_diarization(
            asr_result,
            diarization_result,
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            output_directory = Path(temporary_directory)
            write_fixture(
                output_directory,
                payload,
                asr_result,
                diarization_result,
                combined_result,
                overwrite=False,
            )

            self.assertEqual(
                {path.name for path in output_directory.iterdir()},
                {"asr.json", "diarization.json", "combined.json", "metadata.json"},
            )
            saved_combined = SpeechAnalysisResult.model_validate_json(
                (output_directory / "combined.json").read_text(encoding="utf-8")
            )
            self.assertEqual(saved_combined, combined_result)

            with self.assertRaises(FileExistsError):
                write_fixture(
                    output_directory,
                    payload,
                    asr_result,
                    diarization_result,
                    combined_result,
                    overwrite=False,
                )


if __name__ == "__main__":
    unittest.main()
