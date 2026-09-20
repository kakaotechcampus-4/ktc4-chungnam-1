# 평가 영역

QA 담당: 성채원. AI 평가 협력: 이문영, 이인성.

STT 케이스 9개와 기대 결과, 음성 생성 스크립트가 있다. 실제 STT 출력과 기대 결과를 자동 비교하는 채점 스크립트는 아직 없다.

## 테스트 음성 준비 방법

wav 파일은 커밋하지 않고 클론 후 로컬에서 만든다. 원본은 Zeroth-Korean 공개 자료를 가공하며 출처, CC BY 4.0 라이선스와 파일별 생성 방법은 [SOURCES.md](fixtures/speech/SOURCES.md)에 기록한다. 실제 사용자 자료와 마스킹한 실제 자료는 사용하지 않는다.

저장소 루트에서 다음 순서로 실행한다. 이후 네 스크립트는 현재 폴더 기준 상대 경로를 사용하므로 `evals/fixtures/speech/`에서 실행해야 한다.

```bash
cd evals/fixtures/speech
pip install -r requirements.txt      # datasets, soundfile, pydub
python download_samples.py           # source_clips/에 고정 발화 2개 다운로드, 인터넷 필요
python make_baseline.py              # 00_baseline_quiet.wav
python generate_test_cases.py        # 01~05, 08 케이스
python make_invalid_files.py         # 06_empty_file.wav, 07_corrupted_file.wav
```

다운로드와 생성 후 `cases/*.json`의 `inputRef`가 가리키는 파일 9개가 있는지 확인한다. `source_clips/`에는 지정된 두 원본을 사용한다. 합성 스크립트가 파일명 정렬 순서의 처음 두 파일을 읽으므로 다른 음성을 섞으면 입력 조건이 달라진다.

| 케이스 | 조건 | 생성 파일 |
| --- | --- | --- |
| stt-001 | 조용한 2인 발화, 낭독 클립 이어붙임 | `00_baseline_quiet.wav` |
| stt-002 | 배경 소음 | `01_background_noise.wav` |
| stt-003 | 제3자 음성 포함 | `02_third_party_voice.wav` |
| stt-004 | 작은 음성, 불명확 발화 | `03_unclear_speech.wav` |
| stt-005 | 일부 구간 중첩 | `04_overlapping_speech.wav` |
| stt-006 | 너무 짧은 발화 | `05_too_short.wav` |
| stt-007 | 0바이트 파일 | `06_empty_file.wav` |
| stt-008 | 손상 파일 | `07_corrupted_file.wav` |
| stt-009 | 전체 구간 중첩, 화자 구분 불가 | `08_full_overlap_indeterminate.wav` |

<details>
<summary>고정 입력과 기존 재현 확인 기록</summary>

- 다운로드 발화 ID: `187_003_0011`, `191_003_0006`
- 데이터셋 리비전: `1fe937899f828af822293d05e086200946088bdf`
- 합성 스크립트의 난수 seed: `42`. 손상 파일은 `random.Random(7)` 사용.
- 2026-09-12 기존 기록: 다운로드, 기준 음성 생성과 합성까지 실행했고 당시 비교한 6개 파일의 MD5가 이전 로컬 파일과 일치했다.
- 같은 기록에서 무효 파일 2개는 Python `wave`로 열 때 각각 `EOFError`, `Error: not a WAVE file`을 반환했다. wav 입출력과 신호 처리 과정은 ffmpeg 없이 실행됐다.
- 이 기록은 당시 환경의 재현 확인이다. 의존성이나 입력 조건을 바꾸면 다시 확인하며, 합성 결과만으로 실제 면회 성능을 주장하지 않는다.
- wav 커밋 대신 로컬 생성하는 정책에 대한 재검토는 AI와 BE가 함께 한다.

</details>

## 실행과 통과 기준

현재 가능한 것은 자료 준비와 사람이 기대 결과를 대조하는 작업이다. `howToVerify`는 임시 수동 확인 절차이며 자동 채점 완료를 뜻하지 않는다. STT 결과 형식을 정하는 [이슈 #24](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/24) 이후 채점 스크립트와 실행 명령, 결과 해석 및 통과 기준을 함께 추가한다.

| 위치 | 내용 / 상태 |
| --- | --- |
| [cases/](cases/) | 테스트 목적, 입력과 기대 결과 경로 |
| [fixtures/speech/](fixtures/speech/) | 자료 생성 코드와 출처. 생성 음성은 로컬 보관 |
| [expected/](expected/) | 사람이 검토할 기대 결과와 실패 조건, [필드 설명](expected/FIELD_GUIDE.md) |
| `scripts/` | 향후 채점 코드 위치, 아직 없음 |
| `results/baseline/` | 향후 합의된 비교 기준 위치 |
| `results/local/` | 향후 개인 결과 위치, GitHub 반입 금지 |

## 케이스 최소 필드

새 `cases/` 파일은 `schemaVersion`, `caseId`, `area`, `description`, `inputRef`, `expectedRef`, `tags`를 담는다. 실제 형식은 [stt-001](cases/stt-001-quiet-two-speaker.json), 기대 결과 필드는 [FIELD_GUIDE](expected/FIELD_GUIDE.md)를 참고한다. 입력을 바꾸면 출처와 기대 결과도 함께 확인한다.

## 평가 범위와 자료 원칙

STT 정확도와 실패, 화자 전환 및 식별, 이미지 후보의 사실성, 카드의 안전성과 프로필 적합성, 최근 기억 확인형 질문 차단, 리포트와 보호자 평가의 일치, 확인되지 않은 이야기 생성 방지를 평가한다. STT 이외 항목은 평가 구현 범위를 별도로 정해야 한다.

합성 자료 또는 재배포 권한이 확인된 자료만 사용하고 출처, 라이선스와 생성 조건을 기록한다. 실제 이름, 시설명, 사용자 전사문과 음성을 테스트 고정값으로 두지 않으며 wav 차단 규칙에 합성 자료 예외를 추가하지 않는다.
