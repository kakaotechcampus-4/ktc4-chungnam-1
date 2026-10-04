# 작업 C: 평가·리포트

> 담당 파이프라인: **음성 → 리포트 (8-1 → 8-3)**
>
> 정본은 [API 명세](../../../docs/architecture/api-spec.md)다. 이 문서는 분담을 위해 담당 부분을 옮기고 구현 메모를 더한 것이다. 계약을 바꿔야 하면 API 명세를 먼저 고치고 이 문서를 맞춘다.

## 시작하기

- 브랜치: 공통 기반 PR 1~4가 병합된 develop에서 `feature/backend-evaluation-report`
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
| 5-4 | `GET` | `/api/v1/profiles/{profileId}/visit-sessions` | 신규 | 바로 |
| 6-1 | `POST` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 신규 | 바로 |
| 6-2 | `POST` | `/api/v1/visit-sessions/{sessionId}/speech-analyses` | 완료 | |
| 6-3 | `GET` | `/api/v1/speech-analyses/{analysisId}` | 완료 | |
| 6-4 | `GET` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 신규 | 바로 |
| 7-1 | `GET` | `/api/v1/profiles/{profileId}/reports` | 신규 | 바로 |
| 7-2 | `GET` | `/api/v1/visit-sessions/{sessionId}/report` | 신규 | 바로 |
| 7-3 | `GET` | `/api/v1/visit-sessions/{sessionId}/proposals` | 신규 | 바로 |
| 7-4 | `POST` | `/api/v1/visit-sessions/{sessionId}/proposals/review` | 신규 | A의 `create_life_fact` 후 |
| 8-1 | `POST` | (내부) `/internal/v1/speech-analyses` | 완료 | |
| 8-3 | `POST` | (내부) `/internal/v1/visit-reports` | 신규 | 바로. `ReportGenerator`를 구현해 음성 worker에 넣음 |

## 테이블 쓰기 소유권

다른 담당의 테이블은 읽기만 한다. 다른 담당 테이블에 써야 하면 그 담당이 제공하는 함수를 쓴다.

| 테이블 | 이 작업이 쓰는 것 | 다른 담당 |
| --- | --- | --- |
| `visit_sessions`의 `evaluation_*`, `evaluated_at` | 6-1 | B가 회차를 만든다 |
| `visit_sessions`의 `report_*` | 8-3 | |
| `conversation_cards.review_reaction` | 6-1 | B가 카드를 만들고 `selected`를 쓴다 |
| `conversation_cards.report_summary` | 8-3 | |
| `speech_analysis_jobs` | 6-2, 음성 worker | |
| `life_fact_proposals`, `topic_proposals` | 8-3 생성, 7-4 확정 | |
| `topic_feedback` | 7-4 | B가 8-2 요청에서 읽는다 |
| `life_facts` | 7-4에서 A의 `create_life_fact`로 | A |

읽기만 하는 것: `card_sets`, `conversation_cards`(선택 카드), `profiles`, `life_facts`, `photos`(면회 사진)

## 다른 담당과 맞출 함수

- **제공** `load_visit_session(connection, session_id)`: `VisitSession` 응답과 `sessionStatus` 계산. B의 5-1, 5-3과 C의 5-4가 쓴다. 가장 먼저 만들어 공유한다.
- **사용** A의 `create_life_fact(connection, *, profile_id, title, content, source_proposal_id=None)`: 7-4에서 쓴다.
- **사용** `ImageStorageDep`(7-2 면회 사진의 `imageUrl`)

`sessionStatus` 계산(5절 표를 DB 값으로 옮긴 것):

| 값 | 조건 |
| --- | --- |
| `completed` | `report_generated_at IS NOT NULL` |
| `evaluationPending` | `evaluated_at IS NULL` |
| `processing` | 실패하지 않은 작업이 `queued`, `transcribing`, `sttCompleted`, `generatingReport` |
| `failed` | 접수 후 실패한 작업(`status = 'failed' AND size_bytes IS NOT NULL`)이 있음 |
| `audioPending` | 그 밖. 업로드 단계의 실패는 작업을 지우므로 남지 않는다 |

`participantCount`와 `analysisId`는 가장 최근 작업(`created_at DESC`)의 값이다.

## 작업 순서

