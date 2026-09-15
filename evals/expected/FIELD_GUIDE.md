# expected/*.json 필드 설명

> `cases/*.json`의 `expectedRef`가 가리키는 파일들의 필드 의미를 정리한 문서.
> README(evals/README.md)의 "케이스 최소 필드"는 `cases/`용 형식이고, 이 문서는 그 짝인 `expected/`용 형식을 설명한다.

| 필드 | 의미 | 항상 있음? |
|---|---|---|
| `schemaVersion` | 이 파일 형식의 버전. `cases/`쪽과 동일하게 관리 | 항상 |
| `caseId` | 어느 케이스의 기대 결과인지 (`cases/`의 `caseId`와 반드시 일치해야 함) | 항상 |
| `scenario` | 이 음성 파일이 실제로 어떤 조건으로 만들어졌는지에 대한 사람이 읽는 설명. "왜 이 파일이 이 케이스에 해당하는지"를 알 수 있게 함 | 항상 |
| `expectedResult` | **정상적으로 처리됐을 때** 나와야 하는 값들. `transcript`(텍스트), `confidenceRange`(신뢰도 범위), `speakerLabel`(화자 태깅 결과), `errorCode`(정상이면 보통 `null`) | 항상 |
| `failureCondition` | 어떤 상황이면 "실패"로 봐야 하는지에 대한 기준 설명 (사람이 읽는 글) | 항상 |
| `onFailure` | 실패했을 때 **시스템이 실제로 반환해야 하는 값**. `transcript: null`, `errorCode: "..."` 같은 구체적인 값 | 실패가 예상되는 케이스만 (② ③ ④ ⑤ ⑥) |
| `groundTruth` | QA가 이 파일을 직접 만들면서 이미 알고 있는 "정답 정보". 예: 제3자 음성이 몇 초 지점에 들어갔는지. 검증할 때 이 정보와 실제 출력 결과를 육안으로 대조하는 용도 | 화자 구간 확인이 필요한 케이스만 (③ ⑤) |
| `howToVerify` | 실제 STT 파이프라인이 생겼을 때, 이 파일로 어떻게 검증하면 되는지에 대한 구체적인 절차 | 검증 절차가 직관적이지 않은 케이스만 (③ ⑤) |
| `uiMessage` | (선택) 실패 시 앱 화면에 보여줄 안내 문구 예시. FE가 참고할 수 있도록 넣어둔 것 | 있으면 좋지만 필수 아님 |
| `notes` | 그 외 주의사항, 예시값이라는 표시, 향후 개선 방향 등 자유 메모 | 항상 |

## 왜 케이스마다 필드가 조금씩 다른가

- `expectedResult`, `failureCondition`, `notes`는 모든 케이스에 공통으로 있어야 하는 필드
- `onFailure`, `groundTruth`, `howToVerify`는 그 케이스 성격에 따라 필요할 때만 추가하는 필드. 억지로 모든 케이스에 다 넣지 않아도 됨 (예: ①번 기준 케이스는 애초에 실패 상황을 다루지 않으니 `onFailure`가 없음).

## 새 케이스를 추가할 때

1. `cases/`에 케이스 메타정보(JSON) 먼저 작성
2. `expected/`에 위 표의 필드들 중 필요한 것만 골라서 작성
3. `fixtures/speech/`에 실제 wav 파일 추가 + `SOURCES.md`에 출처 기록
