"""Build a two-speaker WAV and its merged KCSC reference TXT file."""

from __future__ import annotations

import argparse
from array import array
from contextlib import ExitStack
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys
import tempfile
import wave


BENCHMARK_ROOT = Path(__file__).resolve().parent
WAV_ROOT = BENCHMARK_ROOT / "data" / "kcsc" / "WAV"
DEFAULT_SPEAKER_A = WAV_ROOT / "A0051_S0001_0_G0101.wav"
DEFAULT_SPEAKER_B = WAV_ROOT / "A0051_S0001_0_G0102.wav"
DEFAULT_OUTPUT = WAV_ROOT / "generated" / "A0051_S0001_0_G0101_G0102.wav"
CHUNK_FRAMES = 65_536
INT16_MAX = 32_767
REFERENCE_LINE = re.compile(
    r"^\[(?P<start>\d+(?:\.\d+)?),(?P<end>\d+(?:\.\d+)?)\]\s*"
    r"(?P<speaker>\S+)\s+(?P<gender>\S+)\s+(?P<text>.*)$"
)


@dataclass(frozen=True)
class MixResult:
    output: Path
    frames: int
    sample_rate: int
    gain: float

    @property
    def duration_seconds(self) -> float:
        return self.frames / self.sample_rate


@dataclass(frozen=True)
class ReferenceSegment:
    start: float
    end: float
    speaker: str
    gender: str
    text: str

    def format(self) -> str:
        return (
            f"[{self.start:.3f},{self.end:.3f}]\t{self.speaker}\t"
            f"{self.gender}\t{self.text}"
        )


def _read_text(path: Path) -> str:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "cp949"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _read_reference(path: Path) -> list[ReferenceSegment]:
    segments: list[ReferenceSegment] = []
    for line_number, line in enumerate(_read_text(path).splitlines(), start=1):
        if not line.strip():
            continue
        match = REFERENCE_LINE.match(line.strip())
        if match is None:
            raise ValueError(f"정답 TXT 형식을 읽을 수 없습니다: {path}:{line_number}")
        values = match.groupdict()
        segments.append(
            ReferenceSegment(
                start=float(values["start"]),
                end=float(values["end"]),
                speaker=values["speaker"],
                gender=values["gender"],
                text=values["text"],
            )
        )
    return segments


def infer_reference_path(audio_path: Path) -> Path:
    """Infer a KCSC TXT path from a WAV path."""

    if audio_path.parent.name == "WAV":
        return audio_path.parent.parent / "TXT" / f"{audio_path.stem}.txt"
    return audio_path.with_suffix(".txt")


def merge_reference_files(
    reference_a_path: Path,
    reference_b_path: Path,
    output_path: Path,
    *,
    duration_seconds: float | None = None,
    overwrite: bool = False,
) -> int:
    """Merge two KCSC references in timestamp order and return line count."""

    output_path = output_path.resolve()
    if output_path.exists() and not overwrite:
        raise FileExistsError(
            f"정답 파일이 이미 있습니다: {output_path} (--force로 덮어쓸 수 있습니다.)"
        )
    if duration_seconds is not None and duration_seconds <= 0:
        raise ValueError("--duration-seconds는 0보다 커야 합니다.")

    segments = _read_reference(reference_a_path) + _read_reference(reference_b_path)
    if duration_seconds is not None:
        segments = [
            ReferenceSegment(
                start=segment.start,
                end=min(segment.end, duration_seconds),
                speaker=segment.speaker,
                gender=segment.gender,
                text=segment.text,
            )
            for segment in segments
            if segment.start < duration_seconds
        ]
    segments.sort(key=lambda segment: (segment.start, segment.end, segment.speaker))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(f"{segment.format()}\n" for segment in segments)
    temporary_file = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="\n",
        prefix=f".{output_path.stem}-",
        suffix=".txt.tmp",
        dir=output_path.parent,
        delete=False,
    )
    temporary_path = Path(temporary_file.name)
    try:
        with temporary_file:
            temporary_file.write(content)
        os.replace(temporary_path, output_path)
    finally:
        temporary_path.unlink(missing_ok=True)
    return len(segments)


