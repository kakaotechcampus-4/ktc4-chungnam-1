"""
새록 QA 이슈 #8 - 음성 테스트 케이스 자동 생성 스크립트

사용법:
    1. Zeroth-Korean(CC BY 4.0) 등에서 다운로드한 .wav 클립들을 아래 SOURCE_DIR에 넣는다.
       (최소 2개 이상의 서로 다른 화자 클립을 권장)
    2. python generate_test_cases.py 실행
    3. OUTPUT_DIR 아래에 케이스별 폴더가 생성된다.

이 스크립트는 "배경 소음", "제3자 음성 포함", "작은 음성/불명확 발화",
"중첩 발화", "발화 너무 짧음" 5개 케이스를 원본 클립으로부터 합성한다.
("조용한 2인 대화" 기준 케이스는 팀원 직접 녹음을 권장하므로 이 스크립트 대상에서 제외)

출처 표기 필요: 최종 evals/README.md에 "Zeroth-Korean (CC BY 4.0, https://openslr.org/40/)
클립을 가공하여 생성함"과 같이 명시할 것.
"""

import os
import random
from pydub import AudioSegment
from pydub.generators import WhiteNoise

SOURCE_DIR = "./source_clips"      # 원본 wav 클립 폴더 (팀에서 채워 넣을 위치)
OUTPUT_DIR = "./generated_cases"   # 생성된 케이스가 저장될 폴더

random.seed(42)


def load_clips(source_dir):
    clips = []
    if not os.path.isdir(source_dir):
        return clips
    for fname in sorted(os.listdir(source_dir)):
        if fname.lower().endswith(".wav"):
            path = os.path.join(source_dir, fname)
            clips.append((fname, AudioSegment.from_wav(path)))
    return clips


def case_background_noise(clip, noise_db_reduction=18):
    """배경 소음 섞기: 화이트노이즈를 원본보다 조용하게 깔아 겹친다."""
    noise = WhiteNoise().to_audio_segment(duration=len(clip))
    noise = noise - noise_db_reduction  # 원본보다 훨씬 작은 볼륨으로
    return clip.overlay(noise)


def case_third_party_voice(clip_a, clip_b, insert_at_ratio=0.5, snippet_ms=3000):
    """제3자 음성 포함: 다른 화자의 짧은 발화를 중간에 겹쳐 삽입한다."""
    insert_point = int(len(clip_a) * insert_at_ratio)
    snippet = clip_b[:snippet_ms] - 6  # 살짝 작게
    return clip_a.overlay(snippet, position=insert_point)


def case_unclear_speech(clip, lowpass_hz=1200, volume_db=-15):
    """작은 음성/불명확한 발화: 저역통과 필터 + 볼륨 감소로 먹먹하고 작은 발화 흉내."""
    filtered = clip.low_pass_filter(lowpass_hz)
    return filtered + volume_db


def case_overlapping_speech(clip_a, clip_b, overlap_ms=4000):
    """중첩 발화: 두 화자의 발화 구간을 겹쳐서 이어붙인다."""
    a_head = clip_a[: max(len(clip_a) - overlap_ms, 0)]
    a_tail = clip_a[max(len(clip_a) - overlap_ms, 0):]
    b_head = clip_b[:overlap_ms]
    b_rest = clip_b[overlap_ms:]
    overlapped = a_tail.overlay(b_head)
    return a_head + overlapped + b_rest


def case_too_short(clip, snippet_ms=400):
    """발화가 너무 짧음: 극단적으로 짧게 잘라 한두 음절만 남긴다."""
    mid = len(clip) // 2
    return clip[mid: mid + snippet_ms]


def main():
    clips = load_clips(SOURCE_DIR)
    if len(clips) < 2:
        print(f"[안내] '{SOURCE_DIR}' 폴더에 wav 클립을 최소 2개 이상 넣고 다시 실행하세요.")
        print("      (Zeroth-Korean 등 CC BY 4.0 클립 다운로드 후 이 폴더에 배치)")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    (name_a, clip_a), (name_b, clip_b) = clips[0], clips[1]

    outputs = {
        "01_background_noise.wav": case_background_noise(clip_a),
        "02_third_party_voice.wav": case_third_party_voice(clip_a, clip_b),
        "03_unclear_speech.wav": case_unclear_speech(clip_a),
        "04_overlapping_speech.wav": case_overlapping_speech(clip_a, clip_b),
        "05_too_short.wav": case_too_short(clip_a),
    }

    for fname, segment in outputs.items():
        out_path = os.path.join(OUTPUT_DIR, fname)
        segment.export(out_path, format="wav")
        print(f"생성됨: {out_path}  (원본: {name_a}" + (f", {name_b}" if "third_party" in fname or "overlap" in fname else "") + ")")

    print("\n완료. evals/README.md에 각 파일의 원본 클립명과 생성 방식을 기록하세요.")


if __name__ == "__main__":
    main()
