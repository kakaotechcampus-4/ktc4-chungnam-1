"""긴 면회 녹음을 STT에 보낼 30분 이하 조각으로 나눈다.

2026-11-10 PM 결정: 긴 녹음은 30분 단위로 전사한다. 한 번의 STT 호출은 제한 시간
(`SAEROK_AI_SERVER_TIMEOUT_SECONDS`, 기본 600초)을 넘길 수 없는데, 예비 STT 서버에서 88분
녹음은 1,016초, 71분 녹음은 690초가 걸렸다(11/10 E2E). 보호자가 공유하는 녹음은 기기에 남은
전체 WAV이고 이 조각과 관계없다.

- 입력은 접수할 때 검사한 WAV/PCM 16-bit/16kHz/mono다. 길이는 헤더의 프레임 수로 읽는다.
- 조각 끝은 그 조각 시작부터 30분이 되는 지점 직전 40초(29분 40초 ± 20초) 안에서 100ms
  프레임의 에너지(표본 제곱의 합, RMS와 순서가 같다)가 가장 작은 프레임의 가운데로 정한다.
  그래서 어느 조각도 30분을 넘지 않고, 말하는 도중보다 쉬는 곳에서 자를 가능성이 높다.
- 마지막 조각이 60초보다 짧아지면 그 앞 끝을 앞당긴다. STT 서버가 아주 짧은 음성으로 따로
  화자 분리를 하게 두지 않는다. 지금까지 단일 호출로 처리한 가장 짧은 면회 녹음이 15~30초였다.
- 조각마다 새 헤더를 쓴 정상 WAV 파일을 만든다. 표준 라이브러리만 쓴다(backend에 numpy 없음).

음성 내용, 파일 경로와 객체 키는 로그와 예외 메시지에 넣지 않는다.
"""

from __future__ import annotations

import hashlib
import sys
import wave
from array import array
from dataclasses import dataclass
from operator import mul
from pathlib import Path

SAMPLE_RATE = 16_000
SAMPLE_WIDTH = 2
# 조각 하나의 최대 길이(초). PCM 16-bit mono 16kHz에서 57,600,000바이트다.
PART_SECONDS = 30 * 60
# 조각 끝을 찾는 범위(초). 조각 시작부터 PART_SECONDS가 되는 지점 직전이다.
QUIET_SEARCH_SECONDS = 40
FRAME_MILLISECONDS = 100
# 마지막 조각의 최소 길이(초).
MIN_LAST_PART_SECONDS = 60
# RIFF, fmt, data 청크 머리를 합친 가장 작은 WAV 헤더.
MIN_WAV_HEADER_BYTES = 44
_COPY_FRAMES = 1024 * 1024


@dataclass(frozen=True)
class AudioPart:
    """원본 안에서 조각의 위치(프레임, 끝은 제외)."""

    start_frame: int
    end_frame: int

    @property
    def start_ms(self) -> int:
        return self.start_frame * 1000 // SAMPLE_RATE

    @property
    def seconds(self) -> float:
        return (self.end_frame - self.start_frame) / SAMPLE_RATE


@dataclass(frozen=True)
class PartFile:
    size_bytes: int
    sha256: str


def may_need_split(size_bytes: int, *, part_seconds: int = PART_SECONDS) -> bool:
    """파일 크기만으로 조각이 필요할 수 있는지. `False`면 내려받지 않고 한 번에 보낸다.

    음성 데이터는 파일 크기에서 최소 헤더를 뺀 것보다 클 수 없다. 그 크기가 조각 하나의
    PCM 바이트 이하이면 녹음은 조각 길이 이하다. 넘으면 헤더를 읽어야 실제 길이를 안다
    (data 뒤에 메타데이터 청크가 붙을 수 있다).
    """
    return size_bytes - MIN_WAV_HEADER_BYTES > part_seconds * SAMPLE_RATE * SAMPLE_WIDTH