1. `load_visit_session`과 5-4를 만들어 B에게 공유한다.
2. 6-1, 6-4
3. 8-3 리포트 생성기: 요청 조립, AI 호출, 응답 검증, 저장
4. 7-1, 7-2, 7-3
5. A의 `create_life_fact`가 들어오면 7-4
6. 음성 worker 실행 진입점(`app/workers/speech_analysis.py`)의 `report_generator=None`을 구현한 생성기로 바꾼다.

## 장별 공통 규칙

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

### 6. 평가와 음성 제출

보호자 평가의 `리포트 만들기`에서 6-1과 6-2를 차례로 호출한다. 6-1이 성공하고 6-2가 실패하면 6-2만 다시 보낸다.

### 7. 리포트와 변경 제안

리포트는 회차에 저장하며 회차 ID로 조회한다. 변경 제안은 생애 정보 제안과 주제 제안 두 가지이며 회차마다 0개 이상이다. 리포트 확인 여부는 저장하지 않는다([미정 사항](#미정-사항) 2).

### 8. 내부 API (백엔드 → AI 서버)

백엔드 worker가 동기 호출한다. 앱은 호출하지 않는다. 원본 파일은 수명이 짧은 S3 Presigned GET URL로만 전달한다. 피보호자의 이름, 성별, 생년월일은 어떤 요청에도 넣지 않는다.

AI 서버 호출이 실패하면 해당 작업을 `failed`로 바꾸고 다음 `errorCode`를 남긴다: `AI_SERVER_TIMEOUT`, `AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `INVALID_AI_RESPONSE`. worker가 임대 시간 안에 작업을 끝내지 못하면 `WORKER_LEASE_EXPIRED`다. 자동으로 다시 시도하지 않는다.

8-2~8-4 응답의 `model`, `promptVersion`은 결과와 함께 저장한다.

## API 명세와 구현 메모

### 5-4. `GET /api/v1/profiles/{profileId}/visit-sessions` — 신규

최근 회차부터 반환한다. 홈의 리포트 상태 표시에 사용한다.

쿼리: `limit` (기본 20, 최대 100)

응답 `200`

```json
{
  "schemaVersion": 1,
  "sessions": [
    { "...": "VisitSession" }
  ]
}
```

홈은 첫 번째 회차로 상태를 표시한다.

| `sessionStatus` | 홈 표시 |
| --- | --- |
| `evaluationPending` | 평가 이어서 하기 |
| `audioPending` | 음성 다시 보내기 (6-2 재시도) |
| `processing` | 리포트를 만들고 있어요 |
| `completed` | 리포트 도착. 확인한 뒤의 표시는 미정([미정 사항](#미정-사항) 2) |
| `failed` | 리포트를 만들지 못했어요 |

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

**구현 메모**

- `require_owned(connection, PROFILE, ...)`로 확인한다. `started_at DESC` 순이며 `limit` 기본 20, 최대 100이다.

<br>

### 6-1. `POST /api/v1/visit-sessions/{sessionId}/evaluation` — 신규

요청

```json
{
  "conversationSatisfaction": 4,
  "careRecipientReaction": "pleased",
  "cardReviews": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "wasUsed": true,
      "caregiverReaction": "positive"
    },
    {
      "cardId": "00000000-0000-4000-8000-000000000502",
      "wasUsed": false,
      "caregiverReaction": null
    }
  ],
  "freeNote": null
}
```

- `conversationSatisfaction`: 1~5 정수
- `careRecipientReaction`: `pleased`, `calm`, `angry`, `lowEnergy`, `unknown`
- `cardReviews[].cardId`는 회차의 `selectedCardIds` 안에 있어야 한다.
- 카드를 쓰고 평가함: `wasUsed=true`, `caregiverReaction`은 `positive`, `neutral`, `negative` 중 하나
- 쓰지 않았다고 답함: `wasUsed=false`, `caregiverReaction=null`
- 답하지 않음: 그 카드를 `cardReviews`에 넣지 않는다.

응답 `201` — [CaregiverEvaluation](#caregiverevaluation)

- `evaluationPending` 상태에서만 받는다. 저장하면 회차는 `audioPending`이 된다.
- 카드 평가는 카드의 `review_reaction`에 저장한다. 쓰고 평가하면 `caregiverReaction` 값, 쓰지 않았으면 `notUsed`, 답하지 않았으면 `null`이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `EVALUATION_ALREADY_SUBMITTED` |
| 422 | `INVALID_CARD_REVIEW` |

**구현 메모**

- `require_owned(connection, VISIT_SESSION, ...)`로 확인한다. `evaluated_at`이 있으면 409 `EVALUATION_ALREADY_SUBMITTED`다.
- `cardReviews`의 `cardId`는 이 회차의 선택 카드(`card_sets.session_id`가 이 회차이고 `selected = true`)여야 한다. `wasUsed = true`면 `caregiverReaction` 필수, `false`면 `null`이다.
- 한 트랜잭션에서 `visit_sessions`의 `evaluation_satisfaction`, `evaluation_reaction`, `evaluation_note`, `evaluated_at = now()`을 쓰고(CHECK: `evaluated_at`이 있으면 만족도와 반응 필수), 평가한 카드의 `review_reaction`을 쓴다. 쓰고 평가하면 그 값, 쓰지 않았으면 `notUsed`, 답하지 않은 카드는 `null`로 둔다.

<br>

### 6-2. `POST /api/v1/visit-sessions/{sessionId}/speech-analyses` — 완료

면회 음성과 참여자 수를 제출한다.

요청 `multipart/form-data`

| 필드 | 값 |
| --- | --- |
| `audio` | WAV, PCM 16-bit, 16kHz, mono |
| `participantCount` | 녹음 종료 때 보호자가 확인한 1~8 |

응답 `202`

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "status": "queued"
}
```

