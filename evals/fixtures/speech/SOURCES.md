# 음성 테스트 자료 출처·라이선스 기록

> evals/README.md의 "자료 원칙"에 따라, 이 폴더에서 생성되는 모든 음성 파일은 여기에
> 출처/라이선스/생성 조건이 기록되어야 한다.
> 실사용자 자료 및 마스킹한 실사용자 자료는 어떤 경우에도 포함하지 않는다.
>
> **wav 파일 자체는 GitHub에 커밋하지 않는다.** `.gitignore`가 실제 사용자 녹음 유출 방지를 위해
> `*.wav`를 전체 차단하고 있고, 합성 자료라 해도 이 저장소에는 예외 없이 이 규칙을 적용하기로 했다
> (`evals/README.md`의 "테스트 음성 준비 방법" 참고). 아래 표는 각 파일을 **로컬에서 생성할 때**
> 어떤 원본과 방법을 쓰는지 기록한 것이다.
>
> **원본 화자·발화는 고정되어 있다** (PR #29 리뷰 반영). `download_samples.py`가 항상
> 화자 187(발화 ID `187_003_0011`)과 화자 191(발화 ID `191_003_0006`)을, 데이터셋 리비전
> `1fe937899f828af822293d05e086200946088bdf` 기준으로 받아온다. 누가 실행해도 완전히 같은
> 음성이 나오므로, `expected/`의 `confidenceRange` 같은 수치 기준이 계속 유효하다.

| 파일명 | 자료 유형 | 원 출처 | 라이선스 | 생성 방법 | 실사용자 자료 여부 |
|---|---|---|---|---|---|
| `00_baseline_quiet.wav` | 공개 데이터셋 가공 (이어붙임) | [Zeroth-Korean](https://huggingface.co/datasets/kresnik/zeroth_korean) (원본: openslr.org/40) | CC BY 4.0 | Zeroth 원본 클립 2개(서로 다른 화자)를 순서대로 이어붙임(`make_baseline.py`). 실제 대화가 아니라 각자 낭독한 클립을 이어붙인 것 — 화자 전환이 자연스럽지 않을 수 있음. 필요시 추후 실제 녹음으로 교체 가능 | 아니오 |
| `01_background_noise.wav` | 공개 데이터셋 가공 | [Zeroth-Korean](https://huggingface.co/datasets/kresnik/zeroth_korean) (원본: openslr.org/40) | CC BY 4.0 | Zeroth 원본 클립에 `generate_test_cases.py`로 화이트노이즈 오버레이 | 아니오 |
| `02_third_party_voice.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립 2개를 `generate_test_cases.py`로 겹쳐 삽입 | 아니오 |
| `03_unclear_speech.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립에 저역통과 필터+볼륨 감소 적용 | 아니오 |
| `04_overlapping_speech.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립 2개를 겹쳐 이어붙임 | 아니오 |
| `05_too_short.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립을 0.4초로 잘라냄 | 아니오 |
| `06_empty_file.wav` | 합성 자료 (원본 없음) | 없음 | 해당 없음 | 원본 없이 `make_invalid_files.py`로 0바이트 파일 생성 | 아니오 |
| `07_corrupted_file.wav` | 합성 자료 (원본 없음) | 없음 | 해당 없음 | 원본 없이 `make_invalid_files.py`로 유효하지 않은 RIFF 헤더 + 임의 바이트 생성. Python wave 모듈 기준 파싱 실패(`Error: not a WAVE file`) 확인함 | 아니오 |
| `08_full_overlap_indeterminate.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립 2개를 처음부터 끝까지(전체 길이) 완전히 겹침(`generate_test_cases.py`의 `case_full_overlap_indeterminate`). `04_overlapping_speech.wav`(일부 구간만 겹침)와 짝을 이루는 케이스 | 아니오 |

## 사용 중인 자료

| 데이터셋 | 라이선스 | 사용 범위 |
|---|---|---|
| [kresnik/zeroth_korean](https://huggingface.co/datasets/kresnik/zeroth_korean) | 자유 사용, 출처 표기 필수 | STT 평가 케이스 음성 자료로 사용 |

## 검토했지만 현재 사용하지 않는 자료

| 데이터셋 | 상태 | 사유 |
|---|---|---|
| [MagicHub Korean Conversational Speech Corpus](https://huggingface.co/datasets/MagicHub/korean-conversational-speech-corpus) | 보류 | 비상업적 이용만 허용, 재배포 금지 조항이 GitHub 반입과 충돌. 팀 확인 전까지 미사용 |
| MINDsLab-ETRI VOTE400 | 미확인 | ETRI 별도 허가 필요, 우선순위 낮음으로 보류 |

## 생성 스크립트

- 원본 다운로드: `download_samples.py`
- 기준 케이스 합성: `make_baseline.py`
- 나머지 합성 케이스(01~05, 08): `generate_test_cases.py`
- 무효 파일 케이스(06, 07): `make_invalid_files.py` (원본/인터넷 불필요)
- 의존성: `requirements.txt` (`pip install -r requirements.txt`). wav 입출력만 사용하므로 ffmpeg는 불필요함

이 스크립트들은 `evals/README.md`의 `scripts/`(평가 실행·비교 코드)가 아니라 `fixtures/`에 속한
자료 생성 스크립트다. 실행 순서와 명령은 `evals/README.md`의 "테스트 음성 준비 방법"을 참고한다.