def plan_parts(
    path: Path,
    *,
    part_seconds: int = PART_SECONDS,
    search_seconds: float = QUIET_SEARCH_SECONDS,
    frame_milliseconds: int = FRAME_MILLISECONDS,
    min_last_seconds: float = MIN_LAST_PART_SECONDS,
) -> list[AudioPart]:
    """WAV를 읽어 조각 위치를 정한다. 조각 길이 이하이면 조각 하나(원본 전체)다."""
    if part_seconds < 1:
        raise ValueError("조각 길이는 1초 이상이어야 합니다.")
    part_frames = part_seconds * SAMPLE_RATE
    search_frames = max(1, int(search_seconds * SAMPLE_RATE))
    frame = max(1, SAMPLE_RATE * frame_milliseconds // 1000)
    min_last_frames = int(min_last_seconds * SAMPLE_RATE)
    with wave.open(str(path), "rb") as wav:
        total = _checked_frames(wav)
        parts: list[AudioPart] = []
        start = 0
        while total - start > part_frames:
            limit = start + part_frames
            if total - min_last_frames > start:
                limit = min(limit, total - min_last_frames)
            window_start = max(start, limit - search_frames)
            cut = limit
            if limit - window_start >= frame:
                cut = _quietest_frame_center(wav, window_start, limit, frame)
            if cut <= start:
                cut = limit
            parts.append(AudioPart(start, cut))
            start = cut
        parts.append(AudioPart(start, total))
    return parts


def write_part(source: Path, part: AudioPart, destination: Path) -> PartFile:
    """조각을 새 헤더를 쓴 WAV로 저장하고 크기와 SHA-256을 돌려준다."""
    with wave.open(str(source), "rb") as wav:
        _checked_frames(wav)
        wav.setpos(part.start_frame)
        with wave.open(str(destination), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(SAMPLE_WIDTH)
            out.setframerate(SAMPLE_RATE)
            out.setnframes(part.end_frame - part.start_frame)
            remaining = part.end_frame - part.start_frame
            while remaining > 0:
                data = wav.readframes(min(remaining, _COPY_FRAMES))
                if not data:
                    raise ValueError("음성 데이터가 헤더에 선언된 길이보다 짧습니다.")
                out.writeframesraw(data)
                remaining -= len(data) // SAMPLE_WIDTH
    digest = hashlib.sha256()
    size = 0
    with destination.open("rb") as file:
        while chunk := file.read(_COPY_FRAMES):
            size += len(chunk)
            digest.update(chunk)
    return PartFile(size_bytes=size, sha256=digest.hexdigest())


def _checked_frames(wav: wave.Wave_read) -> int:
    if (
        wav.getcomptype() != "NONE"
        or wav.getsampwidth() != SAMPLE_WIDTH
        or wav.getframerate() != SAMPLE_RATE
        or wav.getnchannels() != 1
        or wav.getnframes() <= 0
    ):
        raise ValueError("음성은 WAV/PCM 16-bit/16kHz/mono 형식이어야 합니다.")
    return wav.getnframes()


def _quietest_frame_center(wav: wave.Wave_read, start: int, end: int, frame: int) -> int:
    """[start, end)를 frame 단위로 나눠 에너지가 가장 작은 프레임의 가운데 위치.

    에너지가 같으면 뒤쪽(조각이 더 긴 쪽)을 고른다. 범위 끝에 남는 frame보다 짧은 꼬리는 보지
    않으므로 고른 위치는 늘 `end`보다 앞이다.
    """
    wav.setpos(start)
    samples = array("h")
    samples.frombytes(wav.readframes(end - start))
    if sys.byteorder == "big":
        samples.byteswap()
    best_offset = 0
    best_energy: int | None = None
    for offset in range(0, len(samples) - frame + 1, frame):
        chunk = samples[offset:offset + frame]
        energy = sum(map(mul, chunk, chunk))
        if best_energy is None or energy <= best_energy:
            best_energy = energy
            best_offset = offset
    return start + best_offset + frame // 2