변경 사항

- `audioPending` 상태의 회차만 받는다. 평가 전이면 `EVALUATION_REQUIRED`
- 업로드 단계에서 실패한 작업만 있으면 새 작업을 만든다.
- 접수된 작업이 처리 중이면 그 작업을 `202`로 반환한다.
- 접수 후 실패했거나 완료된 회차는 다시 받지 않는다.
- 앱은 `202`를 받으면 단말의 WAV 파일을 삭제한다.

| HTTP | `errorCode` |
| --- | --- |
| 403 | `SPEECH_PROCESSING_CONSENT_REQUIRED` |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `EVALUATION_REQUIRED` (신규), `ANALYSIS_SUBMISSION_IN_PROGRESS`, `ANALYSIS_ALREADY_FAILED`, `ANALYSIS_ALREADY_COMPLETED` |
| 413 | `AUDIO_TOO_LARGE` |
| 422 | `INVALID_AUDIO_FORMAT`, `INVALID_AUDIO` |
| 503 | `AUDIO_STORAGE_UNAVAILABLE`, `SPEECH_ANALYSIS_NOT_CONFIGURED` |

**구현 메모**

- 공통 기반에서 새 스키마와 비동기 연결 주입으로 옮겼다(평가 전 거절, 접수 후 실패 거절, 업로드 단계 실패 후 재제출). 라우트는 `SpeechSubmissionDep`으로 서비스를 받는다.

<br>

### 6-3. `GET /api/v1/speech-analyses/{analysisId}` — 완료

`completed` 또는 `failed`가 될 때까지 폴링한다.

응답 `200`

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "status": "transcribing",
  "errorCode": null
}
```

- `status`: `queued`, `transcribing`, `sttCompleted`, `generatingReport`, `completed`, `failed`
- `completed`이면 리포트와 변경 제안이 저장되어 7-2, 7-3으로 조회할 수 있다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `SPEECH_ANALYSIS_NOT_FOUND` |
| 409 | `ANALYSIS_SUBMISSION_IN_PROGRESS` (`retryable: true`) |

<br>

### 6-4. `GET /api/v1/visit-sessions/{sessionId}/evaluation` — 신규

리포트 화면에서 카드별 결과(평가함, 쓰지 않음, 답하지 않음)를 표시할 때 사용한다.

응답 `200` — [CaregiverEvaluation](#caregiverevaluation)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `EVALUATION_NOT_FOUND` |

**구현 메모**

- 평가 전이면 404 `EVALUATION_NOT_FOUND`다. `cardReviews`는 `review_reaction`으로 만든다: `notUsed`는 `wasUsed = false`, `null`은 넣지 않는다.

<br>

### 7-1. `GET /api/v1/profiles/{profileId}/reports` — 신규

마이페이지 리포트 기록이다. 리포트가 저장된 회차를 최근 면회부터 반환한다.

쿼리: `limit` (기본 20, 최대 100)

응답 `200`

```json
{
  "schemaVersion": 1,
  "reports": [
    {
      "sessionId": "00000000-0000-4000-8000-000000000201",
      "title": "재봉 일 이야기를 나눈 날",
      "visitDate": "2026-08-21",
      "mood": "good"
    }
  ]
}
```

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

**구현 메모**

- `report_generated_at IS NOT NULL`인 회차만 `started_at DESC` 순으로 담는다. `mood`는 저장하지 않고 만족도로 계산한다(1~2 `hard`, 3 `normal`, 4~5 `good`). `visitDate`는 `(started_at AT TIME ZONE 'Asia/Seoul')::date`다.

<br>

### 7-2. `GET /api/v1/visit-sessions/{sessionId}/report` — 신규

응답 `200` — [VisitReport](#visitreport)

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` | |
| 404 | `REPORT_NOT_FOUND` | 리포트 저장 전 |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` | 면회 사진의 조회 URL을 만들지 못함 |

**구현 메모**

- 리포트 저장 전이면 404 `REPORT_NOT_FOUND`다. `cardSummaries`는 `report_summary`가 있는 카드를 `card_title`과 함께 담는다. `photo`는 이 회차의 면회 사진이며 URL은 `storage.create_download(object_key=...)`로 만든다.

<br>

### 7-3. `GET /api/v1/visit-sessions/{sessionId}/proposals` — 신규

응답 `200` — [ChangeProposal](#changeproposal)

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` | |
| 404 | `REPORT_NOT_FOUND` | 리포트 저장 전 |

