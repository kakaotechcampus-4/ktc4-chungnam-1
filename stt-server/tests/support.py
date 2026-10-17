from io import BytesIO
from pathlib import Path
import wave


def make_synthetic_wav_bytes(
    *,
    channel_count: int = 1,
    sample_width: int = 2,
    sample_rate_hz: int = 16_000,
) -> bytes:
    """개인정보가 없는 짧은 무음 WAV를 만든다."""

    output = BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setnchannels(channel_count)
        audio.setsampwidth(sample_width)
        audio.setframerate(sample_rate_hz)
        audio.writeframes(b"\x00" * sample_width * channel_count * 160)
    return output.getvalue()


def write_synthetic_wav(path: Path, **kwargs) -> None:
    path.write_bytes(make_synthetic_wav_bytes(**kwargs))
