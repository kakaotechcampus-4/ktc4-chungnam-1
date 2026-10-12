from pathlib import Path
import wave


class AudioValidationError(ValueError):
    """입력 음성이 고정 WAV 계약을 따르지 않을 때 발생한다."""


def validate_wav(audio_path: Path) -> None:
    """WAV/PCM 16-bit/16kHz/mono 계약과 비어 있지 않은 음성을 확인한다."""

    try:
        with wave.open(str(audio_path), "rb") as audio:
            if audio.getcomptype() != "NONE":
                raise AudioValidationError("음성 코덱은 PCM이어야 합니다.")
            if audio.getsampwidth() != 2:
                raise AudioValidationError("음성 샘플은 16-bit여야 합니다.")
            if audio.getframerate() != 16_000:
                raise AudioValidationError("음성 샘플레이트는 16kHz여야 합니다.")
            if audio.getnchannels() != 1:
                raise AudioValidationError("음성 채널은 mono여야 합니다.")
            if audio.getnframes() <= 0:
                raise AudioValidationError(
                    "비어 있는 음성 파일은 처리할 수 없습니다."
                )
    except (EOFError, wave.Error) as error:
        raise AudioValidationError("유효한 WAV 파일이 아닙니다.") from error
