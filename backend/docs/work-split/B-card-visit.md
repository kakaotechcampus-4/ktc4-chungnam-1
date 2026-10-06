# 작업 B: 카드·면회

> 담당 파이프라인: **카드 생성 (4-1 처리)**
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
| 2-5 | | 2-4 → 4-1로 대신함 | 삭제 | |
| 4-1 | `POST` | `/api/v1/profiles/{profileId}/card-generations` | 신규 | 바로 |
| 4-2 | `GET` | `/api/v1/profiles/{profileId}/card-generations/status` | 신규 | 바로 |
| 4-3 | `GET` | `/api/v1/profiles/{profileId}/card-generations/current` | 신규 | 바로 |
| 5-1 | `POST` | `/api/v1/visit-sessions` | 신규 | 바로 |
| 5-2 | `POST` | `/api/v1/visit-sessions/{sessionId}/photo` | 신규 | 사진 동의 설계 후(미정 3) |
| 5-3 | `PATCH` | `/api/v1/visit-sessions/{sessionId}/cards` | 신규 | 바로 |
| 8-2 | | 4-1 처리로 옮김 | 삭제 | |

## 테이블 쓰기 소유권

다른 담당의 테이블은 읽기만 한다. 다른 담당 테이블에 써야 하면 그 담당이 제공하는 함수를 쓴다.

| 테이블 | 이 작업이 쓰는 것 | 다른 담당 |
| --- | --- | --- |
| `card_sets` | 4-1 생성과 처리 결과, 5-1 회차 연결 | |
| `profile_topics` | 4-1 처리의 새 주제 | |
| `conversation_cards` | 4-1 처리에서 생성, 5-1과 5-3의 `selected` | C가 6-1에서 `review_reaction`, 8-3에서 `report_summary`를 쓴다 |
| `visit_sessions` | 5-1 생성 | C가 `evaluation_*`, `report_*` 컬럼을 쓴다 |
| `photos` 중 `session_id` 있음 | 5-2 면회 사진 | A가 프로필 사진과 8-4 결과를 쓴다 |

읽기만 하는 것: `profiles`, `life_facts`, `photos`, `profile_topics`, `topic_feedback`, `visit_sessions`(4-1 처리의 요청 조립)

## 다른 담당과 맞출 함수

- **제공** `start_card_generation(connection, profile_id)`: 4-1이 쓴다. 이미 `running`인 작업이 있으면 새로 만들지 않는다.
- **사용** C의 `load_visit_session(connection, session_id)`: `VisitSession` 응답과 `sessionStatus` 계산. 5-1과 5-3의 응답은 정의상 항상 `evaluationPending`이므로, C의 함수가 들어오기 전에는 `sessionStatus = evaluationPending`, `participantCount`와 `analysisId`는 `null`로 응답하고 들어온 뒤 바꾼다.
- **사용** `ImageStorageDep`과 `validate_image`(5-2)
- **사용** `CardGenerationQueue`(`app/services/card_generation_jobs.py`)와 `Worker`: 4-1 처리는 처리 함수와 실행 진입점만 만든다.

## 작업 순서

1. 미정 6은 2026-10-06에 정했다. `model`, `prompt_version`은 BE 설정값으로 `running`을 만들 때 넣는다.
2. 4-2, 4-3. 테스트에서는 카드 묶음을 SQL로 직접 넣는다.
3. 5-1, 5-3
4. 4-1 처리의 요청 조립, 결과 검증, 결과 저장
5. `start_card_generation`, 4-1
6. 4-1 처리 함수와 worker 실행 진입점, 사진 동의 설계 후 5-2

## 장별 공통 규칙

### 2. 프로필

피보호자의 이름, 성별, 생년월일은 서버의 `profiles`에 저장한다. 내부 API(8절) 요청에는 넣지 않고 BE가 생년월일로 계산한 연령대만 보낸다.

프로필 입력 상태(`setupStatus`)는 저장하지 않는다. 온보딩은 첫 카드 생성 작업(4-1)으로 끝나므로, 카드 생성 작업(`card_sets`)이 하나라도 있으면 `completed`, 없으면 `inProgress`다.

### 4. 대화 카드

카드 생성은 비동기 작업이며 `card_sets`에 저장한다. 프로필마다 진행 중(`running`)인 작업은 하나뿐이다.

