"""
Zeroth-Korean 데이터셋에서 서로 다른 화자의 wav 클립 2개를 받아
source_clips/ 폴더에 저장하는 스크립트.

이 스크립트를 먼저 실행한 뒤, generate_test_cases.py를 실행하면 됩니다.
"""

import os
import soundfile as sf
from datasets import load_dataset

OUTPUT_DIR = "./source_clips"


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Zeroth-Korean 데이터셋을 불러오는 중... (인터넷 연결 필요, 처음엔 다소 걸릴 수 있음)")
    ds = load_dataset("kresnik/zeroth_korean", split="train", streaming=True)

    saved = 0
    seen_speakers = set()
    for example in ds:
        speaker = example["speaker_id"]
        # 서로 다른 화자의 클립을 하나씩 골라서 저장 (2개)
        if speaker in seen_speakers:
            continue
        seen_speakers.add(speaker)

        audio = example["audio"]
        out_path = os.path.join(OUTPUT_DIR, f"speaker{speaker}_{example['id']}.wav")
        sf.write(out_path, audio["array"], audio["sampling_rate"])
        print(f"저장됨: {out_path}  (화자ID: {speaker}, 텍스트: {example['text'][:20]}...)")

        saved += 1
        if saved >= 2:
            break

    print(f"\n완료. {OUTPUT_DIR} 폴더에 {saved}개 파일이 저장되었습니다.")
    print("이제 generate_test_cases.py를 같은 폴더에서 실행하세요:")
    print("    python generate_test_cases.py")


if __name__ == "__main__":
    main()