**구현 메모**

- `reviewStatus`: `pending`은 그대로다. `settled`는 승인 결과(`life_facts.source_proposal_id` 또는 `topic_feedback.proposal_id`)가 있으면 `accepted`, 없으면 `rejected`로 돌려준다.

<br>

### 7-4. `POST /api/v1/visit-sessions/{sessionId}/proposals/review` — 신규

변경 사항 확인 화면의 `이대로 반영하기` 또는 `반영하지 않고 마치기`에서 호출한다.

요청

```json
{
  "lifeFacts": [
    { "proposalId": "00000000-0000-4000-8000-000000000801", "reviewStatus": "accepted" }
  ],
  "topics": [
    { "proposalId": "00000000-0000-4000-8000-000000000802", "reviewStatus": "rejected" }
  ]
}
```

- 회차의 `pending` 제안을 모두 담는다. 화면에 남긴 항목은 `accepted`, X로 뺀 항목은 `rejected`
- `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- 제안이 없는 회차의 확인 처리는 미정([미정 사항](#미정-사항) 2)

응답 `200` — [ChangeProposal](#changeproposal)

서버 처리

- 모든 제안을 `settled`로 바꾼다.
- `accepted`인 생애 정보 제안은 생애 정보로 만든다. 생애 정보의 `source_proposal_id`가 그 제안이다.
- `accepted`인 주제 제안은 `topic_feedback`에 `suggestedAction`을 기록하고 다음 카드 생성(8-2)의 `topics`에 반영한다. 보호자가 다른 행동을 고를 수 있는지는 미정([미정 사항](#미정-사항) 4)
- `rejected` 항목은 반영하지 않는다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `REPORT_NOT_FOUND` | |
| 409 | `PROPOSAL_ALREADY_REVIEWED` | 이미 `settled`인 제안이 있음 |
| 422 | `INVALID_PROPOSAL_REVIEW` | `pending` 제안이 빠졌거나 다른 회차의 제안 |

**구현 메모**

- 한 트랜잭션에서 모든 제안을 `settled`로 바꾼 뒤, `accepted`인 생애 정보 제안은 `create_life_fact(..., source_proposal_id=제안 ID)`로, `accepted`인 주제 제안은 `topic_feedback(profile_id, topic_id, proposal_id, action = suggested_action)`으로 넣는다.
- 다음 카드 생성(4-1)은 앱이 호출한다.

<br>

### 8-1. `POST /internal/v1/speech-analyses` — 완료

요청

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "language": "ko",
  "speakerCount": 2,
  "audioSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/audio.wav?...",
    "downloadUrlExpiresAt": "2026-09-25T15:10:00+09:00",
    "sizeBytes": 123456,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "dataExpiresAt": "2026-09-26T14:00:00+09:00"
}
```