홈의 `오늘의 대화카드 받기`는 4-2의 `status`로 정한다. 4-1~4-3 모두 계정은 Bearer 토큰, 프로필은 경로의 `profileId`로 정하고 요청 본문은 없다.

| 4-2 `status` | 최근 작업 | 버튼 | 누르면 |
| --- | --- | --- | --- |
| `none` | 없음, 또는 평가까지 끝난 회차에 쓰임 | 카드 받기 | 4-1 → 4-2 폴링 |
| `running` | 만드는 중 | 만드는 중 | — |
| `ready` | 다 만들었고 아직 안 씀 | 카드 받기 | 4-3 → 카드 고르기 |
| `inVisit` | 평가 전 회차(면회 중이거나 중간에 나감)에 쓰임 | 면회 이어서 하기 | 4-3 → 면회 화면 |
| `failed` | 실패 | 카드 받기 | 4-1 → 4-2 폴링 |

상태는 저장하지 않고 가장 최근 묶음의 `card_sets.status`, `session_id`와 그 회차의 평가 여부로 계산한다.

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

8-3, 8-4 응답의 `model`, `promptVersion`은 결과와 함께 저장한다. 카드 생성은 AI 서버를 거치지 않으며 4-1에 적는다(8-2 삭제).

## API 명세와 구현 메모

### 2-5. 프로필 입력 마치기 — 삭제

2026-10-06 삭제. 온보딩의 `마치기`에서 세부 정보 네 항목은 2-4로 저장하고, 4-1로 첫 카드 생성을 시작한다.

<br>

### 4-1. `POST /api/v1/profiles/{profileId}/card-generations` — 신규

카드를 만들어 달라고 요청한다. 작업만 만들고 바로 끝난다.

호출 시점

- 온보딩의 `마치기`(2-4 다음)
- 홈에서 `오늘의 대화카드 받기`를 눌렀을 때(4-2 `status`가 `none`이나 `failed`)

응답 `202`

```json
{ "schemaVersion": 1, "status": "running" }
```

- 이미 만드는 중이면 새로 만들지 않고 같은 응답을 준다.
- 평가 전 회차가 지금 묶음을 쓰는 중(`inVisit`)이면 409로 거절한다. 새 묶음이 생기면 면회 중인 카드를 4-3으로 받을 수 없게 되기 때문이다.
- 카드 생성 worker가 작업을 가져가 카드 12장과 새 주제를 저장한다(아래 처리). 앱은 4-2를 폴링한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `VISIT_IN_PROGRESS` (평가 전 회차가 있음) |
| 503 | `CARD_GENERATION_NOT_CONFIGURED` (LLM 키가 설정되지 않음) |

**구현 메모**

- 프로필 입력 상태는 따지지 않는다. 그 시점 DB에 있는 것으로 context를 만든다(아래 처리).
- `inVisit`인지는 4-2와 같은 계산으로 확인한다.
- `running`은 프로필당 하나다(부분 유일 인덱스 `uq_card_sets_running`). `INSERT ... ON CONFLICT (profile_id) WHERE status = 'running' DO NOTHING`으로 넣는다.

#### 4-1 카드 생성 처리

LLM은 ML API를 백엔드에서 이용. 

    context 조립(DB 읽기) → 생성 함수 호출(LLM, 트랜잭션 밖, 별도 스레드) → 결과 검증 → 저장(한 트랜잭션)

요청 (`app.schemas.card_generation.CardGenerationRequest`)

