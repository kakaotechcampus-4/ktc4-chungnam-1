"""
"입력 파일 자체가 무효한" 케이스(stt-007, stt-008)용 고정 파일 생성 스크립트.

원본 음성이나 외부 데이터셋에 의존하지 않고, 결정적으로(항상 같은 결과로) 무효한
파일 2개를 만든다. 인터넷 연결이나 ffmpeg가 필요 없다.

같은 폴더(evals/fixtures/speech/)에서 실행한다:
    python make_invalid_files.py
"""

import os
import random

OUTPUT_DIR = "."


def main():
    empty_path = os.path.join(OUTPUT_DIR, "06_empty_file.wav")
    with open(empty_path, "wb"):
        pass
    print(f"생성됨: {empty_path} (0바이트)")

    corrupted_path = os.path.join(OUTPUT_DIR, "07_corrupted_file.wav")
    rng = random.Random(7)
    with open(corrupted_path, "wb") as f:
        f.write(b"RIFF")
        f.write((100).to_bytes(4, "little"))
        f.write(bytes(rng.randrange(256) for _ in range(200)))
    print(f"생성됨: {corrupted_path} (유효하지 않은 RIFF 헤더 + 임의 바이트)")


if __name__ == "__main__":
    main()
