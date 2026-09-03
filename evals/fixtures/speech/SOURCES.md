# 음성 테스트 자료 출처·라이선스 기록

> evals/README.md의 "자료 원칙"에 따라, 이 폴더의 모든 음성 파일은 여기에 출처/라이선스/생성 조건이 기록되어야 GitHub에 반입 가능하다.
> 실사용자 자료 및 마스킹한 실사용자 자료는 어떤 경우에도 포함하지 않는다.

| 파일명 | 자료 유형 | 원 출처 | 라이선스 | 생성 방법 | 실사용자 자료 여부 |
|---|---|---|---|---|---|
| `00_baseline_quiet.wav` | 공개 데이터셋 가공 (이어붙임) | [Zeroth-Korean](https://huggingface.co/datasets/kresnik/zeroth_korean) (원본: openslr.org/40) | CC BY 4.0 | Zeroth 원본 클립 2개(서로 다른 화자)를 순서대로 이어붙임(`make_baseline.py`). 실제 대화가 아니라 각자 낭독한 클립을 이어붙인 것 — 화자 전환이 자연스럽지 않을 수 있음. 필요시 추후 실제 녹음으로 교체 가능 | 아니오 |
| `01_background_noise.wav` | 공개 데이터셋 가공 | [Zeroth-Korean](https://huggingface.co/datasets/kresnik/zeroth_korean) (원본: openslr.org/40) | CC BY 4.0 | Zeroth 원본 클립에 `generate_test_cases.py`로 화이트노이즈 오버레이 | 아니오 |
| `02_third_party_voice.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립 2개를 `generate_test_cases.py`로 겹쳐 삽입 | 아니오 |
| `03_unclear_speech.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립에 저역통과 필터+볼륨 감소 적용 | 아니오 |
| `04_overlapping_speech.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립 2개를 겹쳐 이어붙임 | 아니오 |
| `05_too_short.wav` | 공개 데이터셋 가공 | Zeroth-Korean (동일) | CC BY 4.0 | Zeroth 원본 클립을 0.4초로 잘라냄 | 아니오 |

## 검토했지만 현재 사용하지 않는 자료

| 데이터셋 | 상태 | 사유 |
|---|---|---|
| [MagicHub Korean Conversational Speech Corpus](https://huggingface.co/datasets/MagicHub/korean-conversational-speech-corpus) | 보류 | 비상업적 이용만 허용, 재배포 금지 조항이 GitHub 반입과 충돌. 팀 확인 전까지 미사용 |
| MINDsLab-ETRI VOTE400 | 미확인 | ETRI 별도 허가 필요, 우선순위 낮음으로 보류 |

## 생성 스크립트

- 원본 다운로드: `download_samples.py`
- 케이스 합성: `generate_test_cases.py`

두 스크립트 모두 evals/scripts/ 에 함께 보관 권장 (README 예정 구조의 `scripts/`에 해당).