```json
{
  "schemaVersion": 1,
  "model": "gpt-5.6-luna",
  "promptVersion": 1,
  "context": {
    "ageRange": "80s",
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
        "content": "수선집에 오래 다닌 단골손님이 많았어요.",
        "createdAt": "2026-08-21T15:00:00+09:00",
        "source": "visit"
      }
    ],
    "photos": [
      {
        "photoId": "00000000-0000-4000-8000-000000000121",
        "description": "한복을 입은 사람들이 잔치 자리에 모여 있는 사진이에요."
      }
    ],
    "topics": [
      {
        "topicId": "00000000-0000-4000-8000-000000000451",
        "title": "노래 이야기",
        "description": "즐겨 부르시던 노래와 그 노래에 얽힌 기억을 여쭤보는 주제예요.",
        "evidence": [ { "profileField": "hobby" } ],
        "createdAt": "2026-08-14T12:30:00+09:00",
        "feedback": [
          { "action": "more", "decidedAt": "2026-08-21T15:00:00+09:00" }
        ]
      }
    ],
    "visits": [
      {
        "sessionId": "00000000-0000-4000-8000-000000000201",
        "startedAt": "2026-08-21T14:00:00+09:00",
        "setId": "00000000-0000-4000-8000-000000000400"
      }
    ],
    "pastCards": [
      {
        "cardId": "00000000-0000-4000-8000-000000000500",
        "setId": "00000000-0000-4000-8000-000000000400",
        "topicId": "00000000-0000-4000-8000-000000000451",
        "position": 1,
        "cardTitle": "즐겨 부르던 노래",
        "primaryQuestion": "젊으셨을 때 즐겨 부르던 노래가 있으셨어요?",
        "evidence": [ { "profileField": "hobby" } ],
        "selected": true,
        "reviewReaction": "positive"
      }
    ]
  }
}
```

- `model`, `promptVersion`: BE 설정값(`SAEROK_CARD_GENERATION_MODEL`, `SAEROK_CARD_GENERATION_PROMPT_VERSION`). 4-1에서 `card_sets`를 `running`으로 만들 때 저장하고 그 값을 그대로 넘긴다. `promptVersion`은 카드 생성 방식의 번호(정수)이며 카드 생성은 아는 번호만 받는다.
- `schemaVersion`: 요청과 결과 JSON 형식의 버전. 받는 쪽은 모르는 버전을 거절한다.
- `ageRange`: BE가 생년월일로 계산한 `{십 단위 나이}s` (예: `70s`, `80s`). 이름, 성별, 생년월일, 인지 상태, 증상 메모는 넣지 않는다.
- `lifeFacts.source`: 면회 제안을 승인해 생긴 이야기는 `visit`, 직접 넣은 이야기는 `caregiver`
- `photos`: 분석이 끝난 프로필 사진(`session_id`가 없음)의 설명(3-3)
- `topics`: 이 프로필의 기존 주제와 승인된 주제 피드백(`topic_feedback`)이다. 승인 전 제안은 넣지 않는다. 첫 생성에는 빈 배열이다.
- `visits`: 평가까지 끝난 회차(`evaluated_at` 있음)만, 시간순. 녹음을 시작했다가 그만둔 회차는 넣지 않는다.
- `pastCards`: 그 회차에 쓰인 카드 묶음의 카드. 직전에 보여 준 주제를 미루고, 지난번과 다른 장면을 고르는 데 쓴다. 회차에 쓰이지 않은 묶음은 넣지 않는다.
- 면회 평가 메모, 리포트 본문, 전사문은 넣지 않는다.
- BE는 요청의 `context`를 `card_sets.generation_log`의 `input`에 저장한다.

결과 (`CardGenerationResult`)

```json
{
  "schemaVersion": 1,
  "model": "gpt-5.6-luna",
  "promptVersion": 1,
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
      "evidenceSource": "profile",
      "evidence": [ { "profileField": "hobby" } ],
      "extra": { "...": "..." }
    },
    {
      "position": 2,
      "topic": {
        "title": "재봉 일",
        "description": "젊은 시절 하시던 일과 그때의 하루를 여쭤보는 주제예요.",
        "evidence": [ { "factId": "00000000-0000-4000-8000-000000000111" } ]
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
      "evidence": [ { "factId": "00000000-0000-4000-8000-000000000111" } ],
      "extra": { "...": "..." }
    }
  ],
  "log": { "...": "..." }
}
```

- 카드는 12장이다. `position` 1~9가 선택용, 10~12가 보충용이며 `followUpQuestions`는 카드마다 3개다.
- `topic`: 기존 주제면 `topicId`, 새 주제면 `title`, `description`, `evidence`. 새 주제는 BE가 `profile_topics`에 만든다. 한 묶음 안에서 주제는 겹치지 않는다.
- `evidenceSource`: `lifeFact`, `photo`, `profile`, `none`. `none`이면 `evidence`는 빈 배열이고 나머지는 하나 이상이다. 근거 항목은 `{"factId": ...}`, `{"photoId": ...}`, `{"profileField": "occupation" | "hometown" | "hobby" | "family"}` 중 하나다.
- `extra`, `log`: 생성 쪽이 자유롭게 채우는 객체다. BE는 내용을 보지 않고 `generation_log`에만 남긴다.
- `cardId`와 새 주제의 `topicId`는 백엔드가 부여한다.