응답 `200`

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "language": "ko",
  "durationMs": 15200,
  "text": "합성 전사 결과",
  "segments": [
    {
      "startMs": 0,
      "endMs": 3200,
      "speakerLabel": "SPEAKER_00",
      "text": "합성 발화 구간",
      "words": [
        { "startMs": 0, "endMs": 800, "text": "합성", "probability": 0.93 }
      ]
    }
  ]
}
```

worker 처리 순서: 8-1 → S3 원본 삭제 → 전사문 임시 저장(`sttCompleted`) → 8-3 → 리포트와 변경 제안 저장, 전사문 삭제 → 작업 `completed`

- 전사문은 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업(`speech_analysis_jobs.transcript`)에 임시 저장한다. 리포트를 저장하면 지우고, 늦어도 STT 완료 후 24시간(`transcript_expires_at`)이 지나면 지운다. 기한까지 리포트를 저장하지 못하면 작업은 `failed`이고 `errorCode`는 `TRANSCRIPT_EXPIRED`다.
- 전사문은 화면에 표시하지 않고 8-3 요청에만 사용한다.

**구현 메모**

- 구현돼 있다. worker는 공통 골격(`SpeechAnalysisQueue`, `SpeechAnalysisProcessor`) 위에서 돌며 STT 결과의 구간만 `speech_analysis_jobs.transcript`에 저장한다(24시간). 기한까지 리포트를 저장하지 못하면 `TRANSCRIPT_EXPIRED`, 임대 시간 안에 끝나지 않으면 `WORKER_LEASE_EXPIRED`로 실패한다.

<br>

### 8-3. `POST /internal/v1/visit-reports` — 신규

요청

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "visitDate": "2026-08-21",
  "evaluation": {
    "conversationSatisfaction": 4,
    "careRecipientReaction": "pleased",
    "freeNote": null
  },
  "cards": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "cardTitle": "수선집 시절",
      "topic": {
        "topicId": "00000000-0000-4000-8000-000000000452",
        "title": "재봉 일"
      },
      "reaction": "positive"
    }
  ],
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
  "transcript": {
    "durationMs": 15200,
    "segments": [
      { "startMs": 0, "endMs": 3200, "speakerLabel": "SPEAKER_00", "text": "합성 발화 구간" }
    ]
  }
}
```

- `cards`는 회차에서 `selected`인 카드다.
- `reaction`: `positive`, `neutral`, `negative`, `notUsed`. 답하지 않은 카드는 `null`

