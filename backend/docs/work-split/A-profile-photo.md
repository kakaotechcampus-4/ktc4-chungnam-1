# 작업 A: 계정·프로필·사진

> 담당 파이프라인: **사진 분석 (8-4)**
>
> 정본은 [API 명세](../../../docs/architecture/api-spec.md)다. 이 문서는 분담을 위해 담당 부분을 옮기고 구현 메모를 더한 것이다. 계약을 바꿔야 하면 API 명세를 먼저 고치고 이 문서를 맞춘다.

## 시작하기

- 브랜치: 공통 기반 PR 1~4가 병합된 develop에서 `feature/backend-profile-photo`
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
| 1-4 | `POST` | `/auth/logout` | 완료 | 확인만 |
| 1-5 | `DELETE` | `/auth/me` | 계정 삭제와 탈퇴 이유 저장 구현됨(2026-11-09 기준). 앱은 아직 탈퇴 이유를 보내지 않음([FE README 로그아웃과 탈퇴](../../../app/README.md#로그아웃과-탈퇴)). 처음 작성 때는 탈퇴 이유 저장이 남아 있었다 | 바로 |
| 1-6 | `PATCH` | `/auth/me/consents` | 신규 | 바로 |
| 2-1 | `GET` | `/api/v1/profiles` | 신규 | 바로 |
| 2-2 | `POST` | `/api/v1/profiles` | 신규 | 바로 |
| 2-3 | `GET` | `/api/v1/profiles/{profileId}` | 신규 | 바로 |
| 2-4 | `PATCH` | `/api/v1/profiles/{profileId}` | 신규 | 바로 |
| 2-6 | `POST` | `/api/v1/profiles/{profileId}/life-facts` | 신규 | 바로 |
| 2-7 | `PATCH` | `/api/v1/life-facts/{factId}` | 신규 | 바로 |
| 2-8 | `DELETE` | `/api/v1/profiles/{profileId}` | 신규 | 바로 |
| 3-1 | `POST` | `/api/v1/profiles/{profileId}/photos` | 구현 완료 | 합성 자료로 검증. 11/8 운영 안정성 시험에서 공개 사진 43장을 운영 서버(S3 사진 버킷)에 올려 설명 86건까지 확인([기록](../stability-test-20261108.md)). 실제 사용자 사진 수집 전 사진 보관 동의 검증은 남음(후속 3) |
| 3-2 | `GET` | `/api/v1/profile-photos/{photoId}` | 구현 완료 | 메모리 저장소로 검증. 처음 작성 때 실제 S3 조회는 미검증이었다. 운영 S3에서 이 API를 따로 검사한 기록은 이 문서에 없다 |
| 3-3 | `PATCH` | `/api/v1/profile-photos/{photoId}/description` | 구현 완료(#205, 2026-11-09 기준) | 별도 승인 절차는 두지 않음. 처음 계획 때는 수정 API 미정이었다 |
| 3-4 | `DELETE` | `/api/v1/profile-photos/{photoId}` | 구현 완료(#240, 2026-11-09 기준) | 앱 화면은 아직 이 API를 부르지 않음 |
| 8-4 | `POST` | (내부) `/internal/v1/image-analyses` | 내부 HTTP API 대신 photo-worker가 `ai/photo_analysis`로 ML API를 부름(#257, 2026-11-09 기준) | AI 사진 분석 동의(`photoAnalysis`)한 계정의 사진만 분석. 11/8부터 운영. 사진 보관 동의는 미구현(후속 3). 처음 작성 때 상태는 신규(테스트 자료로 연결 진행, 대기열 `PhotoAnalysisQueue` 준비됨)였다 |

현재 구현 (2026-11-09 기준): 1-6, 2-1, 2-2, 2-3, 2-4, 2-6, 2-7, 2-8도 develop에 구현돼 있다(`app/api/routes/auth.py`, `app/api/routes/profiles.py`, `app/api/routes/life_facts.py`). 이 행들의 `신규`는 처음 작성 때의 상태다.

## 테이블 쓰기 소유권

다른 담당의 테이블은 읽기만 한다. 다른 담당 테이블에 써야 하면 그 담당이 제공하는 함수를 쓴다.

| 테이블 | 이 작업이 쓰는 것 | 다른 담당 |
| --- | --- | --- |
| `users`, `consent_records` | 1-6 동의 이력 추가, 1-5 계정 삭제 | |
| `withdrawal_feedback` | 1-5 탈퇴 이유 | |
| `session_revocations` | 1-4 로그아웃, 1-5 탈퇴의 세션 폐기 | 모든 인증 요청이 폐기 여부를 읽는다 |
| `profiles` | 2-2 생성, 2-4 세부 정보 저장과 수정, 2-8 삭제 | B는 4-1 카드 생성 요청에서 저장된 프로필을 읽는다. 2-8의 CASCADE로 B, C 테이블의 행도 지워진다 |
| `life_facts` | 2-6, 2-7 | C가 7-4에서 A의 `create_life_fact`로 만든다 |
| `photos` 중 `session_id IS NULL` | 3-1 생성, 8-4 분석 결과 | B가 면회 사진(`session_id` 있음)을 만들고 지운다 |

읽기만 하는 것: `card_sets`(`setupStatus` 계산)

## 다른 담당과 맞출 함수

- **제공** `create_life_fact(connection, *, profile_id, title, content, source_proposal_id=None)`: C의 7-4가 자기 트랜잭션 안에서 부른다. 함수 안에서 트랜잭션을 열지 않는다. C가 기다리지 않도록 가장 먼저 만들어 공유한다.
- **사용** `ImageStorageDep`과 `validate_image`: 3-1 업로드, 2-3과 3-2의 `imageUrl`, 8-4의 `downloadUrl`
- **사용** `PhotoAnalysisQueue`(`app/services/photo_analysis_jobs.py`)와 `Worker`: 8-4는 처리 함수와 실행 진입점만 만든다.

## 작업 순서

1. `create_life_fact`를 만들어 C에게 공유한다.
2. 2-2, 2-1, 2-3, 2-4, 2-8로 프로필 흐름을 만든다. 사진을 등록하지 않은 프로필은 `photos`가 빈 배열이며, 등록한 프로필은 3-1, 3-2에서 사용하는 사진 응답을 담는다.
3. 2-6, 2-7
4. 1-6, 1-5 탈퇴 이유
5. 3-1, 3-2와 2-3의 사진 URL은 구현했다. 합성 사진과 메모리 저장소로 검증했으며 실제 S3 연동은 추가 확인한다. 가입 시 계정별 동의 저장 방향은 [ADR-001](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따르고, 남은 검토 때문에 구현 전체를 보류하지 않는다.
6. 테스트 자료로 8-4 처리 함수와 worker 실행 진입점을 연결한다. 실제 사용자 사진을 받기 전에는 보관 및 분석 동의 검사, 철회와 삭제 처리를 검증한다. 2026-11-09 기준 worker 연결과 분석 동의 검사는 #257로 끝났고, 보관 동의 검사와 철회 뒤 처리는 남았다.

## 장별 공통 규칙

### 1. 계정

서버는 계정을 `users`, 동의 이력을 `consent_records`에 저장한다. 동의가 바뀔 때마다 이력 행을 추가하며, 현재 동의는 가장 최근 행(`current_consents`)이다.

녹음과 음성 처리 동의는 가입 때의 필수 동의로 함께 받는다. 면회 회차마다 동의를 따로 받지 않는다.

### 2. 프로필

피보호자의 이름, 성별, 생년월일은 서버의 `profiles`에 저장한다. 내부 API(8절) 요청에는 넣지 않고 BE가 생년월일로 계산한 연령대만 보낸다.

프로필 입력 상태(`setupStatus`)는 저장하지 않는다. 온보딩의 `마치기`에서 세부 정보를 2-4로 저장한 뒤 4-1로 첫 카드 생성을 요청한다. 카드 생성 작업(`card_sets`)이 하나라도 있으면 `completed`, 없으면 `inProgress`다. 프로필 저장과 카드 생성 요청은 별도 API이며, 이전 2-5 API는 사용하지 않는다.

### 3. 프로필 사진

사진은 S3에 서버 측 암호화로 저장한다. 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 모두 이미지 분석(8-4)을 거친다. 면회 사진(5-2)은 분석하지 않는다.

2026-10-05 PM 수정안: 위 자동 분석은 기존 API 제안이며 [ADR-001의 PR #92 개정안](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)은 사진 보관과 AI 분석 동의를 구분한다. 별도 분석 동의를 확인하지 않은 사진으로 분석 작업을 만들면 안 된다. 분석하지 않는 등록 사진의 상태, 동의 전달과 철회 경로는 FE, BE와 AI가 후속 계약에서 정한다. 아래 요청 필드와 응답 enum은 이번 문서 수정에서 바꾸지 않으며 실제 사용자 사진 처리에 적용하기 전 이 차이를 해소해야 한다.

현재 구현(2026-11-09 기준, develop `d9643466`): AI 분석 동의는 #257로 들어갔다. 가입 동의와 1-6의 선택 동의 `photoAnalysis`(기본 거부)를 계정 동의 이력에 저장하고, 사진 worker는 계정의 현재 동의가 켜진 프로필 사진만 가져간다. 동의하지 않은 계정의 사진은 `pending`으로 남아 분석하지 않으며, 나중에 동의하면 그때 분석한다. 사진 보관 동의는 따로 구현하지 않아 3-1, 5-2는 동의와 관계없이 사진을 받는다. 처리 흐름과 철회 시 처리는 [사진 분석 안내](../photo-analysis.md)를 따른다.

### 8. 내부 API (백엔드 → AI 서버)

백엔드 worker가 동기 호출한다. 앱은 호출하지 않는다. 원본 파일은 수명이 짧은 S3 Presigned GET URL로만 전달한다. 피보호자의 이름, 성별, 생년월일은 어떤 요청에도 넣지 않는다.

AI 서버 호출이 실패하면 해당 작업을 `failed`로 바꾸고 다음 `errorCode`를 남긴다: `AI_SERVER_TIMEOUT`, `AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `INVALID_AI_RESPONSE`. worker가 임대 시간 안에 작업을 끝내지 못하면 `WORKER_LEASE_EXPIRED`다. 자동으로 다시 시도하지 않는다.

8-2~8-4 응답의 `model`, `promptVersion`은 결과와 함께 저장한다.

## API 명세와 구현 메모

### 1-4. `POST /auth/logout` — 완료

요청에 사용한 세션을 폐기한다. 본문 없음.

응답 `204`

**구현 메모**

- 공통 기반 이전에 병합된 `feature/backend-account-management`에 구현돼 있다. 세션 폐기 기록은 #129에서 `session_revocations` 테이블로 옮겼다.

<br>

### 1-5. `DELETE /auth/me` — 수정

계정과 동의 이력, 프로필과 그 아래의 모든 기록을 삭제하고 요청에 사용한 세션을 폐기한다. 사진과 음성 원본은 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣어 지운다.

요청 (선택) — 탈퇴 이유. 고르지 않았으면 본문 없이 보낸다.

```json
{
  "reasons": ["cardsNotHelpful", "other"],
  "otherText": "합성 기타 사유"
}
```

- `reasons`: `conditionChanged`, `cardsNotHelpful`, `infrequentVisits`, `hardToUse`, `recordingBurden`, `other`. 탈퇴 화면의 이유 순서와 같다. 1개 이상이며 여러 개를 고를 수 있다.
- `otherText`: `other`를 고르면 필수, 고르지 않으면 `null`
- 탈퇴 이유는 계정과 연결하지 않고 `withdrawal_feedback`에 저장한다.

응답 `204`

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `INVALID_REQUEST` | `reasons`가 비었거나 `otherText` 조건이 맞지 않음 |

**구현 메모**

- 계정 삭제는 구현돼 있다. `DELETE FROM users`의 CASCADE로 계정 아래 기록이 지워지고, 사진과 음성의 객체 키는 trigger가 S3 삭제 대기열에 넣는다. 대기열을 처리해 S3 원본을 지우는 삭제 실행기는 #204로 들어왔다([storage-deletion](../storage-deletion.md)). 11/5 배포부터 운영 이미지에 있지만 저장소 밖 팀 운영 기록에 따르면 실제 삭제(`--apply`)는 11/6 PM 결정으로 보류했고 예약 실행 기록도 없으므로, 운영에서 S3 원본을 실제로 지웠다고 보지 않는다([저장소 대조 안내](../storage-audit.md)). 같은 기록에 따르면 운영 사진 버킷은 버전 관리 중이라 삭제 실행기가 사진 원본을 지우지 않고 건너뛰며(`VERSIONED_BUCKET_REQUIRES_REVIEW`), 처리 방식은 정하지 않았다. 처음 작성 때는 대기열을 처리해 S3 원본을 지우는 코드가 없었다(BE 후속).
- 탈퇴 이유: 본문이 있으면 계정 삭제와 같은 트랜잭션에서 `withdrawal_feedback(reasons, other_text)`에 넣는다. 계정 ID는 넣지 않는다. 처음 작성 때는 남은 일이었고 2026-11-09 기준 구현돼 있다(`app/services/accounts.py`).
- DB CHECK가 `reasons` 값, 1개 이상, `other`와 `other_text`의 짝을 막지만 요청 검증으로 먼저 422 `INVALID_REQUEST`를 낸다.

<br>

### 1-6. `PATCH /auth/me/consents` — 신규

선택 동의만 바꾼다. 보낸 항목만 변경한다.

요청

```json
{
  "serviceImprovement": true,
  "pushNotification": false
}
```

응답 `200` — [Account](#account)

- 직전 이력을 복사해 보낸 항목만 바꾼 새 이력 행을 추가한다. 약관 버전은 직전 이력의 값을 쓴다.
- 바꿀 수 있는 선택 동의는 `serviceImprovement`, `pushNotification`, `photoAnalysis`(AI 사진 분석, #257로 추가)다(2026-11-09 기준 `app/schemas/auth.py`).

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `REQUIRED_CONSENT_NOT_CHANGEABLE` | `serviceData` 또는 `sensitiveData`를 보냄 |
| 422 | `INVALID_REQUEST` | 본문이 비었음 |

**구현 메모**

- 최신 이력(`current_consents` 뷰)을 복사해 보낸 항목만 바꾼 새 행을 `consent_records`에 넣는다. `terms_version`은 최신 이력의 값이다.
- 응답은 `PostgresAccountRepository.get`으로 다시 읽어 만든다. `grantedAt` 규칙이 이미 그 안에 있다.

<br>

### 2-1. `GET /api/v1/profiles` — 신규

현재 계정의 프로필 목록이다. 로그인 직후 온보딩과 홈 중 어디로 갈지 정하고, 어르신 목록과 홈의 어르신 표시에 쓴다.

응답 `200`

```json
{
  "schemaVersion": 1,
  "profiles": [
    {
      "profileId": "00000000-0000-4000-8000-000000000101",
      "name": "김○○",
      "gender": "female",
      "setupStatus": "completed"
    }
  ]
}
```

- `setupStatus`: `inProgress`, `completed`
- 입력 중(`inProgress`)인 프로필도 담는다. 만든 순서(`created_at`)대로 반환한다.
- 목록이 비었으면 홈으로 간다. 입력을 마친(`completed`) 프로필이 생길 때까지 앱은 대화 카드, 면회와 리포트처럼 프로필이 필요한 기능을 막는다.
- `completed`인 프로필이 있으면 홈으로 간다. `inProgress`인 프로필만 있을 때 어디로 갈지는 미정([미정 사항](#미정-사항) 9)

**구현 메모**

- `setupStatus`는 `EXISTS (SELECT 1 FROM card_sets WHERE profile_id = ...)`로 계산한다.
- `name`, `gender`는 `profiles`에서 읽는다. 순서는 `ORDER BY created_at`이며 `idx_profiles_user(user_id, created_at)`를 탄다.

<br>

### 2-2. `POST /api/v1/profiles` — 신규

기본 정보 입력 단계를 마칠 때 호출한다.

요청

```json
{
  "name": "김○○",
  "gender": "female",
  "birthDate": "1943-03-12",
  "condition": {
    "stage": "mildCognitiveImpairment",
    "symptomNote": null
  }
}
```

- `name`: 50자 이하
- `gender`: `male`, `female`
- `condition.stage`: `mildCognitiveImpairment`, `mildDementia`, `unknown`
- `condition.symptomNote`: 선택

응답 `201` — [Profile](#profile), `setupStatus`는 `inProgress`

- 계정당 최대 3개다. 입력 중(`inProgress`)인 프로필도 센다. DB에 개수 제약이 없으므로 서버가 확인한다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 409 | `PROFILE_LIMIT_EXCEEDED` | 계정에 이미 프로필이 3개 있음 |

**구현 메모**

- 계정당 3개는 DB 제약이 없다. 같은 트랜잭션에서 `SELECT 1 FROM users WHERE user_id = %s FOR UPDATE`로 계정 행을 잠근 뒤 `profiles` 개수를 세고 넣는다. 동시 요청에도 3개를 넘지 않는다.
- `condition.stage`는 `condition_stage`, `condition.symptomNote`는 `symptom_note`다.

<br>

### 2-3. `GET /api/v1/profiles/{profileId}` — 신규

응답 `200` — [Profile](#profile)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` — 사진의 조회 URL을 만들지 못함 |

**구현 메모**

- `require_owned(connection, PROFILE, profile_id, account_id=...)`로 확인한다. `lifeFacts`는 `created_at` 순, `photos`는 `session_id IS NULL`인 행만 담는다. `imageUrl`과 `imageUrlExpiresAt`은 `storage.create_download(object_key=...)`로 만든다.

<br>

### 2-4. `PATCH /api/v1/profiles/{profileId}` — 신규

기본 정보와 세부 정보 네 항목을 수정한다. 보낸 필드만 변경한다.

요청

```json
{
  "condition": {
    "stage": "mildDementia",
    "symptomNote": "같은 이야기를 반복하실 때가 있어요"
  },
  "hobby": "노래 부르기를 좋아하셨어요."
}
```

- 받는 필드: `name`, `gender`, `birthDate`, `condition`, `occupation`, `hometown`, `hobby`, `family`
- 세부 정보 네 항목은 `null`을 보내면 지운다. 빈 문자열은 받지 않는다.
- `condition`을 보낼 때 `stage`는 항상 보낸다. `symptomNote`를 빼면 저장된 메모를 그대로 두고, `null`을 보낼 때만 지운다.

응답 `200` — [Profile](#profile)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

**구현 메모**

- 보낸 필드만 바꾼다(pydantic `model_fields_set`로 구분). 세부 정보 네 항목은 `null`이면 지운다. 빈 문자열은 422이며 DB CHECK(`length(btrim(x)) > 0`)도 막는다.
- `condition.symptomNote`도 `condition.model_fields_set`로 구분해, 뺐으면 `symptom_note`를 바꾸지 않는다.

<br>

### 2-6. `POST /api/v1/profiles/{profileId}/life-facts` — 신규

일대기에서 세부 정보 네 항목 밖의 생애 정보를 추가한다.

요청

```json
{
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요."
}
```

- `title`: 100자 이하. `title`과 `content`는 비울 수 없다.

응답 `201` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

<br>

### 2-7. `PATCH /api/v1/life-facts/{factId}` — 신규

생애 정보를 수정한다. 보낸 필드만 변경한다.

요청

```json
{ "content": "수선집에 오래 다닌 단골손님이 많았고 시장 상인들과도 친하셨어요." }
```

응답 `200` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |

**구현 메모**

- `require_owned(connection, LIFE_FACT, fact_id, ...)`로 확인한다.

<br>

### 2-8. `DELETE /api/v1/profiles/{profileId}` — 신규

어르신 목록에서 프로필 하나를 지운다. 그 프로필의 생애 정보, 사진, 주제와 대화 카드, 면회 기록(평가, 음성 분석 작업, 리포트, 변경 제안)을 함께 삭제한다. 계정과 다른 프로필은 남는다. 사진과 음성 원본은 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣어 지운다.

본문 없음.

응답 `204`

- 마지막 프로필도 지울 수 있다. 지운 뒤 2-1은 빈 목록을 돌려준다.
- 카드 생성이나 음성 분석이 처리 중인 프로필의 삭제는 미정([미정 사항](#미정-사항) 8)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

**구현 메모**

- `require_owned(connection, PROFILE, profile_id, account_id=...)`로 확인한 뒤 `DELETE FROM profiles`로 지운다. `ON DELETE CASCADE`로 아래 기록이 지워지고, 사진과 음성의 객체 키는 trigger가 S3 삭제 대기열에 넣는다. 1-5 계정 삭제와 같은 경로이며, 대기열을 처리하는 삭제 실행기는 #204로 들어왔지만 운영의 실제 삭제는 아직 보류 중이다(1-5 구현 메모).
- 카드와 주제가 있는 프로필을 지우는 테스트를 더한다. `conversation_cards`의 `profile_topics` 참조에는 `ON DELETE`가 없어 같은 삭제 안의 CASCADE 순서에 기대며, 1-5에도 아직 이 경우의 테스트가 없다.

<br>

### 3-1. `POST /api/v1/profiles/{profileId}/photos` — 신규

온보딩의 사진 첨부와 마이페이지의 갤러리 추가에서 호출한다.

요청 `multipart/form-data`

| 필드 | 값 |
| --- | --- |
| `image` | JPEG 또는 PNG. 서버 설정의 크기 상한(기본 20MB) 이하 |

응답 `201` — [ProfilePhoto](#profilephoto), `analysisStatus`는 `pending`

- 프로필당 최대 5장이다.
- 서버는 분석 작업(8-4)을 만든다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `PHOTO_LIMIT_EXCEEDED` |
| 413 | `IMAGE_TOO_LARGE` |
| 422 | `INVALID_IMAGE_FORMAT` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` |

**구현 메모**

- 프로필 사진(`session_id IS NULL`)이 이미 5장이면 409다. 동시 업로드로 5장을 넘지 않게 프로필 행을 `FOR UPDATE`로 잠그고 센다.
- 순서: `validate_image` → `photo_id` 생성 → `storage.object_key(photo_id=..., image=...)` → `storage.upload(...)` → `analysis_status = 'pending'`으로 행 저장. 행을 저장하지 못하면 `storage.delete`로 올린 객체를 지운다.
- 사진 worker(`app/workers/photo_analysis.py`, compose `photo-worker`)가 대기열에서 사진을 가져가 분석한다(#257). 계정이 AI 사진 분석에 동의했을 때만 가져가므로, 동의하지 않은 계정의 사진은 업로드 뒤에도 `pending`으로 남는다. 운영에서는 11/8 Deploy run 42385596940부터 photo-worker가 돈다. 처음 작성 때는 worker가 미연결이었다.
- S3 업로드 동안 프로필 행을 잠그지 않도록 올리기 전에 한 번 세어 일찍 거절하고, 행을 넣을 때 잠근 뒤 다시 센다. `storage.delete`도 실패하면 객체 키를 `storage_deletion_request_queue`에 직접 넣는다.
- 본문 상한(develop `d9643466`, #278, 운영 미배포): 미들웨어 `app/api/body_limits.py`가 3-1 본문을 `SAEROK_MAX_IMAGE_BYTES` + 1 MiB(기본 21 MiB)로 막아, `Content-Length`가 넘거나 받은 양이 넘으면 본문을 다 읽기 전에 413 `IMAGE_TOO_LARGE`로 거절한다. 본문을 읽기 전에 앱 버전(426)과 세션 토큰의 서명과 만료(401)도 확인하며, 세션 폐기, 계정과 소유권 확인은 지금처럼 본문을 받은 뒤 한다.
- 구현: [routes/profile_photos.py](../../app/api/routes/profile_photos.py), [services/profile_photos.py](../../app/services/profile_photos.py), 테스트 [test_profile_photos.py](../../tests/test_profile_photos.py)
- 실제 사용자 사진은 **사진 보관 동의를 확인한 경우에만 받는다**([ADR-001](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)). 분석 동의는 별도이며, 분석 동의가 없는 사진은 분석 대상으로 저장하지 않는다. 두 동의는 가입 시 받아 기존 계정 동의 이력에 저장한다. 필드와 분석하지 않는 사진의 상태는 후속 계약으로 맞추되, 테스트 자료를 사용하는 업로드와 분석 구현은 먼저 진행한다. 테스트 가정은 기록하고 실제 사용자 처리에 그대로 적용하지 않는다(후속 3).
- 현재 3-1 코드에는 사진 보관 동의 검사가 없고 모든 등록 사진을 `pending`으로 저장한다(2026-11-09 기준). 분석 대상 구분은 #257에서 worker가 AI 사진 분석 동의로 거르는 방식으로 들어갔다. 사진 보관 동의는 구현하지 않았으므로 실제 사용자 사진 수집 전 그 검사를 추가해야 한다.

<br>

### 3-2. `GET /api/v1/profile-photos/{photoId}` — 신규

`analysisStatus`가 `completed` 또는 `failed`가 될 때까지 폴링한다.

응답 `200` — [ProfilePhoto](#profilephoto)

- `failed`이면 온보딩을 계속한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_PHOTO_NOT_FOUND` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` — 사진의 조회 URL을 만들지 못함 |

**구현 메모**

- `require_owned(connection, PROFILE_PHOTO, photo_id, ...)`로 확인한다. 면회 사진은 이 API로 조회되지 않는다.

<br>

<a id="3-3-사진-설명-확인--미정"></a>

### 3-3. 앨범에서 사진 설명 수정 — 처음 작성 때 API 미정, 2026-11-09 기준 `PATCH /api/v1/profile-photos/{photoId}/description`로 구현

AI 사진 설명은 별도 승인 없이 카드 생성에 사용하고, 사용자가 원할 때 앨범에서 확인하거나 수정한다. 9월 23일 회의와 10월 6일 BE 논의의 기존 방향이다. 사진 등록과 카드 선택에 필수 확인 단계를 추가하지 않는다.

카드 입력에 사진 설명을 쓰는 것과 `life_facts`에 승인된 이야기를 저장하는 것은 다르다. 후자의 보호자 확인과 사진 분석 동의는 유지한다. 정본은 API 명세 3-3이다. 처음 작성 때 남은 것은 수정 API와 분석 중 수정의 처리였다. 새 승인 컬럼을 필수 조건으로 가정하지 않는다.

현재 구현(2026-11-09 기준, #205): 요청은 `{"description": "..."}`이고 200으로 `descriptionSource: "caregiver"`를 돌려준다. 보호자가 고친 값은 `photos.user_description`에 AI 원문과 따로 두며, 조회와 카드 입력은 보호자 설명을 우선하고 늦게 끝난 AI 결과가 덮지 않는다. AI 분석에 실패했거나 동의하지 않아 분석하지 않은 사진에도 설명을 쓸 수 있다. 설명이 바뀌면 아직 면회에 안 쓴 카드 묶음을 `needsRefresh`로 바꾸며, 그때 카드를 만드는 중이면 409 `CARD_GENERATION_IN_PROGRESS`로 저장하지 않는다. 구현은 [routes/profile_photos.py](../../app/api/routes/profile_photos.py), [services/profile_photos.py](../../app/services/profile_photos.py)에 있다. 사진 삭제(3-4, #240)도 같은 파일에 있으며, 지우면 S3 원본을 삭제 대기열에 넣고 아직 면회에 안 쓴 묶음을 `needsRefresh`로 바꾼다.

<br>

### 8-4. `POST /internal/v1/image-analyses` — 신규

프로필 사진만 요청한다. 면회 사진은 요청하지 않는다.

요청

```json
{
  "schemaVersion": 1,
  "photoId": "00000000-0000-4000-8000-000000000121",
  "imageSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/photo.jpg?...",
    "downloadUrlExpiresAt": "2026-09-25T15:10:00+09:00"
  }
}
```

응답 `200`

```json
{
  "schemaVersion": 1,
  "photoId": "00000000-0000-4000-8000-000000000121",
  "model": "synthetic-model",
  "promptVersion": "image-v1",
  "description": "한복을 입은 사람들이 잔치 자리에 모여 있는 사진이에요."
}
```

- `description`은 별도 승인 없이 카드 생성에 사용한다. 3-3은 앨범의 선택적 수정 API이며 카드 생성의 선행 승인 절차가 아니다.

**현재 구현 (2026-11-09 기준, #257)**

- 위 내부 HTTP API는 만들지 않았다. 사진 worker(`app/workers/photo_analysis.py`)가 `ai/photo_analysis`의 `analyze_photo`를 같은 프로세스에서 부르고, 이 함수가 짧은 S3 조회 주소로 ML API를 호출한다. 결과의 `description`과 BE 설정의 모델, `ai/photo_analysis`의 프롬프트 버전(`photo-1`)을 저장한다.
- `PhotoAnalysisQueue`는 계정의 현재 동의(`current_consents.photo_analysis`)가 켜진 `pending` 프로필 사진만 가져온다. 동의하지 않은 계정의 사진은 `pending`으로 남는다. 저장 직전에 동의를 다시 보고, 분석 중에 동의를 거뒀으면 결과를 버리고 `pending`으로 되돌린다.
- 분석 결과를 저장할 때 아직 면회에 안 쓴 카드 묶음을 다시 만들 대상으로 바꾸지 않는다(develop `d9643466`, #275, 운영 미배포). 분석이 끝난 사진은 다음 카드부터 쓴다. 운영(develop `9c2b8276`)은 아직 보호자 설명이 없는 사진의 분석이 끝나면 그 묶음에 `stale_at`을 찍어, 온보딩 `마치기`에서 받은 첫 묶음이 `needsRefresh`가 될 수 있다. 3-3 설명 수정과 3-4 삭제는 두 버전 모두 표시한다.
- 운영에서는 11/8 Deploy run 42385596940(develop `9e292149`)에서 photo-worker를 처음 띄웠고, 승인 배포 workflow가 api, card-worker, speech-worker와 함께 교체한다. 11/8 운영 안정성 시험에서 공개 사진 43장을 두 번씩 분석한 86건이 모두 완료됐다([안정성 시험 기록](../stability-test-20261108.md)). 실제 사용자 사진은 확인하지 않았다.
- 사진 보관 동의, 철회 뒤 이미 저장한 AI 설명의 처리는 정하지 않았다. 처리 흐름은 [사진 분석 안내](../photo-analysis.md)를 따른다. 아래는 처음 작성한 구현 메모다.

**구현 메모**

- **실제 사용자 사진은 분석 동의를 확인한 경우에만 분석한다.** 처음 작성 때 `PhotoAnalysisQueue`는 `pending`인 프로필 사진을 모두 가져왔다(지금은 위 현재 구현처럼 동의로 거른다). 테스트 자료만 있는 개발 환경에서 worker 연결을 먼저 검증하고, 실제 사용자 사진을 처리하기 전에는 유효한 분석 동의 조건, 분석하지 않는 사진의 상태와 철회 시 중단 처리를 구현하고 검증한다(후속 3).
- BE는 사진 사본을 만들지 않고 등록 사진의 Presigned GET URL만 넘긴다. AI 서버가 내려받은 파일이 분석용 임시 사본이며 처리 후 즉시, 늦어도 최초 생성부터 24시간 안에 지운다. 재시도로 기한이 늘지 않도록 작업마다 고정한 마감 시각을 8-4 요청에 넣는 방안을 AI와 정한다(지금 8-4 요청에는 해당 필드가 없다).
- `PhotoAnalysisQueue`가 `pending`인 프로필 사진을 `processing`으로 임대해 `PhotoAnalysisJob(photo_id, profile_id, s3_object_key, attempt_count)`을 넘긴다. 면회 사진은 가져오지 않는다. 실패 기록과 임대 만료(`WORKER_LEASE_EXPIRED`)도 대기열이 한다.
- 처리 함수: `storage.create_download(object_key=job.s3_object_key)`로 `downloadUrl`을 만들어 8-4를 호출하고, 응답의 `photoId`가 작업과 같은지 검증한 뒤 저장한다. 실패는 `AppError`(예: `AI_SERVER_TIMEOUT`, `INVALID_AI_RESPONSE`)로 올리면 대기열이 기록한다.
- 저장: `analysis_status = 'completed'`, `description`, `model`, `prompt_version`, `lease_expires_at = NULL`을 함께 쓴다(`WHERE photo_id = %s AND analysis_status = 'processing'`). CHECK가 세 값의 짝과 임대를 확인한다.
- 실행 진입점은 `app/workers/speech_analysis.py`처럼 `run_worker_main`으로 만든다(예: `app/workers/photo_analysis.py`).
- AI 서버 호출은 `app/clients/ai_server.py`의 음성 호출을 참고해 만든다.

<br>

## 응답 객체

### Account

```json
{
  "schemaVersion": 1,
  "accountId": "00000000-0000-4000-8000-000000000001",
  "authProvider": "google",
  "displayName": "보호자",
  "email": null,
  "consent": {
    "consentVersion": "2026-09-06",
    "serviceData": { "granted": true, "grantedAt": "2026-08-21T11:40:00+09:00" },
    "sensitiveData": { "granted": true, "grantedAt": "2026-08-21T11:40:00+09:00" },
    "serviceImprovement": { "granted": false, "grantedAt": null },
    "pushNotification": { "granted": true, "grantedAt": "2026-08-21T11:40:00+09:00" },
    "photoAnalysis": { "granted": false, "grantedAt": null }
  },
  "createdAt": "2026-08-21T11:40:00+09:00"
}
```

- `email`: 서버에 저장하지 않으므로 항상 `null`
- `consent`: 가장 최근 동의 이력이다. `consentVersion`은 그 이력의 약관 버전이다.
- `grantedAt`: 동의 중인 항목은 거부에서 동의로 바뀐 가장 최근 이력의 기록 시각, 처음부터 동의했으면 가입 시각이다. 거부 중이면 `null`

### Profile

```json
{
  "schemaVersion": 1,
  "profileId": "00000000-0000-4000-8000-000000000101",
  "setupStatus": "completed",
  "name": "김○○",
  "gender": "female",
  "birthDate": "1943-03-12",
  "condition": {
    "stage": "mildCognitiveImpairment",
    "symptomNote": null
  },
  "occupation": "재봉 일을 오래 하셨어요. 동인천에서 수선집을 하셨어요.",
  "hometown": null,
  "hobby": "노래 부르기를 좋아하셨어요.",
  "family": null,
  "lifeFacts": [ { "...": "LifeFact" } ],
  "photos": [ { "...": "ProfilePhoto" } ],
  "createdAt": "2026-08-21T12:00:00+09:00"
}
```

- `occupation`, `hometown`, `hobby`, `family`: 세부 정보 네 항목. 건너뛰었거나 2-4로 저장하기 전이면 `null`. 카드 생성 여부와 별개로 2-4에서 저장하거나 수정한다.

### LifeFact

```json
{
  "schemaVersion": 1,
  "factId": "00000000-0000-4000-8000-000000000111",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요.",
  "createdAt": "2026-08-21T12:10:00+09:00"
}
```

### ProfilePhoto

```json
{
  "schemaVersion": 1,
  "photoId": "00000000-0000-4000-8000-000000000121",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "imageUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/photo.jpg?...",
  "imageUrlExpiresAt": "2026-08-21T12:35:00+09:00",
  "analysisStatus": "completed",
  "description": "한복을 입은 사람들이 잔치 자리에 모여 있는 사진이에요.",
  "error": null,
  "createdAt": "2026-08-21T12:20:00+09:00"
}
```

- `analysisStatus`: `pending`, `processing`, `completed`, `failed`
- `description`: `completed`일 때만 채우고 그 밖에는 `null`
- `error`: `failed`일 때 `{ "errorCode": "..." }`, 그 밖에는 `null`

## 미정 사항

아래에는 미정 정책과 후속 구현 항목이 함께 있다. 미정 정책을 구현으로 확정하지 않되, 테스트 가정을 명시하고 기능 개발과 검증은 진행한다. 개인정보 검토가 남은 항목은 실제 사용자 자료 사용 전에 확인하며 기능 전체를 보류하지 않는다. 번호는 API 명세의 미정 사항 번호다.

| # | 항목 | 영향 | 확인할 곳 |
| --- | --- | --- | --- |
| 1 | 앨범에서 사진 설명을 수정하는 API와 분석 중 수정 처리. 설명의 별도 승인은 필요 없음. 2026-11-09 기준 수정 API는 #205로 구현됐고, 보호자 설명을 AI 원문과 따로 두어 늦은 분석 결과가 덮지 않는다(3-3) | 3-3, 카드 생성, 8-4 | FE, BE, AI. 카드 입력 사용과 생애 사실 승인을 구분 |
| 3 | 2026-10-14 PM 결정: 사진 보관과 AI 분석은 가입 시 별도 선택 동의로 받고 기존 계정 동의 이력에 저장. 테스트 자료로 개발을 진행하며, 동의 필드와 API, 분석하지 않는 사진의 상태와 철회 경로는 실제 사용자 사진 처리 전 구현 및 검증. 2026-11-09 기준 AI 분석 동의(`photoAnalysis`)와 미동의 사진의 `pending` 유지는 #257로 구현됐고, 사진 보관 동의와 철회 뒤 저장된 AI 설명 처리는 남음 | 3-1, 5-2, 8-4 | FE, BE, AI. 남은 개인정보 검토는 PM |
| 7 | 사진 삭제와 보관 동의 철회 동선 및 API 형태. DB 삭제 대기열 등록 이후 S3 실제 삭제와 결과 확인은 미구현. 2026-11-09 기준 사진 삭제 API(3-4, #240)와 삭제 실행기(#204)는 develop과 운영 이미지에 있지만, 앱의 삭제 화면, 보관 동의 철회 동선, 운영의 실제 S3 삭제와 결과 확인은 남음 | 3절 | FE, BE, PM |
| 8 | 카드 생성이나 음성 분석이 처리 중인 프로필 또는 계정을 지울 때의 처리. 삭제를 허용하고 worker가 사라진 행을 건너뛸지, 처리 중에는 409로 막을지 | 1-5, 2-8 | BE |
| 9 | 입력 중(`inProgress`)인 프로필만 있을 때 로그인 직후 그 프로필의 입력을 이어서 할지, 홈으로 갈지 | 2-1, 호출 순서 | FE, BE |
