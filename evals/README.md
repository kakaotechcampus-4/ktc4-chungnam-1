# 평가 영역

검토 담당: 이문영, 이인성

상태: 평가 코드가 추가되기 전의 공통 구조와 원칙

## 평가 대상

- 이미지 분석 후보의 사실성
- STT 정확도와 처리 실패
- 화자 전환과 화자 식별
- 카드 안전성과 프로필 적합성
- 최근 기억 확인형 질문 차단
- 리포트 관찰값과 보호자 평가의 일치
- 확인되지 않은 이야기 생성 방지

## 예정 구조

    evals/
    ├─ cases/
    ├─ fixtures/
    ├─ expected/
    ├─ scripts/
    └─ results/
       ├─ baseline/
       └─ local/

- `cases/`: 테스트 목적, 입력과 기대 결과 경로
- `fixtures/`: 합성 자료 또는 사용 권한이 확인된 자료 (자료 생성/재생성 스크립트도 함께 보관)
- `expected/`: 사람이 검토한 기대 결과
- `scripts/`: 평가 실행과 비교 코드
- `results/baseline/`: 팀이 합의한 비교 기준
- `results/local/`: 개인 결과, GitHub 반입 금지

## 자료 원칙

- 실제 사용자 자료와 마스킹한 실제 자료를 사용하지 않음
- 합성 자료 또는 재배포 권한을 확인한 자료만 사용
- 자료의 출처, 라이선스와 생성 조건 기록
- 실제 이름, 시설명, 전사문과 음성을 테스트 고정값으로 사용하지 않음

## 테스트 음성 준비 방법

STT 케이스(`stt-001`~`stt-009`)가 참조하는 wav 파일은 **저장소에 커밋하지 않고, 클론 후 스크립트로
로컬에 생성**한다. `.gitignore`가 실제 사용자 녹음 유출 방지를 위해 `*.wav`를 전체 차단하고 있는데,
합성 자료라 해도 이 저장소에는 예외 없이 이 규칙을 그대로 적용하기로 했다. 원본은 재배포 허가가
확인된 자료(Zeroth-Korean, CC BY 4.0)를 가공해 만든다 (출처·라이선스·생성 방법은
`fixtures/speech/SOURCES.md`에 기록).

새로 저장소를 받은 팀원은 케이스를 실행하기 전에 아래 절차로 wav 파일을 먼저 만들어야 한다.

```bash
cd evals/fixtures/speech
pip install -r requirements.txt      # datasets, soundfile, pydub
python download_samples.py           # source_clips/ 에 서로 다른 화자 클립 2개 저장 (인터넷 필요)
python make_baseline.py              # 00_baseline_quiet.wav 생성
python generate_test_cases.py        # 01_*.wav ~ 05_*.wav, 08_full_overlap_indeterminate.wav 생성
python make_invalid_files.py         # 06_empty_file.wav, 07_corrupted_file.wav 생성 (인터넷 불필요)
```

- 실행 위치: 반드시 `evals/fixtures/speech/`에서 실행 (스크립트가 현재 폴더 기준 상대 경로를 사용)
- 위 절차를 2026-09-12에 실제로 처음부터 끝까지 실행해 확인함: `download_samples.py` →
  `make_baseline.py` → `generate_test_cases.py`로 만든 6개 파일이 이전에 로컬에 있던 파일과
  MD5까지 동일함 (재현 확인됨). `make_invalid_files.py`가 만드는 2개 파일도 Python `wave` 모듈로
  열었을 때 각각 `EOFError`, `Error: not a WAVE file`이 나 실제로 무효한 파일임을 확인함
- `download_samples.py`는 스트리밍 순회 중 처음 만나는 서로 다른 화자 2명을 저장하므로, 실행마다
  어떤 화자가 저장될지는 보장되지 않는다. 나머지 스크립트는 특정 화자 ID를 가정하지 않고
  `source_clips/`의 파일명 정렬 기준 처음 2개를 사용하므로 이 비결정성에 영향받지 않는다.
- 이 파이프라인은 wav 입출력과 pydub의 순수 파이썬 신호 처리(필터, 화이트노이즈)만 사용하므로
  ffmpeg 설치 없이도 동작함을 확인함
- 실제 환자·보호자 음성은 어떤 경우에도 이 절차에 사용하지 않는다
- 이 결정(커밋 대신 스크립트 생성)은 AI·BE 담당자 리뷰에서 이견이 있으면 재논의한다

## 케이스 최소 필드

```json
{
  "schemaVersion": 1,
  "caseId": "card-safety-001",
  "area": "cardGeneration",
  "description": "최근 기억 확인형 질문을 차단한다",
  "inputRef": "fixtures/profiles/card-safety-001.json",
  "expectedRef": "expected/card-safety-001.json",
  "tags": ["safety", "recentMemory"]
}
```

## 실행과 통과 기준

첫 평가 스크립트가 병합될 때 실제 실행 명령, 결과 해석과 통과 기준을 함께 기록한다. 동작하지 않는 명령과 검증하지 않은 기준은 적지 않는다.

상태: STT 케이스 9개(`cases/stt-001`~`stt-009`)의 자료와 기대 결과는 준비됨. 실제 STT 결과를
`expected/`와 자동 비교하는 평가 스크립트는 아직 없음 — AI팀이 STT 결과 형식을 정하는 이슈 #24 완료
후 작성한다. 그 전까지 `howToVerify`에 적힌 절차는 사람이 육안으로 대조하는 임시 방법이며, 이를
"평가 완료"로 표시하지 않는다.
