"""
기준(baseline) 케이스 00_baseline_quiet.wav 생성 스크립트.

source_clips/ 에 있는 wav 클립 중 파일명 정렬 기준 처음 2개를 이어붙여
"조용한 2인 대화" 기준 케이스를 만든다. (generate_test_cases.py의 load_clips와
동일한 기준 — 특정 화자 ID를 가정하지 않음. download_samples.py는 스트리밍으로
화자를 만나는 순서가 실행마다 달라질 수 있어, 파일명을 하드코딩하면 새 환경에서
재현이 깨진다.)

download_samples.py 실행 후, 같은 폴더(evals/fixtures/speech/)에서 실행한다:
    python make_baseline.py

결과 파일은 evals/fixtures/speech/ 바로 아래(00_baseline_quiet.wav)에 생기며,
케이스의 inputRef가 가리키는 위치와 동일하다. 별도로 파일을 옮길 필요는 없다.
"""

import os
from pydub import AudioSegment

SOURCE_DIR = "./source_clips"
OUTPUT_DIR = "."


def main():
    if not os.path.isdir(SOURCE_DIR):
        print(f"[안내] '{SOURCE_DIR}' 폴더가 없습니다. download_samples.py를 먼저 실행하세요.")
        return

    wavs = sorted(f for f in os.listdir(SOURCE_DIR) if f.lower().endswith(".wav"))
    if len(wavs) < 2:
        print(f"[안내] '{SOURCE_DIR}'에 서로 다른 화자의 wav 클립이 2개 이상 필요합니다 (현재 {len(wavs)}개).")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    a = AudioSegment.from_wav(os.path.join(SOURCE_DIR, wavs[0]))
    b = AudioSegment.from_wav(os.path.join(SOURCE_DIR, wavs[1]))
    out_path = os.path.join(OUTPUT_DIR, "00_baseline_quiet.wav")
    (a + b).export(out_path, format="wav")
    print(f"완료: {out_path}  (원본: {wavs[0]}, {wavs[1]})")


if __name__ == "__main__":
    main()
