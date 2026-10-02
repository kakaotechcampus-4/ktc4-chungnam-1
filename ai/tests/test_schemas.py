from datetime import datetime, timedelta, timezone
import unittest

from pydantic import ValidationError

from ai.api.schemas import LocalSpeechAnalysisRequest, SpeechAnalysisRequest


class SpeechAnalysisRequestTest(unittest.TestCase):
    def test_parses_an_s3_request(self) -> None:
        now = datetime.now(timezone.utc)
        payload = SpeechAnalysisRequest.model_validate(
            {
                "schemaVersion": 1,
                "analysisId": "analysis_test_001",
                "language": "ko",
                "speakerCount": 2,
                "audioSource": {
                    "type": "s3PresignedGet",
                    "downloadUrl": "https://bucket.s3.amazonaws.com/audio.wav?sig=test",
                    "downloadUrlExpiresAt": (now + timedelta(minutes=5)).isoformat(),
                    "sizeBytes": 1024,
                    "sha256": "a" * 64,
                },
                "dataExpiresAt": (now + timedelta(hours=1)).isoformat(),
            }
        )

        self.assertEqual(payload.audio_source.type, "s3PresignedGet")
        self.assertEqual(payload.speaker_count, 2)

    def test_converts_the_legacy_local_request(self) -> None:
        legacy = LocalSpeechAnalysisRequest(
            analysisId="analysis_local_001",
            speakerCount=1,
            audioFileName="sample.wav",
        )

        payload = legacy.to_speech_analysis_request()

        self.assertEqual(payload.schema_version, 1)
        self.assertEqual(payload.audio_source.type, "localFile")
        self.assertEqual(payload.audio_source.audio_file_name, "sample.wav")

    def test_rejects_removed_authorization_and_format_fields(self) -> None:
        now = datetime.now(timezone.utc)

        with self.assertRaises(ValidationError):
            SpeechAnalysisRequest.model_validate(
                {
                    "schemaVersion": 1,
                    "analysisId": "analysis_test_001",
                    "language": "ko",
                    "speakerCount": 2,
                    "audioSource": {
                        "type": "s3PresignedGet",
                        "downloadUrl": "https://bucket.s3.amazonaws.com/audio.wav",
                        "downloadUrlExpiresAt": (
                            now + timedelta(minutes=5)
                        ).isoformat(),
                        "sizeBytes": 1024,
                        "sha256": "a" * 64,
                        "format": {"container": "wav"},
                    },
                    "processingAuthorization": {"authorized": True},
                    "dataExpiresAt": (now + timedelta(hours=1)).isoformat(),
                }
            )


if __name__ == "__main__":
    unittest.main()
