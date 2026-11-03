# #116 실제 모델 점검 입력, 실행기, 원본 출력

[점검 기록](../2026-11-03-real-model-spot-check.md)의 근거 자료입니다. 모두 이 점검을 위해 새로 지은 합성 자료와 그 출력이고, 실제 사용자 자료, 실제 이름과 시설명은 없습니다. 키는 들어 있지 않습니다.

## 파일

| 파일 | 내용 |
| --- | --- |
| `inputs.py` | 실행에 쓴 합성 입력 원본. UUID 판은 `with_uuids`가 고정 네임스페이스 `6f1c2b1e-1160-4c3a-9b1e-2026110300ab`로 원래 ID마다 UUID5를 만들어 바꿉니다 |
| `inputs/*.json` | `inputs.py`의 값을 그대로 JSON으로 저장한 읽기용 사본. `id-map-*.json`은 원래 ID와 UUID의 대응표 |
| `run.py` | 실행기. 키는 `ML_API_KEY` 환경 변수에서만 읽고, 출력과 오류 문장에서 키 문자열을 지웁니다. 호출 상한 40회 |
| `scan.py` | 출력 문장에 `has_medical_effect_claim`, 카드 질문 금지어(`_BANNED`), 추가 키워드를 돌리는 검사 |
| `show.py` | 카드 출력의 UUID를 원래 ID로 되돌려 보여 주는 보조 스크립트 |
| `outputs/*.json` | 2026-11-03 실행의 원본 출력. 실행기가 쓴 파일과 바이트 단위로 같습니다 |
| `outputs/calls.json` | 실행별 호출 수, 시간, 토큰 사용량 원장 |

실행 이름과 파일의 대응은 다음과 같습니다. A0만 실행 뒤 파일 이름을 바꿨고, 원장(`calls.json`)에는 실행 당시 이름 `card-rich`로 남아 있습니다.

| 점검 기록의 실행 | 입력 | 출력 |
| --- | --- | --- |
| 카드 A0 | `inputs/card-rich.json` (`CARD_RICH`) | `outputs/card-rich-nonuuid.json` |
| 카드 A | `inputs/card-rich-uuid.json` (`CARD_RICH_UUID`) | `outputs/card-rich-uuid.json` |
| 카드 B | `inputs/card-sparse-uuid.json` (`CARD_SPARSE_UUID`) | `outputs/card-sparse-uuid.json` |
| 리포트, 변경 제안 R1 | `inputs/report-clear.json` | `outputs/report-clear.json`, `outputs/proposals-clear.json` |
| 리포트, 변경 제안 R2 | `inputs/report-merged.json` | `outputs/report-merged.json`, `outputs/proposals-merged.json` |
| 리포트, 변경 제안 R3 | `inputs/report-third.json` | `outputs/report-third.json`, `outputs/proposals-third.json` |

`inputs/card-sparse.json`(문자열 ID 판)은 실행하지 않았습니다.

## 다시 실행하는 방법

저장소 루트에서 ai 프로젝트 환경으로 실행합니다. 출력 폴더는 `SPOT_CHECK_OUT` 환경 변수로 정하고, 없으면 OS 임시 폴더의 `saerok-spot-check-116`을 씁니다. 커밋된 `outputs/`는 덮어쓰지 않습니다.

```bash
D=evals/results/2026-11-03-real-model-spot-check
uv run --offline --project ai python $D/run.py check          # 모델 호출 없이 입력이 요청 계약을 통과하는지 확인
uv run --offline --project ai python $D/inputs.py             # inputs/*.json 다시 생성
uv run --offline --project ai python $D/scan.py card-rich-uuid report-third   # 커밋된 출력 검사
python $D/show.py card-rich-uuid

# 실제 모델 호출. 카테캠 ML API 키가 필요하고 호출 수가 차감됩니다.
ML_API_KEY=... uv run --offline --project ai python $D/run.py reports           # 6회 예상
ML_API_KEY=... uv run --offline --project ai python $D/run.py card rich-uuid    # 5~6회 예상
```

최초 실행기에는 경로와 `check` 모드만 바꿨습니다. 이후 Luna 6 재점검을 위해
`SPOT_CHECK_MODEL` 선택, 요청 모델과 한도 기록, 오류의 URL 제거를 추가했습니다.
변수를 생략하면 기존 `gpt-5.6-luna`를 사용하고 출력 상한은 현재 `ChatConfig`를 따릅니다.
새 모델은 `SPOT_CHECK_MODEL=gpt-6-luna`로 지정하고 빈 `SPOT_CHECK_OUT` 폴더에 저장합니다.
입력과 기존 `outputs/`는 바꾸지 않습니다. 기능 실행이 실패하면 종료 코드 1입니다.
`scan.py`, `show.py`와 `inputs.py`의 입력 값은 그대로입니다.

## 재현의 범위

- 같은 입력과 같은 호출 인자는 다시 넣을 수 있지만 같은 출력은 기대할 수 없습니다. 모델 응답은 실행마다 달라질 수 있고, 이번 점검은 입력마다 1회씩만 실행해 출력이 매번 같은지 확인하지 않았습니다.
- 카드 생성의 seed 116은 선정 단계의 확률 추첨(`random.Random(seed)`)만 고정합니다. 조사, 연결 판정, 문안 단계의 모델 출력은 고정하지 않습니다.
- 출력은 `local/final-integration-20261103` 브랜치 `1b3acaa`의 코드와 프롬프트(카드 v1, `report-2`, `proposals-3`), `gpt-5.6-luna` 기준입니다. 코드, 프롬프트나 모델이 바뀌면 다른 조건의 실행입니다.
- 출력 폴더를 다시 쓰면 `calls.json`이 이어서 누적됩니다. 새 실행은 빈 폴더에서 시작해야 호출 상한 40회가 실행 단위로 적용됩니다.