def _read_int16_samples(source: wave.Wave_read, frame_count: int) -> array[int]:
    samples = array("h")
    samples.frombytes(source.readframes(frame_count))
    if sys.byteorder != "little":
        samples.byteswap()
    if len(samples) < frame_count:
        samples.extend([0] * (frame_count - len(samples)))
    return samples


def _validate_sources(
    speaker_a: wave.Wave_read,
    speaker_b: wave.Wave_read,
) -> tuple[int, int]:
    for label, source in (("speaker A", speaker_a), ("speaker B", speaker_b)):
        if source.getcomptype() != "NONE":
            raise ValueError(f"{label} 파일은 PCM WAV여야 합니다.")
        if source.getnchannels() != 1:
            raise ValueError(f"{label} 파일은 mono WAV여야 합니다.")
        if source.getsampwidth() != 2:
            raise ValueError(f"{label} 파일은 16-bit WAV여야 합니다.")

    if speaker_a.getframerate() != speaker_b.getframerate():
        raise ValueError("두 입력 파일의 sample rate가 다릅니다.")

    return speaker_a.getframerate(), max(
        speaker_a.getnframes(), speaker_b.getnframes()
    )


def _find_peak(
    speaker_a: wave.Wave_read,
    speaker_b: wave.Wave_read,
    total_frames: int,
) -> int:
    peak = 0
    frames_remaining = total_frames
    while frames_remaining:
        frame_count = min(CHUNK_FRAMES, frames_remaining)
        samples_a = _read_int16_samples(speaker_a, frame_count)
        samples_b = _read_int16_samples(speaker_b, frame_count)
        peak = max(
            peak,
            max((abs(a + b) for a, b in zip(samples_a, samples_b)), default=0),
        )
        frames_remaining -= frame_count
    return peak


def _write_mix(
    output: wave.Wave_write,
    speaker_a: wave.Wave_read,
    speaker_b: wave.Wave_read,
    total_frames: int,
    gain: float,
) -> None:
    frames_remaining = total_frames
    while frames_remaining:
        frame_count = min(CHUNK_FRAMES, frames_remaining)
        samples_a = _read_int16_samples(speaker_a, frame_count)
        samples_b = _read_int16_samples(speaker_b, frame_count)
        mixed = array(
            "h",
            (
                max(-INT16_MAX - 1, min(INT16_MAX, round((a + b) * gain)))
                for a, b in zip(samples_a, samples_b)
            ),
        )
        if sys.byteorder != "little":
            mixed.byteswap()
        output.writeframesraw(mixed.tobytes())
        frames_remaining -= frame_count


