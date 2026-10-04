from __future__ import annotations

from array import array
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import wave


SCRIPT_PATH = (
    Path(__file__).resolve().parents[1]
    / "docs"
    / "stt-mobile-benchmark"
    / "build_two_speaker_audio.py"
)
SPEC = importlib.util.spec_from_file_location("build_two_speaker_audio", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def write_wav(path: Path, samples: list[int], sample_rate: int = 8_000) -> None:
    values = array("h", samples)
    if sys.byteorder != "little":
        values.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(values.tobytes())


def read_wav(path: Path) -> tuple[wave._wave_params, list[int]]:
    with wave.open(str(path), "rb") as source:
        params = source.getparams()
        values = array("h")
        values.frombytes(source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        values.byteswap()
    return params, list(values)


class MixWavFilesTest(unittest.TestCase):
    def test_mixes_timeline_and_reduces_gain_only_to_prevent_clipping(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            speaker_a = root / "speaker-a.wav"
            speaker_b = root / "speaker-b.wav"
            output = root / "mixed.wav"
            write_wav(speaker_a, [10_000, 0, 30_000, -30_000])
            write_wav(speaker_b, [0, 20_000, 30_000, -30_000])

            result = MODULE.mix_wav_files(speaker_a, speaker_b, output)
            params, samples = read_wav(output)

            self.assertEqual(params.nchannels, 1)
            self.assertEqual(params.sampwidth, 2)
            self.assertEqual(params.framerate, 8_000)
            self.assertEqual(params.nframes, 4)
            self.assertAlmostEqual(result.gain, round(32_767 * 0.98) / 60_000)
            self.assertEqual(samples, [5_352, 10_704, 32_112, -32_112])

    def test_pads_the_shorter_track_with_silence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            speaker_a = root / "speaker-a.wav"
            speaker_b = root / "speaker-b.wav"
            output = root / "mixed.wav"
            write_wav(speaker_a, [100, 200, 300])
            write_wav(speaker_b, [10])

            MODULE.mix_wav_files(speaker_a, speaker_b, output)
            _, samples = read_wav(output)

            self.assertEqual(samples, [110, 200, 300])

    def test_refuses_to_overwrite_an_existing_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            speaker_a = root / "speaker-a.wav"
            speaker_b = root / "speaker-b.wav"
            output = root / "mixed.wav"
            write_wav(speaker_a, [100])
            write_wav(speaker_b, [200])
            write_wav(output, [999])

            with self.assertRaises(FileExistsError):
                MODULE.mix_wav_files(speaker_a, speaker_b, output)


class MergeReferenceFilesTest(unittest.TestCase):
    def test_merges_by_timestamp_and_clips_to_audio_duration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            reference_a = root / "speaker-a.txt"
            reference_b = root / "speaker-b.txt"
            output = root / "mixed.txt"
            reference_a.write_text(
                "[1.000,2.500]\tG0001\tfemale\t첫 번째 발화\n"
                "[5.000,7.000]\tG0001\tfemale\t잘리는 발화\n",
                encoding="utf-8",
            )
            reference_b.write_text(
                "[0.500,1.500]\tG0002\tmale\t먼저 시작한 발화\n"
                "[6.500,8.000]\tG0002\tmale\t제외할 발화\n",
                encoding="utf-8",
            )

            count = MODULE.merge_reference_files(
                reference_a,
                reference_b,
                output,
                duration_seconds=6.0,
            )

            self.assertEqual(count, 3)
            self.assertEqual(
                output.read_text(encoding="utf-8").splitlines(),
                [
                    "[0.500,1.500]\tG0002\tmale\t먼저 시작한 발화",
                    "[1.000,2.500]\tG0001\tfemale\t첫 번째 발화",
                    "[5.000,6.000]\tG0001\tfemale\t잘리는 발화",
                ],
            )

    def test_infers_kcsc_reference_path(self) -> None:
        audio = Path("/dataset/kcsc/WAV/A0051_S0001_0_G0101.wav")

        self.assertEqual(
            MODULE.infer_reference_path(audio),
            Path("/dataset/kcsc/TXT/A0051_S0001_0_G0101.txt"),
        )


if __name__ == "__main__":
    unittest.main()
