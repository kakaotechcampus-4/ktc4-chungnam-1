# 새록 API 명세

앱과 백엔드 사이의 공개 API, 백엔드와 AI 서버 사이의 내부 API를 정리한다. 저장 구조는 [init.sql](../../backend/database/init.sql)의 DB 스키마를 따른다. 예시 값은 모두 합성 데이터다.

2026-10-12 문서 정리: 사진 설명은 별도 승인 없이 카드 생성에 쓰고 앨범에서 선택적으로 수정한다(3-3). 카드 API와 요청 및 결과 형식은 [PR #99](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/99)에 맞췄다. 프로필 저장(2-4) 후 카드 생성을 요청(4-1)하고, BE의 4-1 처리에서 생성 함수를 호출한다. 이전 2-5와 내부 8-2는 삭제했으며, 실제 AI 생성 함수 연결은 후속 작업이다.

STT 외 생성 기능은 ML API를 활용하는 방향이다. 8-3과 8-4의 내부 HTTP 형식을 실제 GPU 실행 위치와 동일시하지 않는다. 특히 리포트의 함수 호출 전환은 [PR #110](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/110)에서 #106 담당자와 검토 중이다.

## 공통

| 항목 | 기준 |
| --- | --- |
| 인증 | `/auth/google`, `/auth/consent`를 제외한 모든 공개 API는 `Authorization: Bearer <accessToken>` |
| 본문 | JSON, 필드는 `lowerCamelCase`. 파일 업로드만 `multipart/form-data` |
| 버전 | 응답 최상위에 `schemaVersion: 1` |
| ID | UUID 문자열 |
| 시간 | 시간대를 포함한 ISO 8601. 날짜만 필요한 값은 `YYYY-MM-DD` |
| 없는 값 | `null`. 빈 목록은 `[]` |
| 권한 | 다른 계정의 자원은 존재 여부를 드러내지 않고 `404` |
| 이미지 조회 | 응답의 `imageUrl`은 수명이 짧은 S3 Presigned GET URL이다. `imageUrlExpiresAt`이 지나면 해당 자원을 다시 조회한다 |

오류는 모두 다음 형식이다.

```json
{
  "schemaVersion": 1,
  "errorCode": "VISIT_SESSION_NOT_FOUND",
  "message": "면회 기록을 찾을 수 없습니다.",
  "requestId": "req_01",
  "retryable": false
}
```

모든 인증 API에 공통인 오류는 엔드포인트별 표에서 생략한다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 401 | `UNAUTHENTICATED` | 세션이 없거나 유효하지 않음. 폐기한 세션 포함 |
| 401 | `SESSION_EXPIRED` | 세션 만료 |
| 404 | `ACCOUNT_NOT_FOUND` | 세션의 계정이 없음 |
| 422 | `INVALID_REQUEST` | 요청 형식 오류 |
| 500 | `INTERNAL_SERVER_ERROR` | 서버 내부 오류 |
| 503 | `DATABASE_NOT_CONFIGURED` | 서버의 DB 연결 설정이 없음 |

<br>

## API 목록

상태: `완료` 구현됨, `미병합` 구현됐으나 develop에 병합 전, `수정` 기존 API 변경, `신규` 새로 구현, `미정` 결정 전

6-2, 6-3, 8-1은 공통 기반 작업에서 새 스키마와 worker 공통 골격에 맞췄다.

| # | 화면 | 메서드 | 경로 | 상태 |
| --- | --- | --- | --- | --- |
| 1-1 | 로그인 | `POST` | `/auth/google` | 완료 |
| 1-2 | 가입 동의 | `POST` | `/auth/consent` | 완료 |
| 1-3 | 앱 시작 | `GET` | `/auth/me` | 완료 |
| 1-4 | 프로필 설정 | `POST` | `/auth/logout` | 완료 |
| 1-5 | 회원 탈퇴 | `DELETE` | `/auth/me` | 수정 |
| 1-6 | 프로필 설정 | `PATCH` | `/auth/me/consents` | 신규 |
| 2-1 | 로그인 직후, 어르신 목록 | `GET` | `/api/v1/profiles` | 신규 |
| 2-2 | 기본 정보 입력 | `POST` | `/api/v1/profiles` | 신규 |
| 2-3 | 마이페이지, 일대기 | `GET` | `/api/v1/profiles/{profileId}` | 신규 |
| 2-4 | 기본 정보, 세부 정보 수정 | `PATCH` | `/api/v1/profiles/{profileId}` | 신규 |
| 2-5 | 프로필 입력 마치기 | | 2-4 → 4-1로 대신함 | 삭제 |
| 2-6 | 생애 정보 추가 | `POST` | `/api/v1/profiles/{profileId}/life-facts` | 신규 |
| 2-7 | 생애 정보 수정 | `PATCH` | `/api/v1/life-facts/{factId}` | 신규 |
| 2-8 | 어르신 목록 | `DELETE` | `/api/v1/profiles/{profileId}` | 신규 |
| 2-9 | 일대기 이야기 삭제 | `DELETE` | `/api/v1/life-facts/{factId}` | 신규 |
| 3-1 | 사진 첨부, 갤러리 추가 | `POST` | `/api/v1/profiles/{profileId}/photos` | 신규 |
| 3-2 | 사진 분석 대기 | `GET` | `/api/v1/profile-photos/{photoId}` | 신규 |
| 3-3 | 앨범에서 사진 설명 수정 | | | 수정 API 미정, 필수 승인 없음 |
| 4-1 | 홈 | `POST` | `/api/v1/profiles/{profileId}/card-generations` | 신규 |
| 4-2 | 홈 | `GET` | `/api/v1/profiles/{profileId}/card-generations/status` | 신규 |
| 4-3 | 대화 카드 선택 | `GET` | `/api/v1/profiles/{profileId}/card-generations/current` | 신규 |
| 5-1 | 녹음 시작 | `POST` | `/api/v1/visit-sessions` | 신규 |
| 5-2 | 면회 사진 | `POST` | `/api/v1/visit-sessions/{sessionId}/photo` | 신규 |
| 5-3 | 대화 카드 보충 | `PATCH` | `/api/v1/visit-sessions/{sessionId}/cards` | 신규 |
| 5-4 | 홈 | `GET` | `/api/v1/profiles/{profileId}/visit-sessions` | 신규 |
| 6-1 | 보호자 평가 | `POST` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 신규 |
| 6-2 | 보호자 평가 | `POST` | `/api/v1/visit-sessions/{sessionId}/speech-analyses` | 완료 |
| 6-3 | 홈 | `GET` | `/api/v1/speech-analyses/{analysisId}` | 완료 |
| 6-4 | 리포트 | `GET` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 신규 |
| 7-1 | 리포트 기록 | `GET` | `/api/v1/profiles/{profileId}/reports` | 신규 |
| 7-2 | 리포트 | `GET` | `/api/v1/visit-sessions/{sessionId}/report` | 신규 |
| 7-3 | 변경 사항 확인 | `GET` | `/api/v1/visit-sessions/{sessionId}/proposals` | 신규 |
| 7-4 | 변경 사항 확인 | `POST` | `/api/v1/visit-sessions/{sessionId}/proposals/review` | 신규 |
| 8-1 | (내부) STT | `POST` | `/internal/v1/speech-analyses` | 완료 |
| 8-2 | (내부) 카드 생성 | | 4-1 처리로 옮김 | 삭제 |
| 8-3 | (내부) 리포트 생성 | `POST` | `/internal/v1/visit-reports` | 신규 |
| 8-4 | (내부) 이미지 분석 | `POST` | `/internal/v1/image-analyses` | 신규 |

<br>

## 호출 순서

    [로그인]      1-1 → (consentRequired) 1-2 → [온보딩]
                  1-1 (authenticated) → 2-1 → 빈 목록이거나 completed가 있으면 홈, inProgress만 있으면 미정(9)
    [온보딩]      2-2 → (사진 첨부 시 3-1 → 3-2 폴링) → 2-4 (세부 정보) → 4-1 (카드 생성 시작)
    [홈]          4-2, 5-4. 카드 받기: 4-1 → 4-2 폴링, ready 또는 inVisit이면 4-3(4절 표)
    [어르신 목록] 2-1, 2-8 (삭제). 빈 슬롯 → [온보딩]
    [카드 선택]   4-3 → 면회 사진 촬영(단말)
    [면회]        5-1 (녹음 시작) → 5-2 (사진을 찍었으면) → 5-3 (필요 시) → 녹음 종료(단말). 다시 열면 4-3(`inVisit`)
    [평가]        6-1 → 6-2 → 6-3 폴링
    [리포트]      7-2, 6-4 → 7-3 → 7-4
    [일대기]      2-3, 2-6, 2-7, 2-9
    [마이페이지]  2-3, 2-4, 3-1, 3-2, 1-6, 7-1, 1-4, 1-5

<br>

---

## 1. 계정

2026-10-14 PM 결정: 가입 화면에는 기존 필수 2개와 선택 2개에 사진 서버 보관과 AI 분석의 선택 동의를 각각 추가한다. 계정별 기존 동의 이력에 저장하며, 유효한 동의는 기능 사용 때 다시 묻지 않는다. 미동의, 철회 또는 기록 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 이용할 수 있다. 아래 네 항목의 요청 및 응답 예시는 현재 계약이며 새 두 항목은 아직 구현되지 않았다. 필드명과 가입, 조회, 변경 API 확장은 FE 및 BE가 맞춘다. 정책 정본은 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)이다.

서버는 계정을 `users`, 동의 이력을 `consent_records`에 저장한다. 동의가 바뀔 때마다 이력 행을 추가하며, 현재 동의는 가장 최근 행(`current_consents`)이다.

녹음과 음성 처리 동의는 가입 때의 필수 동의로 함께 받는다. 면회 회차마다 동의를 따로 받지 않는다.

위 설명은 계정의 `serviceData`, `sensitiveData`와 매회 녹음 체크박스를 구분한 것이다. 보호자 가입 동의만으로 피보호자 본인의 동의나 대리 권한까지 확인됐다는 뜻은 아니다. 피보호자 최초 등록 전 확인 시점과 후속 설계는 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#녹음-동의-확인-시점)을 따른다. 현재 프로필 API에는 해당 확인을 기록하는 필드가 없으며, 이번 문서 정정은 요청 및 응답 필드를 추가하지 않는다.

### 1-1. `POST /auth/google` — 완료

구글 ID 토큰을 검증한다. 계정이 있으면 세션을, 없으면 동의 요청을 반환한다.

요청

```json
{ "idToken": "eyJhbGciOi..." }
```

응답 `200` — `status`로 구분한다.

```json
{
  "schemaVersion": 1,
  "status": "authenticated",
  "accessToken": "eyJhbGciOi...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "account": { "...": "Account" }
}
```

```json
{
  "schemaVersion": 1,
  "status": "consentRequired",
  "registrationToken": "eyJhbGciOi...",
  "expiresIn": 600,
  "consentVersion": "2026-09-06",
  "requiredConsents": ["serviceData", "sensitiveData"],
  "optionalConsents": ["serviceImprovement", "pushNotification"]
}
```

| HTTP | `errorCode` |
| --- | --- |
| 401 | `INVALID_ID_TOKEN`, `ID_TOKEN_EXPIRED`, `ID_TOKEN_AUDIENCE_MISMATCH`, `ID_TOKEN_ISSUER_MISMATCH` |
| 503 | `AUTH_NOT_CONFIGURED`, `IDENTITY_PROVIDER_UNAVAILABLE`, `DATABASE_NOT_CONFIGURED` |

### 1-2. `POST /auth/consent` — 완료

필수 동의를 받으면 계정과 첫 동의 이력을 만들고 세션을 발급한다.

요청

```json
{
  "registrationToken": "eyJhbGciOi...",
  "consentVersion": "2026-09-06",
  "consents": {
    "serviceData": true,
    "sensitiveData": true,
    "serviceImprovement": false,
    "pushNotification": true
  },
  "displayName": null
}
```

- `displayName`: 선택, 50자 이하

응답 `200` — 1-1의 `authenticated` 응답

| HTTP | `errorCode` |
| --- | --- |
| 401 | `INVALID_REGISTRATION_TOKEN`, `REGISTRATION_TOKEN_EXPIRED` |
| 409 | `CONSENT_VERSION_MISMATCH` |
| 422 | `REQUIRED_CONSENT_MISSING` |
| 503 | `DATABASE_NOT_CONFIGURED` |

### 1-3. `GET /auth/me` — 완료

응답 `200` — [Account](#account)

### 1-4. `POST /auth/logout` — 완료

요청에 사용한 세션을 폐기한다. 본문 없음.

응답 `204`

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

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `REQUIRED_CONSENT_NOT_CHANGEABLE` | `serviceData` 또는 `sensitiveData`를 보냄 |
| 422 | `INVALID_REQUEST` | 본문이 비었음 |

<br>

---

## 2. 프로필

피보호자의 이름, 성별, 생년월일은 서버의 `profiles`에 저장한다. 내부 API(8절) 요청에는 넣지 않고 BE가 생년월일로 계산한 연령대만 보낸다.

프로필 입력 상태(`setupStatus`)는 저장하지 않는다. 온보딩은 첫 카드 생성 작업(4-1)으로 끝나므로, 카드 생성 작업(`card_sets`)이 하나라도 있으면 `completed`, 없으면 `inProgress`다.

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

### 2-3. `GET /api/v1/profiles/{profileId}` — 신규

응답 `200` — [Profile](#profile)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` — 사진의 조회 URL을 만들지 못함 |

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

### 2-5. 프로필 입력 마치기 — 삭제

2026-10-06 삭제. 온보딩의 `마치기`에서 세부 정보 네 항목은 2-4로 저장하고, 4-1로 첫 카드 생성을 시작한다.

### 2-6. `POST /api/v1/profiles/{profileId}/life-facts` — 신규

일대기에서 세부 정보 네 항목 밖의 생애 정보를 추가한다.

요청

```json
{
  "storyCategory": "work",
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요.",
  "imageNumber": 3
}
```

- `storyCategory`: 일대기의 분류. `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`
- `title`: 100자 이하. `title`과 `content`는 비울 수 없다.
- `imageNumber`: 분류별 기본 그림 번호. 1~5 정수. 그림 파일은 앱에 있고 서버는 번호만 저장한다.
- 네 필드 모두 필수다. `storyCategory`, `imageNumber`의 필드 이름은 임시다([미정 사항](#미정-사항) 11).

응답 `201` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

### 2-7. `PATCH /api/v1/life-facts/{factId}` — 신규

생애 정보를 수정한다. 보낸 필드만 변경한다.

요청

```json
{ "content": "수선집에 오래 다닌 단골손님이 많았고 시장 상인들과도 친하셨어요." }
```

- 받는 필드: `storyCategory`, `title`, `content`, `imageNumber`. 규칙은 2-6과 같고 `null`로 지울 수 없다.
- 분류를 바꿔도 `imageNumber`와 `createdAt`은 그대로다.

응답 `200` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |

### 2-8. `DELETE /api/v1/profiles/{profileId}` — 신규

어르신 목록에서 프로필 하나를 지운다. 그 프로필의 생애 정보, 사진, 주제와 대화 카드, 면회 기록(평가, 음성 분석 작업, 리포트, 변경 제안)을 함께 삭제한다. 계정과 다른 프로필은 남는다. 사진과 음성 원본은 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣어 지운다.

본문 없음.

응답 `204`

- 마지막 프로필도 지울 수 있다. 지운 뒤 2-1은 빈 목록을 돌려준다.
- 카드 생성이나 음성 분석이 처리 중인 프로필의 삭제는 미정([미정 사항](#미정-사항) 8)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

### 2-9. `DELETE /api/v1/life-facts/{factId}` — 신규

일대기 이야기 한 편의 휴지통에서 확인 창을 거쳐 호출한다. 본문 없음.

응답 `204`

- 생애 정보 행만 지운다. 다음 카드 생성(4-1)의 `context.lifeFacts`에서 빠지며, 주제와 지난 카드의 근거에 남은 그 `factId`도 4-1 입력을 만들 때 뺀다. 저장된 근거는 고치지 않는다.
- 이미 만든 카드와 주제, 그 이야기를 출처로 한 변경 제안은 지우지 않는다. 지운 이야기를 근거로 한 카드와 주제의 처리는 미정([미정 사항](#미정-사항) 12)
- 세부 정보 네 항목은 생애 정보가 아니므로 이 API로 지우지 않는다(2-4에서 `null`).

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |

<br>

---

## 3. 프로필 사진

사진은 S3에 서버 측 암호화로 저장한다. 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 모두 이미지 분석(8-4)을 거친다. 면회 사진(5-2)은 분석하지 않는다.

2026-10-14 PM 결정: 사진 서버 보관과 AI 분석은 가입 화면에서 각각 선택 동의로 받고 기존 계정 동의 이력에 저장한다. 유효한 동의는 재요청하지 않으며, 미동의, 철회 또는 기록이 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 유지한다. 가입 시 수집과 계정별 저장 방향은 결정됐고 필드명 및 API는 후속 구현이다. 상세 기준은 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따른다.

위 자동 분석은 기존 API 제안이며 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)은 사진 보관과 AI 분석 동의를 구분한다. 별도 분석 동의를 확인하지 않은 사진으로 분석 작업을 만들면 안 된다. 계정별 분석 동의의 필드와 API, 분석하지 않는 사진의 상태와 철회 경로는 후속 계약에서 정한다. 아래 요청 필드와 응답 enum은 이번 문서 수정에서 바꾸지 않으며 실제 사용자 사진 처리에 적용하기 전 이 차이를 해소해야 한다.

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

### 3-2. `GET /api/v1/profile-photos/{photoId}` — 신규

`analysisStatus`가 `completed` 또는 `failed`가 될 때까지 폴링한다.

응답 `200` — [ProfilePhoto](#profilephoto)

- `failed`이면 온보딩을 계속한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_PHOTO_NOT_FOUND` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` — 사진의 조회 URL을 만들지 못함 |

<a id="3-3-사진-설명-확인--미정"></a>

### 3-3. 앨범에서 사진 설명 수정 — API 미정

9월 23일 회의와 10월 6일 BE 논의에서 정한 대로, AI 사진 설명은 별도 승인 없이 카드 생성에 사용한다. 사용자는 원할 때 앨범에서 확인하거나 수정한다. 사진 등록과 카드 선택에 필수 확인 단계를 넣지 않으며, 수정 API가 정해지기 전이라는 이유로 설명 사용을 막지 않는다.

사진 설명을 질문의 입력으로 쓰는 것과 승인된 생애 사실을 저장하는 것은 다르다. 사진 설명이나 카드 선택만으로 `life_facts`에 저장하지 않는다. 사진 분석 동의도 별도로 확인한다. 기존 결정을 확인한 [PR #97 의견](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97#discussion_r4183313066), [상세 흐름](card-generation-flow.md#4-사진-설명은-바로-사용하고-앨범에서-선택적으로-수정)을 참고한다.

남은 사항은 설명 수정의 경로와 요청 형식, 분석 중 수정 및 늦게 도착한 결과의 처리다. 새 승인 여부 컬럼을 필수 조건으로 정한 것은 아니다.

<br>

---

## 4. 대화 카드

### 사실 정정 후 카드 갱신 기준

생성 시점은 [PM 기준](../pm/README.md#사실-정정과-다음-면회-카드-반영)을 따른다. 정정은 즉시 저장하고 영향받은 카드의 사용을 중지한다. 매번 재생성하지 않고 ‘다음 대화 준비’에서 누적 정정을 반영해 카드 묶음 전체를 한 번 재생성한다. 완료 후 카드 선택과 대화 시작을 허용한다.

2026-10-16 [PM 기준](../pm/README.md#사실-정정과-다음-면회-카드-반영): 정정으로 사용 중지한 카드는 대화 평가의 미사용과 구분하며 추천 불이익을 주지 않는다.

아래 상태 표와 `CARD_SET_READY`는 현재 계약이다. 기존 코드는 준비된 카드의 입력이 이후 수정됐는지 구분하지 않으므로 이 제품 기준을 충족하는 구현이 아니다. 2-4, 2-7과 7-4의 사실 저장, 4-1부터 4-3의 생성 및 조회, 5-1의 면회 시작 사이에서 정정 반영 여부를 맞춰야 한다. 반영 대기 저장 방식, 입력 변경 감지, 갱신 실패와 생성 중 해당 프로필 정정 저장 제한와 API 변경은 담당자가 설계한다. 이 문서 변경으로 기존 응답 enum이나 오류 코드를 임의로 바꾸지 않는다.

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

4-1과 4-2는 상태를 보기 전에 더는 끝나지 않을 `running` 작업을 `failed`로 바꾼다. worker가 가져가지 않은 채 `SAEROK_CARD_GENERATION_START_TIMEOUT_SECONDS`(기본 360초)가 지난 작업은 `CARD_GENERATION_NOT_STARTED`, 임대가 만료된 작업은 `WORKER_LEASE_EXPIRED`다. 임대 만료 정리는 원래 worker가 하므로, worker가 없거나 멈추면 작업이 `running`으로 남아 앱이 다시 요청할 수 없기 때문이다.

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
- 아직 쓰지 않은 묶음이 있으면(`ready`) 409로 거절한다. 그래서 회차에 쓸 수 있는 완료 묶음은 늘 가장 최근 묶음 하나뿐이고, 5-1이 받는 묶음이 4-2, 4-3이 보는 묶음과 같다.
- 카드 생성 worker가 작업을 가져가 카드 12장과 새 주제를 저장한다(아래 처리). 앱은 4-2를 폴링한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `VISIT_IN_PROGRESS` (평가 전 회차가 있음), `CARD_SET_READY` (아직 쓰지 않은 묶음이 있음) |
| 503 | `CARD_GENERATION_NOT_CONFIGURED` (LLM 키가 설정되지 않음) |

#### 4-1 카드 생성 처리

BE의 카드 생성 함수가 ML API를 호출한다. 실제 생성 함수 연결은 후속 작업이다.

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
- `photos`: 분석이 끝난 프로필 사진(`session_id`가 없음)의 설명. 별도 내용 승인 없이 사용하고, 사용자가 원하면 앨범에서 수정한다(3-3). 사진 분석 동의 확인은 별도로 유지한다.
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
- `topic`: 기존 주제면 `topicId`, 새 주제면 `title`, `description`, `evidence`. 새 주제는 BE가 `profile_topics`에 만든다. 한 묶음 안에서 같은 `topicId`는 두 번 나오지 않는다.
- `evidenceSource`: `lifeFact`, `photo`, `profile`, `none`. `none`이면 `evidence`는 빈 배열이고 나머지는 하나 이상이다. 근거 항목은 `{"factId": ...}`, `{"photoId": ...}`, `{"profileField": "occupation" | "hometown" | "hobby" | "family"}` 중 하나이며, 카드의 근거 항목은 모두 `evidenceSource`와 같은 종류다(`lifeFact`는 `factId`, `photo`는 `photoId`, `profile`은 `profileField`). `profileField`는 context의 `profileFacts`에서 값이 있는 항목만 가리킨다.
- `extra`, `log`: 생성 쪽이 자유롭게 채우는 객체다. BE는 내용을 보지 않고 `generation_log`에만 남긴다.
- `cardId`와 새 주제의 `topicId`는 백엔드가 부여한다.

검증과 저장

- BE는 저장 전에 확인한다: 12장, `position` 1~12가 한 번씩, 꼬리 질문 3개, 카드 제목·설명·첫 질문·꼬리 질문이 공백만으로 되어 있지 않음, 한 묶음 안 같은 `topicId` 중복 없음, 기존 `topicId`와 근거 ID가 context에 있음, 보호자가 `exclude`를 고른 주제는 쓰지 않음, `profileField`는 context에 값이 있는 항목, 근거 항목 형식, 카드의 근거 항목이 `evidenceSource`와 같은 종류(`none`이면 빈 배열). 맞지 않으면 `INVALID_GENERATION_RESULT`로 실패시킨다.
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
| `CARD_GENERATION_NOT_STARTED` | 정해진 시간 안에 worker가 작업을 가져가지 않음(4절) |
| `WORKER_LEASE_EXPIRED` | worker가 임대 시간 안에 작업을 끝내지 못함 |


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

### 4-3. `GET /api/v1/profiles/{profileId}/card-generations/current` — 신규

지금 쓸 카드 묶음이다. 4-2가 `ready`(고르기 전)나 `inVisit`(면회 시작은 했고, 평가 전)일 때 그 묶음을 준다. 카드 고르기, 면회 중, 중간에 나갔다 돌아온 경우 모두 같은 카드를 받는다. 평가(6-1)를 마치면 더는 나오지 않는다.

응답 `200` — [CardSet](#cardset)

- `position` 1~9는 선택 화면용, 10~12는 면회 중 보충용이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND`, `CARD_GENERATION_NOT_FOUND`(쓸 묶음이 없음) |

<br>

---

## 5. 면회

회차는 녹음을 시작할 때 만든다. 녹음 일시정지와 종료는 단말에서 처리하고 서버에 알리지 않는다.

회차 상태는 저장하지 않고 평가, 음성 분석 작업과 리포트로 계산한다.

| `sessionStatus` | 조건 |
| --- | --- |
| `evaluationPending` | 보호자 평가 전 |
| `audioPending` | 평가 후 음성 접수 전. 작업이 없거나 업로드 단계에서 실패한 작업만 있음 |
| `processing` | 음성 분석 작업이 `queued`, `transcribing`, `sttCompleted`, `generatingReport` |
| `completed` | 리포트 저장 |
| `failed` | 접수된 음성 분석 작업이 `failed` |

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

- `selectedCardIds`는 중복 없이 1~9개이며 해당 작업의 `position` 1~9 안에서 고른다.

응답 `201` — [VisitSession](#visitsession), `sessionStatus`는 `evaluationPending`

- `startedAt`은 서버 수신 시각이다.
- 고른 카드를 `selected`로 바꾸고, 작업의 `usedBySessionId`를 이 회차로 채운다.
- 녹음 동의는 가입 때 받으므로 이 요청에서 받지 않는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_GENERATION_NOT_FOUND` |
| 409 | `CARD_GENERATION_NOT_COMPLETED`, `CARD_SET_ALREADY_USED` |
| 422 | `INVALID_CARD_SELECTION` |

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

### 5-3. `PATCH /api/v1/visit-sessions/{sessionId}/cards` — 신규

면회 중 꺼낸 보충 카드를 회차의 고른 카드에 더한다. 보충 카드 세 장(10~12번)은 4-3으로 언제든 볼 수 있다.

요청

```json
{ "cardIds": ["00000000-0000-4000-8000-000000000510"] }
```

- 같은 묶음의 `position` 10~12 안에서 중복 없이 고른다(1~3개). 이미 더한 카드는 무시하므로 같은 요청을 다시 보내도 결과가 같다.

응답 `200` — [VisitSession](#visitsession)

- 추가한 카드를 `selected`로 바꾸고 `selectedCardIds`에 더한다.
- `evaluationPending` 상태에서만 받는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `INVALID_SESSION_STATE` |
| 422 | `INVALID_CARD_SELECTION` |

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

<br>

---

## 6. 평가와 음성 제출

보호자 평가의 `리포트 만들기`에서 6-1과 6-2를 차례로 호출한다. 6-1이 성공하고 6-2가 실패하면 6-2만 다시 보낸다.

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

### 6-4. `GET /api/v1/visit-sessions/{sessionId}/evaluation` — 신규

리포트 화면에서 카드별 결과(평가함, 쓰지 않음, 답하지 않음)를 표시할 때 사용한다.

응답 `200` — [CaregiverEvaluation](#caregiverevaluation)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `EVALUATION_NOT_FOUND` |

<br>

---

## 7. 리포트와 변경 제안

리포트는 회차에 저장하며 회차 ID로 조회한다. 변경 제안은 생애 정보 제안과 주제 제안 두 가지이며 회차마다 0개 이상이다. 리포트 확인 여부는 저장하지 않는다([미정 사항](#미정-사항) 2).

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

### 7-2. `GET /api/v1/visit-sessions/{sessionId}/report` — 신규

응답 `200` — [VisitReport](#visitreport)

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` | |
| 404 | `REPORT_NOT_FOUND` | 리포트 저장 전 |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` | 면회 사진의 조회 URL을 만들지 못함 |

### 7-3. `GET /api/v1/visit-sessions/{sessionId}/proposals` — 신규

응답 `200` — [ChangeProposal](#changeproposal)

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND` | |
| 404 | `REPORT_NOT_FOUND` | 리포트 저장 전 |

### 7-4. `POST /api/v1/visit-sessions/{sessionId}/proposals/review` — 신규

변경 사항 확인 화면의 `이대로 반영하기` 또는 `반영하지 않고 마치기`에서 호출한다.

요청

```json
{
  "lifeFacts": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000801",
      "reviewStatus": "accepted",
      "title": "한복",
      "content": "한복과 두루마기를 주로 만드셨어요."
    }
  ],
  "topics": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000802",
      "reviewStatus": "accepted",
      "action": "more"
    }
  ]
}
```

- 회차의 `pending` 제안을 모두 담는다. 화면에 남긴 항목은 `accepted`, X로 뺀 항목은 `rejected`
- `accepted`인 항목에만 보호자가 확인한 최종 값을 담는다. `rejected`인 항목은 `proposalId`와 `reviewStatus`만 보낸다.
  - `lifeFacts[].title`, `content`: 생애 정보로 만들 최종 제목과 내용. 고치지 않았으면 제안 값을 그대로 보낸다. 2-6과 같이 `title`은 100자 이하이고 둘 다 비울 수 없다.
  - `topics[].action`: `more`, `less`, `exclude`. 보호자가 고른 행동이며 제안의 `suggestedAction`과 달라도 된다. 바꾸지 않았으면 제안 값을 그대로 보낸다.
- `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- 제안이 없는 회차의 확인 처리는 미정([미정 사항](#미정-사항) 2)

응답 `200` — [ChangeProposal](#changeproposal)

서버 처리

- 모든 제안을 `settled`로 바꾼다.
- `accepted`인 생애 정보 제안은 요청의 `title`, `content`로 생애 정보를 만든다. 생애 정보의 `source_proposal_id`가 그 제안이다. 제안(`life_fact_proposals`)의 `title`, `content`, `reason`은 바꾸지 않는다.
- `accepted`인 주제 제안은 요청의 `action`을 `topic_feedback.action`에 기록하고 다음 카드 생성(4-1)의 `topics`에 반영한다. 제안의 `suggested_action`은 바꾸지 않는다.
- `rejected` 항목은 반영하지 않는다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `REPORT_NOT_FOUND` | |
| 409 | `PROPOSAL_ALREADY_REVIEWED` | 이미 `settled`인 제안이 있음 |
| 422 | `INVALID_PROPOSAL_REVIEW` | `pending` 제안이 빠졌거나 다른 회차의 제안 |
| 422 | `INVALID_REQUEST` | `accepted` 항목에 최종 값(`title`과 `content`, 또는 `action`)이 없거나 `rejected` 항목에 있음 |

<br>

---

## 8. 내부 API (백엔드 → AI 서버)

백엔드 worker가 동기 호출한다. 앱은 호출하지 않는다. 원본 파일은 수명이 짧은 S3 Presigned GET URL로만 전달한다. 피보호자의 이름, 성별, 생년월일은 어떤 요청에도 넣지 않는다.

AI 서버 호출이 실패하면 해당 작업을 `failed`로 바꾸고 다음 `errorCode`를 남긴다: `AI_SERVER_TIMEOUT`, `AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `INVALID_AI_RESPONSE`. worker가 임대 시간 안에 작업을 끝내지 못하면 `WORKER_LEASE_EXPIRED`다. 자동으로 다시 시도하지 않는다.

8-3, 8-4 응답의 `model`, `promptVersion`은 결과와 함께 저장한다. 카드 생성은 AI 서버를 거치지 않으며 4-1에 적는다(8-2 삭제).

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

### 8-2. 카드 생성 — 삭제

AI 서버를 거치지 않으므로 4-1의 처리 과정으로 옮겼다([4-1 카드 생성 처리](#4-1-카드-생성-처리)).

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

- `description`은 별도 승인 없이 카드 생성에 사용한다. 사용자는 원할 때 앨범에서 수정한다(3-3). 사진 분석 동의 확인과 생애 사실의 승인 규칙은 유지한다.

<br>

---

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
    "pushNotification": { "granted": true, "grantedAt": "2026-08-21T11:40:00+09:00" }
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

- `occupation`, `hometown`, `hobby`, `family`: 세부 정보 네 항목. 건너뛰었거나 2-4에서 저장하기 전이면 `null`

### LifeFact

```json
{
  "schemaVersion": 1,
  "factId": "00000000-0000-4000-8000-000000000111",
  "profileId": "00000000-0000-4000-8000-000000000101",
  "storyCategory": "work",
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요.",
  "imageNumber": 3,
  "createdAt": "2026-08-21T12:10:00+09:00"
}
```

- `storyCategory`, `imageNumber`: 2-6과 같다. 7-4로 만든 생애 정보는 `other`이고 번호는 서버가 1~5 중에 고른다(분류 결정 방식은 [미정 사항](#미정-사항) 13).

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
        "title": "재봉 일",
        "description": "젊은 시절 하시던 일과 그때의 하루를 여쭤보는 주제예요."
      },
      "suggestedAction": "more",
      "reason": "재봉 일 이야기에 반응이 좋으셨어요.",
      "reviewStatus": "pending"
    }
  ]
}
```

- `topic.description`: 주제 설명이다. [CardSet](#cardset)의 `topic.description`, 8-2의 `topics[].description`과 같은 값이다.
- `suggestedAction`: `more`, `less`, `exclude`
- `reviewStatus`: `pending`, `accepted`, `rejected`. DB에는 `pending`과 `settled`만 저장하므로, `settled`인 제안은 승인 결과(생애 정보 또는 주제 피드백)가 있으면 `accepted`, 없으면 `rejected`로 반환한다.
- `lifeFactProposals`의 `title`, `content`와 `topicProposals`의 `suggestedAction`은 AI의 원래 제안이며 검토 뒤에도 바뀌지 않는다. 보호자가 고친 값은 생애 정보와 주제 피드백에만 남는다. 검토 뒤 응답에 보호자가 고른 값을 담을지는 미정([미정 사항](#미정-사항) 10)

<br>

---

## 미정 사항

| # | 항목 | 영향 | 확인할 곳 |
| --- | --- | --- | --- |
| 1 | 앨범에서 사진 설명을 수정하는 API와 분석 중 수정 처리. 설명의 별도 승인은 필요 없음 | 3-3, 카드 생성, 8-4 | FE, BE, AI. 카드 입력 사용과 생애 사실 승인을 구분 |
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 확인했는지 알 수 없음 | 4-1 호출 시점, 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 3 | 사진 보관과 AI 분석은 가입 화면의 별도 선택 항목으로 받고 계정별 이력에 저장하기로 PM 결정 완료(2026-10-14). 유효한 동의는 재요청하지 않으며 미동의자는 기능 사용 시 요청. 남은 것은 동의 필드 및 가입, 조회, 변경 API와 화면 연결, 분석하지 않는 사진의 상태 및 철회 처리 | 1-1~1-3, 1-6, 3-1, 5-2, 8-4 | FE, BE, AI. 기존 동의 범위를 바꾸는 경우 PM 확인 |
| 7 | 사진 삭제와 보관 동의 철회 동선 및 API 형태. DB 삭제 대기열 등록 이후 S3 실제 삭제와 결과 확인은 미구현 | 3절 | FE, BE, PM |
| 8 | 카드 생성이나 음성 분석이 처리 중인 프로필 또는 계정을 지울 때의 처리. 삭제를 허용하고 worker가 사라진 행을 건너뛸지, 처리 중에는 409로 막을지 | 1-5, 2-8 | BE |
| 9 | 입력 중(`inProgress`)인 프로필만 있을 때 로그인 직후 그 프로필의 입력을 이어서 할지, 홈으로 갈지 | 2-1, 호출 순서 | FE, BE |
| 10 | 검토 뒤 ChangeProposal 응답에 보호자가 고른 행동과 고친 생애 정보를 담을지. 지금은 원래 제안 값만 돌려줌 | 7-3, 7-4 | FE, BE |
| 11 | 일대기 분류와 그림 번호의 필드 이름(`storyCategory`, `imageNumber`는 임시) | 2-3, 2-6, 2-7 | FE, BE. [작업 D 문서](../../backend/docs/work-split/D-life-story.md) D1, D2 |
| 12 | 지운 이야기를 근거로 만든 카드와 주제의 처리, 카드 생성 기록(`generation_log`)에 남는 이야기 내용, 지운 이야기의 제안이 7-3에서 `rejected`로 보이는 문제 | 2-9, 4-1, 7-3 | PM, BE, AI. 작업 D 문서 D3, D4, D6 |
| 13 | 면회 제안을 승인해 만드는 생애 정보의 분류를 AI가 제안할지 보호자가 고를지 | 7-3, 7-4, 8-3 | PM, AI, FE, BE. 작업 D 문서 D5 |
