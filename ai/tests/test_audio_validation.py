from pathlib import Path
import tempfile
import unittest

from ai.audio.validation import AudioValidationError, validate_wav
from tests.support import write_synthetic_wav


class ValidateWavTest(unittest.TestCase):
    def test_accepts_pcm_16bit_16khz_mono(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audio_path = Path(directory) / "sample.wav"
            write_synthetic_wav(audio_path)

            validate_wav(audio_path)

    def test_rejects_stereo_audio(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audio_path = Path(directory) / "sample.wav"
            write_synthetic_wav(audio_path, channel_count=2)

            with self.assertRaises(AudioValidationError):
                validate_wav(audio_path)


if __name__ == "__main__":
    unittest.main()