검증과 저장

- BE는 저장 전에 확인한다: 12장, `position` 1~12가 한 번씩, 꼬리 질문 3개, 한 묶음 안 주제 중복 없음, 기존 `topicId`와 근거 ID가 context에 있음, 근거 항목 형식, `evidenceSource`와 `evidence`가 맞음. 맞지 않으면 `INVALID_GENERATION_RESULT`로 실패시킨다.
- 저장은 한 트랜잭션이다: 새 주제, 카드 12장, `card_sets`를 `completed`로(임대도 지움), `generation_log`(`input`, `log`, 카드별 `extra`).

실패

| `errorCode` | 뜻 |
| --- | --- |
| `INVALID_CONTEXT` | 입력 형식이 맞지 않거나 모르는 `promptVersion` |
| `NOT_ENOUGH_TOPICS` | 다시 찾아도 서로 다른 주제로 12장을 채우지 못함 |
| `TEXT_CHECK_FAILED` | 문안이 금지 표현 검사(최근 기억 확인, 의료 표현)에 두 번 걸림 |
| `LLM_UNAVAILABLE` | 엘리스 API 연결 실패, 시간 초과, 호출 한도 |
| `CARD_GENERATION_FAILED` | 그 밖의 실패 |
| `INVALID_GENERATION_RESULT` | 결과가 위 검증에 맞지 않음(BE가 판단) |

**구현 메모**

- 요청 조립: `ageRange`는 `birth_date`로 계산한 십 단위 값(`80s`)이다. `profileFacts`는 네 항목, `lifeFacts`는 `life_facts`, `photos`는 분석이 끝난 프로필 사진, `topics`는 `profile_topics`와 `topic_feedback`(`decided_at` 순), `visits`와 `pastCards`는 평가까지 끝난 회차와 그 회차에 쓰인 카드다. 이름, 성별, 생년월일, 인지 상태와 증상 메모는 넣지 않는다.
- 결과 검증: 카드 12장, `position` 1~12가 한 번씩, `followUpQuestions` 3개, 한 묶음 안 주제 중복 없음, 기존 `topicId`는 이 프로필의 주제, 근거 항목 형식과 ID가 context에 있음, `evidenceSource`가 `none`이면 `evidence`는 빈 배열이고 나머지는 하나 이상이다. 맞지 않으면 `INVALID_GENERATION_RESULT`로 실패시킨다.
- 저장은 한 트랜잭션이다: 새 주제를 `profile_topics`에 만들고 `conversation_cards` 12장을 넣은 뒤 `card_sets`를 `completed`로 바꾸고 `generation_log`(`{"input": context, ...}`)를 넣는다.
- `CardGenerationQueue`가 `running`이고 임대가 없는 작업을 임대해 `CardGenerationJob(set_id, profile_id, attempt_count)`을 넘긴다. 임대 만료(`WORKER_LEASE_EXPIRED`)도 대기열이 한다.
- 결과를 저장할 때 `status = 'completed'`와 함께 `lease_expires_at = NULL`로 바꾼다(CHECK `card_sets_lease_check`).
- **실패해도 `generation_log`가 있어야 한다**(CHECK). AI에 보낸 입력을 남기며 실패시키려면 `queue.fail(connection, job, error_code=..., generation_input=context)`을 부르고 처리 함수에서 정상 반환한다. 그냥 `AppError`를 올리면 `{"input": null}`로 기록된다.
- 실행 진입점은 `app/workers/speech_analysis.py`처럼 `run_worker_main`으로 만든다(예: `app/workers/card_generation.py`).

<br>

### 4-2. `GET /api/v1/profiles/{profileId}/card-generations/status` — 신규

홈 버튼 상태다. `running`이면 폴링한다.

응답 `200`

```json
{ "schemaVersion": 1, "status": "ready" }
```

- `status`: `none`, `running`, `ready`, `inVisit`, `failed`(4절 표). 프로필의 가장 최근 작업으로 정한다.
- 작업이 없어도 오류가 아니라 `none`이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