def mix_wav_files(
    speaker_a_path: Path,
    speaker_b_path: Path,
    output_path: Path,
    *,
    duration_seconds: float | None = None,
    headroom: float = 0.98,
    overwrite: bool = False,
) -> MixResult:
    """Mix synchronized, speaker-isolated WAV tracks without changing timing."""

    speaker_a_path = speaker_a_path.resolve()
    speaker_b_path = speaker_b_path.resolve()
    output_path = output_path.resolve()

    if speaker_a_path == speaker_b_path:
        raise ValueError("서로 다른 두 화자 WAV 파일을 지정해야 합니다.")
    if output_path in (speaker_a_path, speaker_b_path):
        raise ValueError("출력 경로는 입력 경로와 달라야 합니다.")
    if output_path.exists() and not overwrite:
        raise FileExistsError(
            f"출력 파일이 이미 있습니다: {output_path} (--force로 덮어쓸 수 있습니다.)"
        )
    if duration_seconds is not None and duration_seconds <= 0:
        raise ValueError("--duration-seconds는 0보다 커야 합니다.")
    if not 0 < headroom <= 1:
        raise ValueError("headroom은 0보다 크고 1 이하여야 합니다.")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None

    try:
        with ExitStack() as stack:
            speaker_a = stack.enter_context(wave.open(str(speaker_a_path), "rb"))
            speaker_b = stack.enter_context(wave.open(str(speaker_b_path), "rb"))
            sample_rate, total_frames = _validate_sources(speaker_a, speaker_b)
            if duration_seconds is not None:
                total_frames = min(
                    total_frames, round(duration_seconds * sample_rate)
                )

            peak = _find_peak(speaker_a, speaker_b, total_frames)
            target_peak = round(INT16_MAX * headroom)
            gain = min(1.0, target_peak / peak) if peak else 1.0

            speaker_a.rewind()
            speaker_b.rewind()
            temporary_file = tempfile.NamedTemporaryFile(
                prefix=f".{output_path.stem}-",
                suffix=".wav.tmp",
                dir=output_path.parent,
                delete=False,
            )
            temporary_path = Path(temporary_file.name)
            temporary_file.close()

            with wave.open(str(temporary_path), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(sample_rate)
                _write_mix(output, speaker_a, speaker_b, total_frames, gain)

        os.replace(temporary_path, output_path)
        temporary_path = None
        return MixResult(output_path, total_frames, sample_rate, gain)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "동일 KCSC 대화 세션의 화자별 WAV 두 개를 타임라인 그대로 합쳐 "
            "diarization 테스트용 mono WAV와 정답 TXT를 만듭니다."
        )
    )
    parser.add_argument("--speaker-a", type=Path, default=DEFAULT_SPEAKER_A)
    parser.add_argument("--speaker-b", type=Path, default=DEFAULT_SPEAKER_B)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--reference-a",
        type=Path,
        help="화자 A 정답 TXT. 생략하면 speaker-a 경로에서 추론합니다.",
    )
    parser.add_argument(
        "--reference-b",
        type=Path,
        help="화자 B 정답 TXT. 생략하면 speaker-b 경로에서 추론합니다.",
    )
    parser.add_argument(
        "--reference-output",
        type=Path,
        help="합친 정답 경로. 생략하면 output의 확장자를 .txt로 바꿉니다.",
    )
    parser.add_argument(
        "--duration-seconds",
        type=float,
        help="앞부분만 생성할 길이(초). 생략하면 긴 쪽 입력의 전체 길이를 사용합니다.",
    )
    parser.add_argument(
        "--force", action="store_true", help="기존 출력 파일을 덮어씁니다."
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reference_a = args.reference_a or infer_reference_path(args.speaker_a)
    reference_b = args.reference_b or infer_reference_path(args.speaker_b)
    reference_output = args.reference_output or args.output.with_suffix(".txt")
    try:
        if reference_output.resolve().exists() and not args.force:
            raise FileExistsError(
                f"정답 파일이 이미 있습니다: {reference_output.resolve()} "
                "(--force로 덮어쓸 수 있습니다.)"
            )
        # Parse references before producing audio so malformed or missing TXT input
        # cannot leave a newly generated WAV without its matching ground truth.
        _read_reference(reference_a)
        _read_reference(reference_b)
        result = mix_wav_files(
            args.speaker_a,
            args.speaker_b,
            args.output,
            duration_seconds=args.duration_seconds,
            overwrite=args.force,
        )
        reference_count = merge_reference_files(
            reference_a,
            reference_b,
            reference_output,
            duration_seconds=result.duration_seconds,
            overwrite=args.force,
        )
    except (OSError, ValueError, wave.Error) as exc:
        raise SystemExit(f"생성 실패: {exc}") from exc

    print(f"음성 생성 완료: {result.output}")
    print(f"정답 생성 완료: {reference_output.resolve()} ({reference_count}개 구간)")
    print(
        f"형식: mono, 16-bit PCM, {result.sample_rate} Hz, "
        f"{result.duration_seconds:.3f}초"
    )
    print(f"clipping 방지 gain: {result.gain:.6f}")


if __name__ == "__main__":
    main()
