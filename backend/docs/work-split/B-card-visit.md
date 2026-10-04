# 작업 B: 카드·면회

> 담당 파이프라인: **카드 생성 (8-2)**
>
> 정본은 [API 명세](../../../docs/architecture/api-spec.md)다. 이 문서는 분담을 위해 담당 부분을 옮기고 구현 메모를 더한 것이다. 계약을 바꿔야 하면 API 명세를 먼저 고치고 이 문서를 맞춘다.

## 시작하기

- 브랜치: 공통 기반 PR 1~4가 병합된 develop에서 `feature/backend-card-visit`
- DB 사용 규칙: [backend/README.md의 DB 연결과 저장소 작성 규칙](../../README.md#db-연결과-저장소-작성-규칙)
- 쓰는 공통 기반
  - DB와 인증: `DbConnectionDep`(요청별 연결), `CurrentAccountDep`(현재 계정), `require_owned`(소유 확인, `app/services/ownership.py`)
  - 사진: `validate_image`(`app/services/image_validation.py`)와 `ImageStorageDep`(`object_key`, `upload`, `create_download`, `delete`). 사용 순서: [README 사진 저장](../../README.md#사진-저장-s3)
  - worker: `Worker`와 `run_worker_main`(`app/workers/base.py`), 테이블별 대기열. 작성법: [README worker 공통 골격](../../README.md#worker-공통-골격)
  - 테스트: 임시 DB fixture `migrated_database_url`, 비동기 실행 `tests/support.run`
- worker는 공통 골격을 쓴다. 작업을 가져오는 반복문과 임대는 만들지 않고 처리 함수 `async def process(connection, job)`만 만든다. AI 서버 호출은 트랜잭션 밖에서 하고 결과 저장만 트랜잭션으로 묶는다.
- 공통 요청, 응답, 오류 형식: [API 명세 공통](../../../docs/architecture/api-spec.md#공통)

## 담당 API

| # | 메서드 | 경로 | 지금 상태 | 시작 조건 |
| --- | --- | --- | --- | --- |
| 2-5 | `POST` | `/api/v1/profiles/{profileId}/complete-setup` | 신규 | 미정 6 결정 후 |
| 4-1 | `POST` | `/api/v1/profiles/{profileId}/card-generations` | 신규 | 미정 6 결정 후 |
| 4-2 | `GET` | `/api/v1/profiles/{profileId}/card-generations/latest` | 신규 | 바로 |
| 4-3 | `GET` | `/api/v1/card-generations/{setId}` | 신규 | 바로 |
| 5-1 | `POST` | `/api/v1/visit-sessions` | 신규 | 바로 |
| 5-2 | `POST` | `/api/v1/visit-sessions/{sessionId}/photo` | 신규 | 바로 |
| 5-3 | `POST` | `/api/v1/visit-sessions/{sessionId}/cards` | 신규 | 바로 |
| 8-2 | `POST` | (내부) `/internal/v1/card-generations` | 신규 | 바로. 대기열 `CardGenerationQueue`는 준비됨 |

## 테이블 쓰기 소유권

다른 담당의 테이블은 읽기만 한다. 다른 담당 테이블에 써야 하면 그 담당이 제공하는 함수를 쓴다.

| 테이블 | 이 작업이 쓰는 것 | 다른 담당 |
| --- | --- | --- |
| `card_sets` | 2-5, 4-1 생성, 8-2 결과, 5-1 회차 연결 | |
| `profile_topics` | 8-2 새 주제 | |
| `conversation_cards` | 8-2 생성, 5-1과 5-3의 `selected` | C가 6-1에서 `review_reaction`, 8-3에서 `report_summary`를 쓴다 |
| `visit_sessions` | 5-1 생성 | C가 `evaluation_*`, `report_*` 컬럼을 쓴다 |
| `photos` 중 `session_id` 있음 | 5-2 면회 사진 | A가 프로필 사진과 8-4 결과를 쓴다 |
| `profiles`의 세부 정보 네 항목 | 2-5 | A의 2-4도 같은 컬럼을 고친다 |

읽기만 하는 것: `profiles`, `life_facts`, `topic_feedback`(8-2 요청 조립)

## 다른 담당과 맞출 함수

- **제공** `start_card_generation(connection, profile_id)`: 2-5와 4-1이 쓴다. 이미 `running`인 작업이 있으면 그 작업을 돌려준다.
- **사용** C의 `load_visit_session(connection, session_id)`: `VisitSession` 응답과 `sessionStatus` 계산. 5-1과 5-3의 응답은 정의상 항상 `evaluationPending`이므로, C의 함수가 들어오기 전에는 `sessionStatus = evaluationPending`, `participantCount`와 `analysisId`는 `null`로 응답하고 들어온 뒤 바꾼다.
- **사용** `ImageStorageDep`과 `validate_image`(5-2)
- **사용** `CardGenerationQueue`(`app/services/card_generation_jobs.py`)와 `Worker`: 8-2는 처리 함수와 실행 진입점만 만든다.

## 작업 순서

1. **미정 6을 먼저 정한다.** 정해지기 전에는 2-5와 4-1에서 카드 작업 행을 만들 수 없다. 스키마 작성자, AI 담당과 정한다.
2. 4-2, 4-3. 테스트에서는 카드 묶음을 SQL로 직접 넣는다.
3. 5-1, 5-3
4. 8-2 요청 조립, 응답 검증, 결과 저장
5. 미정 6 결정 후 `start_card_generation`, 2-5, 4-1
6. 5-2, 8-2 처리 함수와 worker 실행 진입점

## 장별 공통 규칙

### 2. 프로필

피보호자의 이름, 성별, 생년월일은 서버의 `profiles`에 저장한다. 내부 API(8절) 요청에는 넣지 않고 BE가 생년월일로 계산한 연령대만 보낸다.

프로필 입력 상태(`setupStatus`)는 저장하지 않는다. 2-5가 세부 정보 저장과 첫 카드 생성 작업을 한 트랜잭션에서 만들므로, 카드 생성 작업(`card_sets`)이 하나라도 있으면 `completed`, 없으면 `inProgress`다.

### 4. 대화 카드

카드 생성은 비동기 작업이며 `card_sets`에 저장한다. 프로필마다 진행 중(`running`)인 작업은 하나뿐이다. 홈의 `오늘의 대화카드 받기`는 최신 작업이 `completed`이고 아직 회차에 쓰이지 않았을 때(`usedBySessionId`가 `null`) 활성화한다.

### 5. 면회

회차는 녹음을 시작할 때 만든다. 녹음 일시정지와 종료는 단말에서 처리하고 서버에 알리지 않는다.

회차 상태는 저장하지 않고 평가, 음성 분석 작업과 리포트로 계산한다.

| `sessionStatus` | 조건 |
| --- | --- |
| `evaluationPending` | 보호자 평가 전 |
| `audioPending` | 평가 후 음성 접수 전. 작업이 없거나 업로드 단계에서 실패한 작업만 있음 |
| `processing` | 음성 분석 작업이 `queued`, `transcribing`, `sttCompleted`, `generatingReport` |
| `completed` | 리포트 저장 |
| `failed` | 접수된 음성 분석 작업이 `failed` |

### 8. 내부 API (백엔드 → AI 서버)

백엔드 worker가 동기 호출한다. 앱은 호출하지 않는다. 원본 파일은 수명이 짧은 S3 Presigned GET URL로만 전달한다. 피보호자의 이름, 성별, 생년월일은 어떤 요청에도 넣지 않는다.

AI 서버 호출이 실패하면 해당 작업을 `failed`로 바꾸고 다음 `errorCode`를 남긴다: `AI_SERVER_TIMEOUT`, `AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `INVALID_AI_RESPONSE`. worker가 임대 시간 안에 작업을 끝내지 못하면 `WORKER_LEASE_EXPIRED`다. 자동으로 다시 시도하지 않는다.

8-2~8-4 응답의 `model`, `promptVersion`은 결과와 함께 저장한다.

## API 명세와 구현 메모

### 2-5. `POST /api/v1/profiles/{profileId}/complete-setup` — 신규

온보딩의 `마치기`에서 호출한다. 세부 정보 네 항목을 저장하고 카드 생성을 시작한다.

요청

```json
{
  "occupation": "재봉 일을 오래 하셨어요. 동인천에서 수선집을 하셨어요.",
  "hometown": null,
  "hobby": "노래 부르기를 좋아하셨어요.",
  "family": null
}
```

- 네 항목을 모두 보낸다. 건너뛴 항목은 `null`이며 빈 문자열은 받지 않는다.
- 음성과 텍스트 중 어떤 방식으로 입력했는지와 항목별 입력 시도 상태는 단말에서만 쓰고 보내지 않는다.

응답 `202`

```json
{
  "schemaVersion": 1,
  "profileId": "00000000-0000-4000-8000-000000000101",
  "setupStatus": "completed",
  "cardGeneration": {
    "setId": "00000000-0000-4000-8000-000000000401",
    "generationStatus": "running"
  }
}
```

- 네 항목 저장과 카드 생성 작업 생성을 한 트랜잭션으로 처리한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `SETUP_ALREADY_COMPLETED` |

**구현 메모**

- `require_owned(connection, PROFILE, ...)`로 확인한다. 카드 작업이 하나라도 있으면 409 `SETUP_ALREADY_COMPLETED`다.
- 한 트랜잭션에서 `profiles`의 네 항목을 고치고 `start_card_generation`을 부른다.
- `card_sets.model`과 `prompt_version`은 `running`으로 만들 때부터 NOT NULL인데 8-2 응답 전에는 값이 없다(미정 6). 임의 값을 넣지 말고 결정 후 구현한다.

<br>

### 4-1. `POST /api/v1/profiles/{profileId}/card-generations` — 신규

카드 생성 작업을 만든다. 본문 없음.

호출 시점

- 7-4 완료 후
- 4-2 결과가 `failed`일 때 다시 시도
- 변경 제안이 없는 리포트 뒤의 호출 시점은 미정([미정 사항](#미정-사항) 2)

응답 `202`

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "generationStatus": "running"
}
```

- `running` 작업이 이미 있으면 새로 만들지 않고 그 작업을 `200`으로 반환한다.
- 서버는 8-2를 호출하고 카드 12장과 새 주제를 저장한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `PROFILE_SETUP_INCOMPLETE` |

**구현 메모**

- 카드 작업이 하나도 없으면 409 `PROFILE_SETUP_INCOMPLETE`다.
- `running`은 프로필당 하나다(부분 유일 인덱스 `uq_card_sets_running`). `INSERT ... ON CONFLICT (profile_id) WHERE status = 'running' DO NOTHING RETURNING *`로 넣고, 넣지 못했으면 기존 `running`을 읽어 200으로 돌려준다.

<br>

### 4-2. `GET /api/v1/profiles/{profileId}/card-generations/latest` — 신규

가장 최근 카드 생성 작업이다. 홈에서 버튼 상태를 정한다. `running`이면 폴링한다.

응답 `200` — [CardSet](#cardset)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_GENERATION_NOT_FOUND` |

**구현 메모**

- `created_at DESC`의 첫 행이다. 없으면 404다.
- `CardSet` 응답 공통: `usedBySessionId`는 `card_sets.session_id`, `cards`는 `completed`일 때만 `position` 순으로 담고 `topic`은 `profile_topics`와 조인한다. `evidenceSource`는 DB 값 `life_fact`를 API 값 `lifeFact`로 바꾼다.

<br>

### 4-3. `GET /api/v1/card-generations/{setId}` — 신규

응답 `200` — [CardSet](#cardset)

- `cards`는 `completed`일 때만 채운다. `position` 1~9는 선택 화면용, 10~12는 면회 중 보충용이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_GENERATION_NOT_FOUND` |

**구현 메모**

- `require_owned(connection, CARD_SET, set_id, ...)`로 확인한다.

<br>

### 5-1. `POST /api/v1/visit-sessions` — 신규

녹음을 시작할 때 고른 카드로 회차를 만든다.

요청

```json
{
  "setId": "00000000-0000-4000-8000-000000000401",
  "selectedCardIds": [
    "00000000-0000-4000-8000-000000000501",
    "00000000-0000-4000-8000-000000000502"
  ]
}
```

- `selectedCardIds`는 1~9개이며 해당 작업의 `position` 1~9 안에서 고른다.

응답 `201` — [VisitSession](#visitsession), `sessionStatus`는 `evaluationPending`

- `startedAt`은 서버 수신 시각이다.
- 고른 카드를 `selected`로 바꾸고, 작업의 `usedBySessionId`를 이 회차로 채운다.
- 녹음 동의는 가입 때 받으므로 이 요청에서 받지 않는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_GENERATION_NOT_FOUND` |
| 409 | `CARD_GENERATION_NOT_COMPLETED`, `CARD_SET_ALREADY_USED` |
| 422 | `INVALID_CARD_SELECTION` |

**구현 메모**

- `require_owned(connection, CARD_SET, ...)`로 확인한다(없으면 `CARD_GENERATION_NOT_FOUND`).
- `selectedCardIds`는 중복 없이 1~9개이며 이 묶음의 `position` 1~9 카드여야 한다.
- 한 트랜잭션에서 `visit_sessions`를 넣고(`started_at` 기본값이 서버 시각), `UPDATE card_sets SET session_id = %s WHERE set_id = %s AND session_id IS NULL`로 묶음을 연결한다. 0행이면 동시 요청이 먼저 쓴 것이므로 409 `CARD_SET_ALREADY_USED`로 롤백한다. 마지막으로 고른 카드를 `selected = true`로 바꾼다.
- `card_sets(session_id, profile_id)` FK가 회차와 묶음이 같은 프로필인지 DB에서도 확인한다.

<br>

### 5-2. `POST /api/v1/visit-sessions/{sessionId}/photo` — 신규

면회 사진을 회차 기록으로 올린다. 사진은 녹음 전에 단말에서 찍고 5-1 뒤에 올린다. 사진 없이 시작하면 호출하지 않으며 회차의 `photoId`는 `null`로 남는다.

요청 `multipart/form-data`

| 필드 | 값 |
| --- | --- |
| `image` | JPEG 또는 PNG. 서버 설정의 크기 상한(기본 20MB) 이하 |

응답 `201` — [VisitPhoto](#visitphoto)

- `evaluationPending` 상태에서만 받는다. 다시 올리면 기존 사진을 지우고 교체한다.
- 이미지 분석을 하지 않는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `INVALID_SESSION_STATE` |
| 413 | `IMAGE_TOO_LARGE` |
| 422 | `INVALID_IMAGE_FORMAT` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` |

**구현 메모**

- `require_owned(connection, VISIT_SESSION, ...)`로 확인한다. `evaluated_at`이 있으면 409 `INVALID_SESSION_STATE`다.
- 업로드 순서는 3-1과 같다: `validate_image` → `storage.object_key` → `storage.upload` → 행 저장(실패하면 `storage.delete`).
- 다시 올리면 기존 사진 행을 지우고 새로 넣는다(`uq_photos_session`). 지운 행의 키는 trigger가 S3 삭제 대기열에 넣는다.
- 면회 사진은 분석하지 않는다. `analysis_status`는 기본값 `pending`으로 남지만, A의 8-4 worker는 `session_id`가 있는 행을 가져가지 않는다.

<br>

### 5-3. `POST /api/v1/visit-sessions/{sessionId}/cards` — 신규

면회 중 보충 카드를 추가한다.

요청

```json
{ "cardIds": ["00000000-0000-4000-8000-000000000510"] }
```

- 같은 작업의 `position` 10~12 안에서 고른다. 이미 추가한 카드는 무시한다.

응답 `200` — [VisitSession](#visitsession)

- 추가한 카드를 `selected`로 바꾸고 `selectedCardIds`에 더한다.
- `evaluationPending` 상태에서만 받는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `INVALID_SESSION_STATE` |
| 422 | `INVALID_CARD_SELECTION` |

**구현 메모**

- `require_owned(connection, VISIT_SESSION, ...)`로 확인한다. `evaluated_at`이 없을 때만 받는다. 같은 묶음의 `position` 10~12 카드만 받고, 이미 `selected`인 카드는 무시한다.

<br>

### 8-2. `POST /internal/v1/card-generations` — 신규

요청

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
  "context": {
    "ageRange": "80s",
    "conditionStage": "mildCognitiveImpairment",
    "profileFacts": {
      "occupation": "재봉 일을 오래 하셨어요. 동인천에서 수선집을 하셨어요.",
      "hometown": null,
      "hobby": "노래 부르기를 좋아하셨어요.",
      "family": null
    },
    "lifeFacts": [
      {
        "factId": "00000000-0000-4000-8000-000000000111",
        "title": "단골손님",
        "content": "수선집에 오래 다닌 단골손님이 많았어요."
      }
    ],
    "topics": [
      {
        "topicId": "00000000-0000-4000-8000-000000000451",
        "title": "노래 이야기",
        "description": "즐겨 부르시던 노래와 그 노래에 얽힌 기억을 여쭤보는 주제예요.",
        "feedback": [
          { "action": "more", "decidedAt": "2026-08-21T15:00:00+09:00" }
        ]
      }
    ]
  },
  "constraints": {
    "avoidRecentMemoryCheck": true,
    "avoidMedicalInterpretation": true
  }
}
```

- `ageRange`: BE가 생년월일로 계산한 `{십 단위 나이}s` (예: `70s`, `80s`)
- `topics`: 이 프로필의 기존 주제와 승인된 주제 피드백(`topic_feedback`)이다. 첫 생성에는 빈 배열이다.
- 사진 설명은 3-3이 정해질 때까지 넣지 않는다.
- BE는 요청의 `context`를 `card_sets.generation_log`의 `input`에 저장한다.

응답 `200`

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
  "model": "synthetic-model",
  "promptVersion": "card-v1",
  "cards": [
    {
      "position": 1,
      "topic": { "topicId": "00000000-0000-4000-8000-000000000451" },
      "cardTitle": "즐겨 부르던 노래",
      "description": "자주 흥얼거리시던 노래를 함께 떠올려 보는 카드예요.",
      "primaryQuestion": "젊으셨을 때 즐겨 부르던 노래가 있으셨어요?",
      "followUpQuestions": [
        "그 노래는 어디서 처음 들으셨어요?",
        "누구와 함께 부르곤 하셨어요?",
        "그 노래를 들으면 어떤 장면이 떠오르세요?"
      ],
      "evidenceSource": "lifeFact",
      "evidence": [ { "...": "미정" } ]
    },
    {
      "position": 2,
      "topic": {
        "title": "재봉 일",
        "description": "젊은 시절 하시던 일과 그때의 하루를 여쭤보는 주제예요."
      },
      "cardTitle": "수선집 시절",
      "description": "수선집을 하시던 때의 손님과 옷 이야기를 나누는 카드예요.",
      "primaryQuestion": "어떤 옷을 주로 만드셨어요?",
      "followUpQuestions": [
        "일할 때 자주 쓰던 도구가 있었어요?",
        "함께 일하던 분들은 어떤 분들이었어요?",
        "가장 기억에 남는 옷은 무엇이었어요?"
      ],
      "evidenceSource": "lifeFact",
      "evidence": [ { "...": "미정" } ]
    }
  ]
}
```

- 카드는 12장이다. `position` 1~9가 선택용, 10~12가 보충용이며 `followUpQuestions`는 카드마다 3개다.
- `topic`: 기존 주제면 `topicId`, 새 주제면 `title`과 `description`. 새 주제는 BE가 `profile_topics`에 만든다. 한 묶음 안에서 주제는 겹치지 않는다.
- `evidenceSource`: `lifeFact`, `photo`, `none`. `none`이면 `evidence`는 빈 배열이다. `evidence` 항목 형식은 미정([미정 사항](#미정-사항) 5)
- `cardId`와 새 주제의 `topicId`는 백엔드가 부여한다.

**구현 메모**

- 요청 조립: `ageRange`는 `birth_date`로 계산한 십 단위 값(`80s`)이다. `profileFacts`는 네 항목, `lifeFacts`는 `life_facts`, `topics`는 `profile_topics`와 `topic_feedback`(`decided_at` 순)이다. 이름, 성별, 생년월일과 사진 설명은 넣지 않는다.
- 응답 검증: 카드 12장, `position` 1~12가 한 번씩, `followUpQuestions` 3개, 한 묶음 안 주제 중복 없음, 기존 `topicId`는 이 프로필의 주제, `evidenceSource`가 `none`이면 `evidence`는 빈 배열이다. 맞지 않으면 `INVALID_AI_RESPONSE`로 실패시킨다.
- 저장은 한 트랜잭션이다: 새 주제를 `profile_topics`에 만들고 `conversation_cards` 12장을 넣은 뒤 `card_sets`를 `completed`로 바꾸고 `generation_log`(`{"input": context, ...}`), `model`, `prompt_version`을 넣는다.
- `CardGenerationQueue`가 `running`이고 임대가 없는 작업을 임대해 `CardGenerationJob(set_id, profile_id, attempt_count)`을 넘긴다. 임대 만료(`WORKER_LEASE_EXPIRED`)도 대기열이 한다.
- 결과를 저장할 때 `status = 'completed'`와 함께 `lease_expires_at = NULL`로 바꾼다(CHECK `card_sets_lease_check`).
- **실패해도 `generation_log`가 있어야 한다**(CHECK). AI에 보낸 입력을 남기며 실패시키려면 `queue.fail(connection, job, error_code=..., generation_input=context)`을 부르고 처리 함수에서 정상 반환한다. 그냥 `AppError`를 올리면 `{"input": null}`로 기록된다.
- 실행 진입점은 `app/workers/speech_analysis.py`처럼 `run_worker_main`으로 만든다(예: `app/workers/card_generation.py`).

<br>

## 응답 객체

### CardSet

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "generationStatus": "completed",
  "usedBySessionId": null,
  "cards": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "position": 1,
      "topic": {
        "topicId": "00000000-0000-4000-8000-000000000452",
        "title": "재봉 일",
        "description": "젊은 시절 하시던 일과 그때의 하루를 여쭤보는 주제예요."
      },
      "cardTitle": "수선집 시절",
      "description": "수선집을 하시던 때의 손님과 옷 이야기를 나누는 카드예요.",
      "primaryQuestion": "어떤 옷을 주로 만드셨어요?",
      "followUpQuestions": [
        "일할 때 자주 쓰던 도구가 있었어요?",
        "함께 일하던 분들은 어떤 분들이었어요?",
        "가장 기억에 남는 옷은 무엇이었어요?"
      ],
      "evidenceSource": "lifeFact",
      "evidence": [ { "...": "미정" } ],
      "selected": false
    }
  ],
  "error": null,
  "createdAt": "2026-08-21T12:30:00+09:00"
}
```

- `generationStatus`: `running`, `completed`, `failed`
- `usedBySessionId`: 이 카드 묶음으로 만든 회차. 없으면 `null`
- `cards`: `completed`일 때 12장, 그 밖에는 `[]`
- `error`: `failed`일 때 `{ "errorCode": "..." }`, 그 밖에는 `null`

### VisitSession

```json
{
  "schemaVersion": 1,
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "setId": "00000000-0000-4000-8000-000000000401",
  "selectedCardIds": ["00000000-0000-4000-8000-000000000501"],
  "sessionStatus": "processing",
  "photoId": "00000000-0000-4000-8000-000000000221",
  "participantCount": 2,
  "startedAt": "2026-08-21T14:00:00+09:00",
  "analysisId": "00000000-0000-4000-8000-000000000601"
}
```

- `sessionStatus`: 5절의 상태 표
- `photoId`: 면회 사진이 없으면 `null`
- `participantCount`, `analysisId`: 6-2 접수 후 채운다. 가장 최근 작업의 값이다.

### VisitPhoto

```json
{
  "schemaVersion": 1,
  "photoId": "00000000-0000-4000-8000-000000000221",
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "imageUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/visit.jpg?...",
  "imageUrlExpiresAt": "2026-08-21T14:15:00+09:00",
  "createdAt": "2026-08-21T14:01:00+09:00"
}
```

## 미정 사항

아래 항목은 정해지기 전에 구현으로 먼저 정하지 않는다. 번호는 API 명세의 미정 사항 번호다.

| # | 항목 | 영향 | 확인할 곳 |
| --- | --- | --- | --- |
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 확인했는지 알 수 없음 | 4-1 호출 시점, 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 5 | 카드 근거(`evidence`) 항목 형식. 세부 정보 네 항목은 `fact_id`가 없음 | 8-2, CardSet | AI |
| 6 | 카드 생성 작업의 `model`, `prompt_version`. 생성(`running`) 시점부터 NOT NULL이라 8-2 응답 전에 값이 필요함 | 4-1, 8-2 | 스키마 작성자, AI |