**구현 메모**

- `created_at DESC`의 첫 행을 회차와 `LEFT JOIN`해서 정한다. `completed`이고 `session_id`가 없으면 `ready`, 있고 그 회차의 `evaluated_at`이 없으면 `inVisit`, 있으면 `none`이다.

<br>

### 4-3. `GET /api/v1/profiles/{profileId}/card-generations/current` — 신규

지금 쓸 카드 묶음이다. 4-2가 `ready`(고르기 전)나 `inVisit`(면회 시작은 했고, 평가 전)일 때 그 묶음을 준다. 카드 고르기, 면회 중, 중간에 나갔다 돌아온 경우 모두 같은 카드를 받는다. 평가(6-1)를 마치면 더는 나오지 않는다.

응답 `200` — [CardSet](#cardset)

- `position` 1~9는 선택 화면용, 10~12는 면회 중 보충용이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND`, `CARD_GENERATION_NOT_FOUND`(쓸 묶음이 없음) |

**구현 메모**

- 4-2와 같은 행을 본다. `ready`나 `inVisit`가 아니면 404다. 카드는 `position` 순으로 담고 `topic`은 `profile_topics`와 조인한다. `evidenceSource`는 DB 값 `life_fact`를 API 값 `lifeFact`로 바꾼다.

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
- **면회 사진도 등록 사진이라 사진 보관 동의를 확인한 경우에만 받는다**([ADR-001 사진 보관 개정안](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)). 동의 저장 위치가 정해지기 전에는 구현을 시작하지 않는다(미정 3).
- 업로드 순서는 3-1과 같다: `validate_image` → `storage.object_key` → `storage.upload` → 행 저장(실패하면 `storage.delete`).
- 다시 올리면 기존 사진 행을 지우고 새로 넣는다(`uq_photos_session`). 지운 행의 키는 trigger가 S3 삭제 대기열에 넣는다.
- 면회 사진은 분석하지 않는다. `analysis_status`는 기본값 `pending`으로 남지만, A의 8-4 worker는 `session_id`가 있는 행을 가져가지 않는다.

<br>

### 5-3. `PATCH /api/v1/visit-sessions/{sessionId}/cards` — 신규

면회 중 꺼낸 보충 카드를 회차의 고른 카드에 더한다. 보충 카드 세 장(10~12번)은 4-3으로 언제든 볼 수 있다.

요청

```json
{ "cardIds": ["00000000-0000-4000-8000-000000000510"] }
```

- 같은 묶음의 `position` 10~12 안에서 고른다(1~3개). 이미 더한 카드는 무시하므로 같은 요청을 다시 보내도 결과가 같다.

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

### 8-2. 카드 생성 — 삭제

AI 서버를 거치지 않으므로 4-1의 처리 과정으로 옮겼다([4-1 카드 생성 처리](#4-1-카드-생성-처리)).

<br>

## 응답 객체

### CardSet

4-3의 응답이다. 고르기 전이거나 평가 전 회차에 쓰는 중인 카드 묶음이다.

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
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
      "evidence": [ { "factId": "00000000-0000-4000-8000-000000000111" } ],
      "selected": false
    }
  ]
}
```

- `setId`: 녹음을 시작할 때 5-1에 보낸다.
- `usedBySessionId`: 이 묶음을 쓰는 평가 전 회차. 고르기 전이면 `null`. 앱을 다시 켰을 때 이 값으로 5-2, 5-3을 부른다.
- `cards`: 12장. 회차에서 고른 카드와 더한 보충 카드는 `selected`가 `true`다.
- `evidenceSource`: `lifeFact`, `photo`, `profile`, `none`. `evidence` 항목은 `{"factId"}`, `{"photoId"}`, `{"profileField"}` 중 하나다(4-1 처리). 세부 정보 네 항목처럼 `fact_id`가 없는 근거는 `profile`과 `{"profileField": "occupation"}`으로 가리킨다.

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
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 확인했는지 알 수 없음 | 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 3 | PR #92의 PM 수정안은 사진 보관과 분석 동의를 구분함. 기존 자동 분석 제안에 동의 확인, 분석하지 않는 사진의 상태와 철회 경로를 반영해야 함 | 3-1, 8-4 | PM, FE, BE, AI |
