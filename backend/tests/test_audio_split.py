"""긴 녹음 조각 나누기(`app/services/audio_split.py`) 검증. 음성은 모두 합성 신호다.

길이는 표본 수(16kHz에서 1600표본 = 100ms)로 적는다. 무음은 찾는 범위의 100ms 격자에 맞춘다.
"""

import hashlib
import struct
import wave
from pathlib import Path

import pytest

from app.services.audio_split import (
    PART_SECONDS,
    SAMPLE_RATE,
    AudioPart,
    may_need_split,
    plan_parts,
    write_part,
)

FRAME = 1600  # 100ms
SECOND = SAMPLE_RATE


def loud(samples: int) -> bytes:
    assert samples % 2 == 0
    return struct.pack("<hh", 3000, -3000) * (samples // 2)


def silence(samples: int) -> bytes:
    return b"\x00\x00" * samples


def write_wav(path: Path, frames: bytes) -> Path:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)
    return path


def read_frames(path: Path) -> tuple[tuple, bytes]:
    with wave.open(str(path), "rb") as wav:
        params = (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes())
        return params, wav.readframes(wav.getnframes())


# 2초 조각, 조각 끝 직전 0.6초(6프레임) 안에서 찾는다.
SMALL = {"part_seconds": 2, "search_seconds": 0.6, "frame_milliseconds": 100,
         "min_last_seconds": 0.0}
# 첫 무음 1.6~1.7초, 둘째 무음 3.25~3.35초(첫 조각 끝 1.65초 + 1.6초), 전체 4.75초.
TWO_QUIET_POINTS = (
    loud(25_600) + silence(FRAME) + loud(24_800) + silence(FRAME) + loud(22_400)
)


def test_size_alone_decides_when_a_download_is_needed():
    pcm_30_minutes = PART_SECONDS * SAMPLE_RATE * 2
    assert pcm_30_minutes == 57_600_000
    # 44바이트 헤더와 30분 PCM이면 확실히 30분 이하라 내려받지 않는다.
    assert not may_need_split(pcm_30_minutes + 44)
    assert may_need_split(pcm_30_minutes + 45)
    assert not may_need_split(96_044, part_seconds=3)
    assert may_need_split(96_045, part_seconds=3)


def test_a_recording_within_the_part_length_is_one_part(tmp_path):
    path = write_wav(tmp_path / "short.wav", loud(2 * SECOND))

    assert plan_parts(path, **SMALL) == [AudioPart(0, 2 * SECOND)]


def test_cuts_land_on_the_quietest_frame_near_each_boundary(tmp_path):
    path = write_wav(tmp_path / "long.wav", TWO_QUIET_POINTS)

    parts = plan_parts(path, **SMALL)

    # 무음 프레임의 가운데(1.65초, 3.3초)에서 자른다.
    assert parts == [
        AudioPart(0, 26_400),
        AudioPart(26_400, 52_800),
        AudioPart(52_800, 76_000),
    ]
    assert all(part.end_frame - part.start_frame <= 2 * SECOND for part in parts)
    assert [part.start_ms for part in parts] == [0, 1650, 3300]


def test_without_a_quiet_point_the_cut_stays_at_or_before_the_part_length(tmp_path):
    # 모든 프레임의 에너지가 같으면 조각이 가장 긴 쪽(마지막 프레임의 가운데, 1.95초)을 고른다.
    path = write_wav(tmp_path / "flat.wav", loud(5 * SECOND))

    parts = plan_parts(path, **SMALL)

    assert parts[0] == AudioPart(0, 31_200)
    assert all(part.end_frame - part.start_frame <= 2 * SECOND for part in parts)
    assert parts[-1].end_frame == 5 * SECOND


def test_quiet_points_outside_the_search_window_are_ignored(tmp_path):
    # 0.5초 무음은 찾는 범위(1.4~2초) 밖이다.
    frames = loud(8_000) + silence(FRAME) + loud(38_400)
    path = write_wav(tmp_path / "early.wav", frames)

    first = plan_parts(path, **SMALL)[0]

    assert 22_400 <= first.end_frame <= 2 * SECOND


def test_a_short_tail_moves_the_last_cut_earlier(tmp_path):
    path = write_wav(tmp_path / "tail.wav", loud(35_200))

    parts = plan_parts(path, **{**SMALL, "min_last_seconds": 1.0})

    assert len(parts) == 2
    assert parts[-1].end_frame - parts[-1].start_frame >= 1 * SECOND
    assert parts[0].end_frame - parts[0].start_frame <= 2 * SECOND


def test_parts_are_valid_wavs_that_rebuild_the_original(tmp_path):
    source = write_wav(tmp_path / "long.wav", TWO_QUIET_POINTS)
    parts = plan_parts(source, **SMALL)

    rebuilt = b""
    for number, part in enumerate(parts):
        destination = tmp_path / f"part-{number}.wav"
        written = write_part(source, part, destination)
        params, data = read_frames(destination)
        # 새 헤더가 조각 길이를 정확히 선언한다.
        assert params == (1, 2, SAMPLE_RATE, part.end_frame - part.start_frame)
        content = destination.read_bytes()
        assert written.size_bytes == len(content) == 44 + len(data)
        assert written.sha256 == hashlib.sha256(content).hexdigest()
        rebuilt += data
    assert rebuilt == TWO_QUIET_POINTS


def test_rejects_audio_that_is_not_the_accepted_format(tmp_path):
    path = tmp_path / "stereo.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(b"\x00\x00\x00\x00" * SAMPLE_RATE)

    with pytest.raises(ValueError):
        plan_parts(path, **SMALL)


def test_default_parts_are_at_most_30_minutes_and_cut_in_the_last_40_seconds(tmp_path):
    # 실제 기본값(30분, 40초 범위, 100ms 프레임, 마지막 조각 60초 이상). 29분 45초에 무음
    # 0.1초를 둔 31분 합성 신호다. 찾는 범위는 29분 20초부터 30분까지다.
    quiet_at = (29 * 60 + 45) * SECOND
    total = 31 * 60 * SECOND
    frames = loud(quiet_at) + silence(FRAME) + loud(total - quiet_at - FRAME)
    path = write_wav(tmp_path / "default.wav", frames)

    parts = plan_parts(path)

    assert parts == [AudioPart(0, quiet_at + FRAME // 2), AudioPart(quiet_at + FRAME // 2, total)]
    assert parts[0].end_frame <= PART_SECONDS * SECOND
