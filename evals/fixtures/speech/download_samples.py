"""
Zeroth-Korean 데이터셋에서 미리 정해둔 화자 2명의 발화를
source_clips/ 폴더에 저장하는 스크립트.

#23 PR 리뷰 반영: 화자를 "처음 만나는 서로 다른 두 명"으로 고르면 실행할 때마다
다른 목소리가 나올 수 있어, expected/의 confidenceRange 같은 수치 기준이 팀원마다
달라질 위험이 있었다. 그래서 화자·발화 ID와 데이터셋 버전(revision)을 모두 고정해,
누가 언제 실행해도 완전히 같은 음성이 나오도록 한다.

이 스크립트를 먼저 실행한 뒤, generate_test_cases.py를 실행하면 됩니다.
"""

import os
import soundfile as sf
from datasets import load_dataset

OUTPUT_DIR = "./source_clips"
DATASET_REVISION = "1fe937899f828af822293d05e086200946088bdf"
TARGET_UTTERANCE_IDS = ["187_003_0011", "191_003_0006"]


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Zeroth-Korean 데이터셋을 불러오는 중... (인터넷 연결 필요, 처음엔 다소 걸릴 수 있음)")
    ds = load_dataset(
        "kresnik/zeroth_korean",
        split="train",
        streaming=True,
        revision=DATASET_REVISION,
    )

    remaining = set(TARGET_UTTERANCE_IDS)
    saved = 0
    for example in ds:
        if example["id"] not in remaining:
            continue
        remaining.discard(example["id"])

        audio = example["audio"]
        out_path = os.path.join(OUTPUT_DIR, f"speaker{example['speaker_id']}_{example['id']}.wav")
        sf.write(out_path, audio["array"], audio["sampling_rate"])
        print(f"저장됨: {out_path}  (화자ID: {example['speaker_id']}, 텍스트: {example['text'][:20]}...)")

        saved += 1
        if not remaining:
            break

    if remaining:
        print(f"\n[경고] 다음 발화 ID를 찾지 못했습니다: {sorted(remaining)}")
        print("       데이터셋 리비전이 바뀌었을 수 있습니다. DATASET_REVISION과 TARGET_UTTERANCE_IDS를 확인하세요.")
        return

    print(f"\n완료. {OUTPUT_DIR} 폴더에 {saved}개 파일이 저장되었습니다.")
    print("이제 generate_test_cases.py를 같은 폴더에서 실행하세요:")
    print("    python generate_test_cases.py")


if __name__ == "__main__":
    main()
