from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
import tempfile
import unittest

import httpx

from ai.api.schemas import LocalAudioSource, S3AudioSource
from ai.audio.providers import AudioSourceError, LocalAudioProvider, S3AudioProvider
from tests.support import make_synthetic_wav_bytes, write_synthetic_wav


class LocalAudioProviderTest(unittest.TestCase):
    def test_returns_a_file_inside_the_configured_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            audio_path = root / "sample.wav"
            write_synthetic_wav(audio_path)
            provider = LocalAudioProvider(root, enabled=True)
            source = LocalAudioSource(type="localFile", audioFileName="sample.wav")

            with provider.materialize(source) as materialized:
                self.assertEqual(materialized, audio_path)

    def test_rejects_a_path_outside_the_configured_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "audio"
            root.mkdir()
            outside = Path(directory) / "outside.wav"
            write_synthetic_wav(outside)
            provider = LocalAudioProvider(root, enabled=True)
            source = LocalAudioSource(
                type="localFile",
                audioFileName="../outside.wav",
            )

            with self.assertRaises(AudioSourceError):
                with provider.materialize(source):
                    pass

    def test_rejects_local_audio_when_disabled(self) -> None:
        provider = LocalAudioProvider(Path("."), enabled=False)
        source = LocalAudioSource(type="localFile", audioFileName="sample.wav")

        with self.assertRaises(AudioSourceError):
            with provider.materialize(source):
                pass


class S3AudioProviderTest(unittest.TestCase):
    def test_streams_and_verifies_the_download_then_removes_the_temp_file(self) -> None:
        content = make_synthetic_wav_bytes()
        source = S3AudioSource(
            type="s3PresignedGet",
            downloadUrl=(
                "https://bucket.s3.ap-northeast-2.amazonaws.com/audio.wav"
                "?X-Amz-Signature=synthetic"
            ),
            downloadUrlExpiresAt=datetime.now(timezone.utc) + timedelta(minutes=5),
            sizeBytes=len(content),
            sha256=hashlib.sha256(content).hexdigest(),
        )

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, content=content, request=request)

        client = httpx.Client(transport=httpx.MockTransport(handler))
        provider = S3AudioProvider(client=client)

        with provider.materialize(source) as audio_path:
            materialized = audio_path
            self.assertEqual(audio_path.read_bytes(), content)

        self.assertFalse(materialized.exists())
        client.close()

    def test_rejects_a_hash_mismatch(self) -> None:
        content = make_synthetic_wav_bytes()
        source = S3AudioSource(
            type="s3PresignedGet",
            downloadUrl="https://bucket.s3.amazonaws.com/audio.wav?signature=test",
            downloadUrlExpiresAt=datetime.now(timezone.utc) + timedelta(minutes=5),
            sizeBytes=len(content),
            sha256="0" * 64,
        )

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, content=content, request=request)

        client = httpx.Client(transport=httpx.MockTransport(handler))
        provider = S3AudioProvider(client=client)

        with self.assertRaises(AudioSourceError):
            with provider.materialize(source):
                pass
        client.close()


if __name__ == "__main__":
    unittest.main()