응답 `200`

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "model": "synthetic-model",
  "promptVersion": "report-v1",
  "title": "재봉 일 이야기를 나눈 날",
  "body": "오늘은 재봉 일을 하시던 시절 이야기를 나눴어요.",
  "cardSummaries": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "summary": "한복을 주로 만드셨고 함께 일하던 분들 이야기를 하셨어요."
    }
  ],
  "lifeFactProposals": [
    {
      "title": "한복",
      "content": "한복을 주로 만드셨어요.",
      "reason": "이번 면회에서 확인되었어요."
    }
  ],
  "topicProposals": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "suggestedAction": "more",
      "reason": "재봉 일 이야기에 반응이 좋으셨어요."
    }
  ]
}
```

- `cardSummaries`는 `reaction`이 `positive`, `neutral`, `negative`인 카드만 담는다.
- `topicProposals`는 요청의 `cards` 안에서 카드당 최대 1개다. `suggestedAction`: `more`, `less`, `exclude`
- 카드를 쓰지 않았거나 답하지 않았다는 사실만으로 `less`, `exclude`를 제안하지 않는다(2026-09-19 PM 결정).
- `mood`는 AI가 만들지 않는다. 백엔드가 `conversationSatisfaction`으로 계산한다(1~2 `hard`, 3 `normal`, 4~5 `good`).
- `proposalId`는 백엔드가 부여한다.

**구현 메모**

- `ReportGenerator`(`app/services/speech_analysis_pipeline.py`)를 구현해 `app/workers/speech_analysis.py`의 `report_generator=None` 자리에 넣는다. 형태는 `async def generate(connection, *, session_id, speech)`다. worker는 `sttCompleted` 뒤 `generatingReport`로 바꾸고 생성기를 부르며, 생성기가 끝나면 작업을 `completed`로 바꾸고 전사문을 지운다.
- 생성기 안에서 8-3 호출은 트랜잭션 밖에서 하고, 리포트와 변경 제안 저장만 `async with connection.transaction():`으로 묶는다. 실패는 `AppError`로 올리면 대기열이 작업을 실패로 기록한다.
- 요청 조립: `visitDate`, `evaluation`(만족도, 반응, 메모), `cards`(선택 카드의 `cardId`, `cardTitle`, `topic`, `reaction = review_reaction`), `profileFacts`, `lifeFacts`, `transcript`. 이름, 성별, 생년월일은 넣지 않는다.
- 응답 검증: `cardSummaries`는 `positive`, `neutral`, `negative` 카드만, `topicProposals`는 요청 `cards` 안에서 카드당 최대 1개다. 미사용과 미응답만으로 `less`, `exclude`를 제안하면 안 된다는 PM 결정을 어긴 응답을 실패로 볼지 그 제안만 뺄지는 AI 담당과 정한다.
- 저장은 한 트랜잭션이다: `visit_sessions`의 `report_title`, `report_body`, `report_model`, `report_prompt_version`, `report_generated_at`(CHECK: 다섯 값은 함께, `evaluated_at` 필요), `conversation_cards.report_summary`(CHECK: 평가한 카드만), `life_fact_proposals`, `topic_proposals`(`topic_id`는 그 카드의 주제)를 넣는다. 작업의 `completed`와 전사문 삭제는 worker의 `mark_completed`가 한다.

<br>

## 응답 객체

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

### CaregiverEvaluation

```json
{
  "schemaVersion": 1,
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "conversationSatisfaction": 4,
  "careRecipientReaction": "pleased",
  "cardReviews": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "wasUsed": true,
      "caregiverReaction": "positive"
    }
  ],
  "freeNote": null,
  "evaluatedAt": "2026-08-21T14:25:00+09:00"
}
```

- `cardReviews`: 답한 카드만 담는다. 답하지 않은 카드는 넣지 않는다.

### VisitReport

```json
{
  "schemaVersion": 1,
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "title": "재봉 일 이야기를 나눈 날",
  "body": "오늘은 재봉 일을 하시던 시절 이야기를 나눴어요.",
  "visitDate": "2026-08-21",
  "mood": "good",
  "photo": {
    "photoId": "00000000-0000-4000-8000-000000000221",
    "imageUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/visit.jpg?...",
    "imageUrlExpiresAt": "2026-08-21T15:00:00+09:00"
  },
  "cardSummaries": [
    {
      "cardId": "00000000-0000-4000-8000-000000000501",
      "cardTitle": "수선집 시절",
      "summary": "한복을 주로 만드셨고 함께 일하던 분들 이야기를 하셨어요."
    }
  ],
  "generatedAt": "2026-08-21T14:26:00+09:00"
}
```

- `visitDate`: 회차 `startedAt`의 한국 시간 날짜
- `mood`: `hard`, `normal`, `good`. 백엔드가 만족도로 계산한다.
- `photo`: 면회 사진이 없으면 `null`

### ChangeProposal

```json
{
  "schemaVersion": 1,
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "lifeFactProposals": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000801",
      "title": "한복",
      "content": "한복을 주로 만드셨어요.",
      "reason": "이번 면회에서 확인되었어요.",
      "reviewStatus": "pending"
    }
  ],
  "topicProposals": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000802",
      "cardId": "00000000-0000-4000-8000-000000000501",
      "topic": {
        "topicId": "00000000-0000-4000-8000-000000000452",
        "title": "재봉 일"
      },
      "suggestedAction": "more",
      "reason": "재봉 일 이야기에 반응이 좋으셨어요.",
      "reviewStatus": "pending"
    }
  ]
}
```

- `suggestedAction`: `more`, `less`, `exclude`
- `reviewStatus`: `pending`, `accepted`, `rejected`. DB에는 `pending`과 `settled`만 저장하므로, `settled`인 제안은 승인 결과(생애 정보 또는 주제 피드백)가 있으면 `accepted`, 없으면 `rejected`로 반환한다.

## 미정 사항

아래 항목은 정해지기 전에 구현으로 먼저 정하지 않는다. 번호는 API 명세의 미정 사항 번호다.

| # | 항목 | 영향 | 확인할 곳 |
| --- | --- | --- | --- |
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 확인했는지 알 수 없음 | 4-1 호출 시점, 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 4 | 주제 제안 승인 시 보호자가 제안과 다른 행동을 고를 수 있는지. `topic_feedback.action`과 `topic_proposals.suggested_action`이 별도 컬럼 | 7-4 | 스키마 작성자 |
