from pathlib import Path
import unittest

from ai.stt.alignment import align_asr_and_diarization
from ai.stt.schemas import (
    AsrResult,
    DiarizationResult,
    SpeechAnalysisResult,
)


FIXTURE_DIRECTORY = Path(__file__).parent / "fixtures" / "alignment"


def load_fixture(model_type: type, name: str):
    return model_type.model_validate_json(
        (FIXTURE_DIRECTORY / name).read_text(encoding="utf-8")
    )


def make_asr_result(words: list[dict]) -> AsrResult:
    start_ms = min(word["startMs"] for word in words)
    end_ms = max(word["endMs"] for word in words)
    return AsrResult(
        analysisId="analysis_boundary_test",
        language="ko",
        languageProbability=1.0,
        durationMs=max(3000, end_ms),
        text=" ".join(word["text"] for word in words),
        segments=[
            {
                "startMs": start_ms,
                "endMs": end_ms,
                "text": " ".join(word["text"] for word in words),
                "avgLogProb": -0.1,
                "noSpeechProbability": 0.0,
                "compressionRatio": 1.0,
                "words": [
                    {**word, "probability": 0.9}
                    for word in words
                ],
            }
        ],
    )


class AlignAsrAndDiarizationTest(unittest.TestCase):
    def test_aligns_fixture_by_exclusive_diarization_turn(self) -> None:
        asr_result = load_fixture(AsrResult, "asr.json")
        diarization_result = load_fixture(DiarizationResult, "diarization.json")
        expected = load_fixture(SpeechAnalysisResult, "expected.json")

        result = align_asr_and_diarization(asr_result, diarization_result)

        self.assertEqual(
            result.model_dump(by_alias=True),
            expected.model_dump(by_alias=True),
        )

    def test_leaves_an_equal_cross_speaker_overlap_unassigned(self) -> None:
        asr_result = make_asr_result(
            [{"startMs": 900, "endMs": 1100, "text": "경계"}]
        )
        diarization_result = DiarizationResult(
            segments=[],
            exclusiveSegments=[
                {"startMs": 0, "endMs": 1000, "speaker": "SPEAKER_00"},
                {"startMs": 1000, "endMs": 2000, "speaker": "SPEAKER_01"},
            ],
        )

        result = align_asr_and_diarization(asr_result, diarization_result)

        self.assertIsNone(result.segments[0].speaker_label)

    def test_leaves_a_word_outside_all_speech_turns_unassigned(self) -> None:
        asr_result = make_asr_result(
            [{"startMs": 2000, "endMs": 2300, "text": "외부"}]
        )
        diarization_result = DiarizationResult(
            segments=[],
            exclusiveSegments=[
                {"startMs": 0, "endMs": 1000, "speaker": "SPEAKER_00"}
            ],
        )

        result = align_asr_and_diarization(asr_result, diarization_result)

        self.assertIsNone(result.segments[0].speaker_label)

    def test_does_not_merge_separate_turns_with_the_same_speaker(self) -> None:
        asr_result = make_asr_result(
            [
                {"startMs": 100, "endMs": 400, "text": "첫째"},
                {"startMs": 2100, "endMs": 2400, "text": "둘째"},
            ]
        )
        diarization_result = DiarizationResult(
            segments=[],
            exclusiveSegments=[
                {"startMs": 0, "endMs": 1000, "speaker": "SPEAKER_00"},
                {"startMs": 2000, "endMs": 3000, "speaker": "SPEAKER_00"},
            ],
        )

        result = align_asr_and_diarization(asr_result, diarization_result)

        self.assertEqual(len(result.segments), 2)
        self.assertEqual(
            [segment.text for segment in result.segments],
            ["첫째", "둘째"],
        )

    def test_aligns_saved_actual_asr_output_without_calling_model(self) -> None:
        actual_output_path = Path(__file__).parent / "asr_test_data.json"
        if not actual_output_path.exists():
            self.skipTest("로컬 실제 ASR 출력 fixture가 없습니다.")
        asr_result = AsrResult.model_validate_json(
            actual_output_path.read_text(encoding="utf-8")
        )
        last_end_ms = max(segment.end_ms for segment in asr_result.segments)
        diarization_result = DiarizationResult(
            segments=[
                {"startMs": 0, "endMs": last_end_ms, "speaker": "SPEAKER_00"}
            ],
            exclusiveSegments=[
                {"startMs": 0, "endMs": last_end_ms, "speaker": "SPEAKER_00"}
            ],
        )

        result = align_asr_and_diarization(asr_result, diarization_result)

        self.assertGreater(len(result.segments), 0)
        self.assertEqual(result.text, asr_result.text)
        unassigned_words = [
            word
            for segment in result.segments
            if segment.speaker_label is None
            for word in segment.words
        ]
        self.assertGreater(len(unassigned_words), 0)
        self.assertTrue(
            all(word.start_ms == word.end_ms for word in unassigned_words)
        )
        self.assertTrue(
            all(
                segment.speaker_label == "SPEAKER_00"
                for segment in result.segments
                if segment.speaker_label is not None
            )
        )
        self.assertEqual(
            sum(len(segment.words) for segment in result.segments),
            sum(len(segment.words) for segment in asr_result.segments),
        )


if __name__ == "__main__":
    unittest.main()
