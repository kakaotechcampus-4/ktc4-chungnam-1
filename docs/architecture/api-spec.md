# 새록 API 명세

앱과 백엔드 사이의 공개 API, 백엔드와 AI 서버 사이의 내부 API를 정리한다. 저장 구조는 [init.sql](../../backend/database/init.sql)의 DB 스키마를 따른다. 예시 값은 모두 합성 데이터다.

2026-10-12 문서 정리: 사진 설명은 별도 승인 없이 카드 생성에 쓰고 앨범에서 선택적으로 수정한다(3-3). 카드 API와 요청 및 결과 형식은 [PR #99](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/99)에 맞췄다. 프로필 저장(2-4) 후 카드 생성을 요청(4-1)하고, BE의 4-1 처리에서 생성 함수를 호출한다. 이전 2-5와 내부 8-2는 삭제했으며, 실제 AI 생성 함수 연결은 후속 작업이다.

STT 외 생성 기능은 ML API를 활용하는 방향이다. 8-3과 8-4의 내부 HTTP 형식을 실제 GPU 실행 위치와 동일시하지 않는다. 리포트(8-3)는 [PR #123](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/123)에서 BE가 `ai/`의 생성 함수를 직접 부르는 방식으로 연결한다. 요청과 응답 형식, BE 검증과 오류 코드는 그대로이며, 생성 함수 안에서 외부 ML API로 요청을 보낸다는 점도 같다.

## 공통

| 항목 | 기준 |
| --- | --- |
| 인증 | `/auth/google`, `/auth/consent`를 제외한 모든 공개 API는 `Authorization: Bearer <accessToken>` |
| 앱 버전 | 앱은 모든 공개 API에 `X-App-Version-Code: <안드로이드 versionCode>`를 싣는다. 서버 설정(`SAEROK_MIN_ANDROID_VERSION_CODE`)보다 낮으면 인증보다 먼저 `426 APP_UPDATE_REQUIRED`로 거절한다. 헤더가 없거나 숫자가 아니면 검사하지 않는다. `/health/*`는 검사하지 않는다 |
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
| 413 | `REQUEST_TOO_LARGE` | 업로드가 아닌 요청의 본문이 1 MiB를 넘음. 로그인 전 API 포함([본문 크기와 확인 순서](#본문-크기와-확인-순서)) |
| 422 | `INVALID_REQUEST` | 요청 형식 오류 |
| 426 | `APP_UPDATE_REQUIRED` | 앱 버전(`X-App-Version-Code`)이 최소 지원 버전보다 낮음. 로그인 전 API 포함 |
| 500 | `INTERNAL_SERVER_ERROR` | 서버 내부 오류 |
| 503 | `DATABASE_NOT_CONFIGURED` | 서버의 DB 연결 설정이 없음 |

### 본문 크기와 확인 순서

서버는 본문을 읽기 전에 경로별 본문 상한을 정하고, 넘는 본문은 끝까지 받지 않고 `413`으로 거절한다. `Content-Length`가 상한을 넘으면 본문을 읽지 않는다. 길이를 밝히지 않은 chunked 본문은 받은 양이 상한을 넘는 순간 끊는다.

| 경로 | 본문 상한 | 넘으면 |
| --- | --- | --- |
| 3-1 프로필 사진, 5-2 면회 사진 | 사진 상한(`SAEROK_MAX_IMAGE_BYTES`, 기본 20 MiB) + 1 MiB | `413 IMAGE_TOO_LARGE` |
| 6-2 면회 음성 | 음성 상한(`SAEROK_MAX_AUDIO_BYTES`, 기본 512 MiB) + 1 MiB | `413 AUDIO_TOO_LARGE` |
| 6-6 프로필 입력용 전사 | 10 MiB와 `SAEROK_MAX_AUDIO_BYTES` 중 작은 값 + 1 MiB | `413 AUDIO_TOO_LARGE` |
| 그 밖의 모든 경로 | 1 MiB | `413 REQUEST_TOO_LARGE` |

더한 1 MiB는 multipart 경계와 파일이 아닌 필드의 여유다. 파일 자체의 크기는 지금처럼 라우트가 검사하므로, 본문 상한 안에서 파일만 상한을 넘으면 같은 오류 코드를 라우트가 돌려준다.

업로드 네 경로는 다음 순서로 확인한다. 업로드가 아닌 경로는 2부터 시작한다.

1. 본문을 읽기 전에 앱 버전(`426 APP_UPDATE_REQUIRED`)과 세션 토큰의 형식, 서명, 만료(`401 UNAUTHENTICATED`, `401 SESSION_EXPIRED`)를 확인한다.
2. 본문 상한(`413`)을 `Content-Length`로 먼저 보고, 받는 동안 다시 센다.
3. 본문을 다 받은 뒤 앱 버전, 세션(업로드가 아닌 경로는 이때 형식, 서명, 만료도 확인한다)과 폐기 여부, 계정, 소유권과 동의를 확인한다. 로그아웃이나 탈퇴로 폐기한 세션은 이 단계에서 `401 UNAUTHENTICATED`다.
4. 라우트가 파일 형식과 크기를 검사한다.

HTTPS 앞단(Caddy, `backend/Caddyfile`)에도 514 MiB 본문 상한이 있다. 정상 설정에서는 위 경로별 상한이 더 작아 API가 먼저 응답하고, Caddy 상한은 API 상한을 잘못 키웠을 때의 바깥 방어선이다. 그때 Caddy의 `413`에는 위 오류 형식의 본문이 없다.

상한을 넘거나 1단계에서 거절한 업로드는 본문을 끝까지 받지 않고 응답하므로, 아직 본문을 보내던 클라이언트는 `413`이나 `401` 본문 대신 연결 오류를 받을 수 있다. 앱은 올리기 전에 파일 크기를 확인한다.

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
| 1-7 | 앱 시작, 알림 수신 동의 | `PUT` | `/auth/me/push-devices/{fid}` | 미병합 |
| 1-8 | 로그아웃, 알림 수신 철회 | `DELETE` | `/auth/me/push-devices/{fid}` | 미병합 |
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
| 3-4 | 앨범에서 사진 삭제 | `DELETE` | `/api/v1/profile-photos/{photoId}` | 신규 |
| 4-1 | 홈 | `POST` | `/api/v1/profiles/{profileId}/card-generations` | 신규 |
| 4-2 | 홈 | `GET` | `/api/v1/profiles/{profileId}/card-generations/status` | 신규 |
| 4-3 | 대화 카드 선택 | `GET` | `/api/v1/profiles/{profileId}/card-generations/current` | 신규 |
| 4-4 | 지난 대화 카드 보기 | `GET` | `/api/v1/visit-sessions/{sessionId}/card-set` | 신규 |
| 4-5 | 지난 대화 카드 보기 | `PUT` | `/api/v1/cards/{cardId}/like` | 신규 |
| 4-6 | 지난 대화 카드 보기 | `DELETE` | `/api/v1/cards/{cardId}/like` | 신규 |
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
    [리포트]      7-2, 6-4 → 7-3 → 7-4. 회차의 카드 전체 보기: 4-4, 좋았어요 표시: 4-5, 4-6
    [일대기]      2-3, 2-6, 2-7, 2-9
    [마이페이지]  2-3, 2-4, 3-1, 3-2, 1-6, 7-1, 1-4, 1-5
    [푸시 기기]   알림 수신에 동의한 계정이면 앱을 켤 때마다 1-7. 로그아웃 전과 알림 수신 철회 때 1-8

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
  "optionalConsents": ["serviceImprovement", "pushNotification", "photoAnalysis"]
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
- `consents`의 값은 JSON `true`, `false`만 받는다. `"yes"`, `"on"`, `1` 같은 값은 동의로 읽지 않고 `422 INVALID_REQUEST`로 거절하며 계정을 만들지 않는다. 1-6과 같은 기준이다.
- 등록 토큰은 한 번만 쓴다. 계정을 만들거나 세션을 주면 그 토큰을 쓴 것으로 남기고, 같은 토큰을 다시 보내면 로그아웃이나 탈퇴 뒤에도 `401 INVALID_REGISTRATION_TOKEN`이다. 계정을 만들지 못한 `409`, `422`는 토큰을 쓴 것으로 치지 않으므로 고쳐서 다시 보낼 수 있다.
- 응답을 받지 못해 같은 토큰으로 다시 보낸 앱도 `401 INVALID_REGISTRATION_TOKEN`을 받는다. 앱은 1-1부터 다시 하고, 그사이 계정이 만들어졌으면 1-1이 `authenticated`를 준다.
- 계정이 없을 때 받은 다른 등록 토큰으로 이미 가입을 마쳤다면, 아직 쓰지 않은 토큰은 계정을 덧만들지 않고 그 계정의 세션을 한 번 준다.

응답 `200` — 1-1의 `authenticated` 응답

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 401 | `INVALID_REGISTRATION_TOKEN` | 등록 토큰이 유효하지 않거나 이미 사용함 |
| 401 | `REGISTRATION_TOKEN_EXPIRED` | 등록 토큰 수명(기본 600초)이 지남 |
| 409 | `CONSENT_VERSION_MISMATCH` | 약관 버전이 서버와 다름 |
| 422 | `REQUIRED_CONSENT_MISSING` | 필수 동의를 거부함 |
| 422 | `INVALID_REQUEST` | 요청 형식 오류. `consents` 값이 `true`, `false`가 아니거나 `displayName`이 50자를 넘는 경우 포함 |
| 503 | `AUTH_NOT_CONFIGURED` | 서버의 세션 서명 키가 설정되지 않음 |
| 503 | `DATABASE_NOT_CONFIGURED` | 서버의 DB 연결 설정이 없음 |

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
- `pushNotification: false`를 보내면 같은 트랜잭션에서 그 계정의 푸시 기기 등록(1-7)을 모두 지운다.
- `photoAnalysis`(AI 사진 분석)도 같은 방식으로 바꾼다. 거두면 사진 분석 worker가 그 계정의 사진을 더 가져가지 않는다. 이미 가져간 사진도 ML 업체에 보내기 전이면 보내지 않고, 보낸 뒤면 결과를 저장하지 않는다. 두 경우 모두 사진은 `pending`으로 돌아간다.
- `photoAnalysis: false`를 보내면 같은 트랜잭션에서 그 계정 프로필 사진의 저장된 AI 설명을 지우고 `analysisStatus`를 `pending`으로 되돌린다(2026-11-09 PM 결정). 보호자가 쓴 설명(3-3)은 남아 2-3, 3-2의 `description`(`descriptionSource: caregiver`)과 카드 입력에 그대로 쓴다. 보호자 설명이 없는 사진의 AI 설명을 지운 프로필은 아직 면회에 안 쓴 완료 묶음의 `needsRefresh`가 `true`가 된다(4절). 3-4 사진 삭제처럼 그 묶음이 지운 설명을 실제로 입력에 썼는지는 따지지 않는다. 카드를 만드는 중이어도 동의 변경은 거절하지 않으며, 만드는 중인 묶음은 지운 설명을 입력에 썼으면 완료할 때 `needsRefresh`가 `true`가 된다. 다시 `true`로 바꾸면 `pending`인 사진을 다시 분석한다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `REQUIRED_CONSENT_NOT_CHANGEABLE` | `serviceData` 또는 `sensitiveData`를 보냄 |
| 422 | `INVALID_REQUEST` | 본문이 비었음 |

### 1-7. `PUT /auth/me/push-devices/{fid}` — 미병합

리포트 완료 푸시를 받을 이 기기를 등록한다. 본문 없음.

- `fid`: 앱이 FCM에 등록하고 받은 Firebase Installation ID(FID). FCM은 기기 토큰(`getToken`) 대신 FID를 쓰도록 바꿨고, 서버는 HTTP v1 발송의 `fid`에 이 값을 넣는다. 영문 대소문자, 숫자, `-`, `_`로 된 1~64자다(지금 FID는 22자).
- 같은 요청을 다시 보내면 등록 시각(`push_devices.registered_at`)만 새로 한다. 앱은 켤 때마다 다시 보낸다.
- 다른 계정에 등록된 FID면 이 계정으로 옮긴다. 같은 기기에서 계정을 바꿔 로그인한 경우이며, 앞 계정의 알림이 이 기기로 가지 않게 된다.
- 알림 수신(`pushNotification`)에 동의하지 않은 계정이면 저장하지 않고 거절한다.
- 계정당 5대(서버 설정 `SAEROK_PUSH_DEVICES_PER_ACCOUNT`)까지 둔다. 새 기기로 한도를 넘으면 등록 시각이 가장 오래된 기기, 곧 가장 오래 앱을 켜지 않은 기기의 등록을 지우고 `204`로 답한다. 오류로 알리지 않으며 방금 등록한 기기는 지우지 않는다. 지워진 기기는 앱을 다시 켜서 1-7을 보내면 다시 등록된다(2026-11-09 PM 결정).
- 탈퇴(1-5)하면 계정과 함께 지운다.
- 리포트가 완료되면(6-3의 `completed`) 서버가 그 계정에 등록된 기기로 알림을 보낸다. 알림 문구는 `새록`, `리포트가 준비되었어요`로 고정이고, `data`에는 `type: "reportReady"`, `sessionId`, `analysisId`만 담는다. 어르신 이름과 리포트 내용은 담지 않는다. `data` 항목은 FE와 합의 전인 테스트 가정이다. 리포트 생성 실패는 알리지 않는다.

응답 `204`

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 403 | `PUSH_NOTIFICATION_CONSENT_REQUIRED` | 알림 수신에 동의하지 않음 |
| 422 | `INVALID_REQUEST` | `fid` 형식이 맞지 않음 |

### 1-8. `DELETE /auth/me/push-devices/{fid}` — 미병합

1-7의 등록을 지운다. 본문 없음. 앱은 로그아웃(1-4) 전과 알림 수신을 끌 때 보낸다. 로그아웃 뒤에는 세션이 없어 지울 수 없다.

응답 `204`

- 등록되지 않았거나 다른 계정에 등록된 FID여도 `204`다. 다른 계정의 등록은 지우지 않는다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `INVALID_REQUEST` | `fid` 형식이 맞지 않음 |

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
- `birthDate`: `YYYY-MM-DD`. 만 10세 이상인 날짜만 받는다. 기준일은 서버의 UTC 날짜이고, 기준일에 없는 2월 29일은 2월 28일로 본다. 카드 생성 입력의 연령대(4-1 `ageRange`)가 `10s` 이상이어야 하기 때문이며, 그 밖의 나이 제한은 두지 않는다.
- `condition.stage`: `mildCognitiveImpairment`, `mildDementia`, `unknown`
- `condition.symptomNote`: 선택

응답 `201` — [Profile](#profile), `setupStatus`는 `inProgress`

- 계정당 최대 3개다. 입력 중(`inProgress`)인 프로필도 센다. DB에 개수 제약이 없으므로 서버가 확인한다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 409 | `PROFILE_LIMIT_EXCEEDED` | 계정에 이미 프로필이 3개 있음 |
| 422 | `INVALID_REQUEST` | `birthDate`가 미래이거나 만 10세가 안 된 날짜. 그 밖의 형식 오류 포함 |

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
- `birthDate`는 2-2와 같이 만 10세 이상인 날짜만 받는다. 걸리면 함께 보낸 다른 필드도 저장하지 않는다.
- `birthDate`, `occupation`, `hometown`, `hobby`, `family`가 실제로 바뀌면 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다(4절). 카드를 만드는 중이면 이 값들은 고칠 수 없다.

응답 `200` — [Profile](#profile)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `CARD_GENERATION_IN_PROGRESS`(카드를 만드는 중) |
| 422 | `INVALID_REQUEST`(`birthDate`가 미래이거나 만 10세가 안 된 날짜, 그 밖의 형식 오류) |

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
- `title`: 100자 이하. `content`: 5,000자 이하(2026-11-09 PM 결정). `title`과 `content`는 비울 수 없다. 글자 수는 유니코드 코드 포인트 수로 센다.
- `imageNumber`: 분류별 기본 그림 번호. 1~5 정수. 그림 파일은 앱에 있고 서버는 번호만 저장한다.
- 네 필드 모두 필수다. `storyCategory`, `imageNumber`의 필드 이름은 임시다([미정 사항](#미정-사항) 11).
- 프로필 하나의 이야기는 300개까지다(2026-11-09 PM 결정). 변경 제안 승인(7-4)으로 만든 이야기도 함께 센다. 이미 300개면 저장하지 않고 `409 LIFE_FACT_LIMIT_EXCEEDED`이며, 이야기를 지우면(2-9) 다시 추가할 수 있다.

응답 `201` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `LIFE_FACT_LIMIT_EXCEEDED`(프로필에 이야기가 이미 300개 있음) |
| 422 | `INVALID_REQUEST`(`title` 100자 또는 `content` 5,000자 초과, 빈 값, 그 밖의 형식 오류) |

### 2-7. `PATCH /api/v1/life-facts/{factId}` — 신규

생애 정보를 수정한다. 보낸 필드만 변경한다.

요청

```json
{ "content": "수선집에 오래 다닌 단골손님이 많았고 시장 상인들과도 친하셨어요." }
```

- 받는 필드: `storyCategory`, `title`, `content`, `imageNumber`. 규칙은 2-6과 같고(`title` 100자, `content` 5,000자 이하) `null`로 지울 수 없다. 이야기 수는 바뀌지 않으므로 300개 상한은 보지 않는다.
- 분류를 바꿔도 `imageNumber`와 `createdAt`은 그대로다.
- `title`, `content`가 실제로 바뀌면 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다(4절). 카드를 만드는 중이면 이 두 값은 고칠 수 없다.

응답 `200` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |
| 409 | `CARD_GENERATION_IN_PROGRESS`(카드를 만드는 중) |
| 422 | `INVALID_REQUEST`(`title` 100자 또는 `content` 5,000자 초과, 빈 값이나 `null`, 그 밖의 형식 오류) |

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
- 이미 만든 카드와 주제, 그 이야기를 출처로 한 변경 제안은 지우지 않는다. 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다(4절). 카드를 만드는 중이면 지울 수 없다. 지난 카드와 주제의 처리는 미정([미정 사항](#미정-사항) 12)
- 세부 정보 네 항목은 생애 정보가 아니므로 이 API로 지우지 않는다(2-4에서 `null`).

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |
| 409 | `CARD_GENERATION_IN_PROGRESS`(카드를 만드는 중) |

<br>

---

## 3. 프로필 사진

사진은 S3에 서버 측 암호화로 저장한다. 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 모두 이미지 분석(8-4)을 거친다. 면회 사진(5-2)은 분석하지 않는다.

2026-10-14 PM 결정: 사진 서버 보관과 AI 분석은 가입 화면에서 각각 선택 동의로 받고 기존 계정 동의 이력에 저장한다. 유효한 동의는 재요청하지 않으며, 미동의, 철회 또는 기록이 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 유지한다. 가입 시 수집과 계정별 저장 방향은 결정됐고 필드명 및 API는 후속 구현이다. 상세 기준은 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따른다.

위 자동 분석은 기존 API 제안이며 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)은 사진 보관과 AI 분석 동의를 구분한다. 별도 분석 동의를 확인하지 않은 사진으로 분석 작업을 만들면 안 된다. AI 분석 동의는 계정별 선택 동의 `photoAnalysis`(1-1~1-3, 1-6)로 받는다. 동의하지 않은 계정의 사진은 분석하지 않고, 동의를 거두면 저장된 AI 설명을 지운다([1-6](#1-6-patch-authmeconsents--신규), 2026-11-09 PM 결정). 사진 보관 동의를 따로 받는 필드와 API는 아직 없다.

### 3-1. `POST /api/v1/profiles/{profileId}/photos` — 신규

온보딩의 사진 첨부와 마이페이지의 갤러리 추가에서 호출한다.

요청 `multipart/form-data`

| 필드 | 값 |
| --- | --- |
| `image` | JPEG 또는 PNG. 서버 설정의 크기 상한(기본 20MB) 이하 |

응답 `201` — [ProfilePhoto](#profilephoto), `analysisStatus`는 `pending`

- 프로필당 최대 5장이다.
- 서버는 분석 작업(8-4)을 만든다.
- 세션 서명과 본문 크기는 본문을 받기 전에 확인한다([본문 크기와 확인 순서](#본문-크기와-확인-순서)).

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

<a id="3-3-앨범에서-사진-설명-수정--api-미정"></a>

### 3-3. `PATCH /api/v1/profile-photos/{photoId}/description` — 사진 설명 수정

9월 23일 회의와 10월 6일 BE 논의에서 정한 대로, AI 사진 설명은 별도 승인 없이 카드 생성에 사용한다. 사용자는 원할 때 앨범에서 확인하거나 수정한다. 사진 등록과 카드 선택에 필수 확인 단계를 넣지 않으며, 수정 API가 정해지기 전이라는 이유로 설명 사용을 막지 않는다.

사진 설명을 질문의 입력으로 쓰는 것과 승인된 생애 사실을 저장하는 것은 다르다. 사진 설명이나 카드 선택만으로 `life_facts`에 저장하지 않는다. 사진 분석 동의도 별도로 확인한다. 기존 결정을 확인한 [PR #97 의견](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/97#discussion_r4183313066), [상세 흐름](card-generation-flow.md#4-사진-설명은-바로-사용하고-앨범에서-선택적으로-수정)을 참고한다.

요청은 `{"description": "보호자가 고친 사진 설명"}`이다. 비어 있거나 공백뿐인 설명은 422로 거절한다. 소유 계정의 프로필 사진만 수정할 수 있으며 면회 사진과 다른 계정 사진은 404다.

성공 응답은 200이며 `schemaVersion`, `photoId`, 저장한 `description`, `descriptionSource: "caregiver"`, `updatedAt`을 돌려준다. 이 저장 API는 S3 주소 발급을 호출하지 않는다.

AI 설명은 `photos.description`, 보호자가 고친 값은 `user_description`에 따로 둔다. 조회와 다음 카드 입력에서는 보호자 설명을 우선한다. AI 분석 상태와 모델 기록은 바꾸지 않으며 늦게 도착한 AI 결과도 보호자 설명을 덮지 않는다. 2-3, 3-1, 3-2의 `ProfilePhoto`에는 선택 필드 `descriptionSource`를 추가한다(`ai`, `caregiver`, 설명 없으면 `null`). AI 분석에 실패했어도 보호자 설명은 조회할 수 있다.

설명이 바뀌면 기존 정정 처리처럼 미사용 카드 묶음에 `needsRefresh`를 표시한다. 수정할 때마다 생성하지 않고 다음 대화 준비에서 12장을 다시 만든다. 카드 생성 중이면 409 `CARD_GENERATION_IN_PROGRESS`이며 설명을 부분 저장하지 않는다. 앱은 입력을 남기고 카드 준비 후 다시 저장할 수 있게 한다. 별도 승인 여부나 사진 메타데이터를 새로 요구하지 않는다.

<br>

---

### 3-4. `DELETE /api/v1/profile-photos/{photoId}` — 신규

앨범에서 프로필 사진 한 장을 지운다. 면회 사진(5-2)은 대상이 아니다.

본문 없음.

응답 `204`

- 사진 행을 지우고 S3 원본은 삭제 대기열로 지운다(`photos_queue_storage_deletion` 트리거).
- 사진은 카드 생성 자료가 될 수 있으므로 이야기 삭제(2-9)처럼 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 된다. 이미 만든 카드와 면회 기록은 남는다.
- 카드를 만드는 중이면 409로 거절한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_PHOTO_NOT_FOUND`(다른 계정의 사진, 면회 사진 포함) |
| 409 | `CARD_GENERATION_IN_PROGRESS` |

## 4. 대화 카드

### 사실 정정 후 카드 갱신 기준

생성 시점은 [PM 기준](../pm/README.md#사실-정정과-다음-면회-카드-반영)을 따른다. 정정은 즉시 저장하고 영향받은 카드의 사용을 중지한다. 매번 재생성하지 않고 ‘다음 대화 준비’에서 누적 정정을 반영해 카드 묶음 전체를 한 번 재생성한다. 완료 후 카드 선택과 대화 시작을 허용한다.

2026-10-16 [PM 기준](../pm/README.md#사실-정정과-다음-면회-카드-반영): 정정으로 사용 중지한 카드는 대화 평가의 미사용과 구분하며 추천 불이익을 주지 않는다.

BE 구현(#158)은 묶음 단위로 처리한다.

- 2-4, 2-7, 2-9로 카드 생성에 쓰는 값을 바꾸면 아직 면회에 안 쓴 완료 묶음에 고친 시각(`card_sets.stale_at`)을 남긴다. 2-4는 생년월일, 직업, 고향, 취미, 가족이고 2-7은 제목과 내용이다. 이름, 성별, 인지 상태, 이야기 분류와 그림 번호는 카드 생성에 쓰지 않아서 남기지 않는다. 2-9는 항상 남긴다.
- 7-4(변경 사항 확인)는 주제 제안을 하나라도 승인하면 남긴다. 승인한 주제 피드백(`more`, `less`, `exclude`)이 다음 카드 생성에서 주제를 고르는 기준을 바꾸기 때문이다. 생애 정보 제안 승인은 이야기 추가(2-6)와 같아서 남기지 않고 다음 생성부터 반영한다. 모두 거절한 확인도 남기지 않는다.
- 1-6에서 AI 사진 분석 동의를 거둬 보호자 설명이 없는 사진의 AI 설명이 지워진 프로필도 남긴다. 동의 변경은 카드를 만드는 중이어도 거절하지 않는다. 만드는 중인 묶음은 저장할 때 입력 뒤 사진 설명이 바뀐 것을 보고 남긴다.
- 면회에 쓴 묶음은 지난 기록이라 남기지 않는다.
- `stale_at`이 있는 묶음은 4-2, 4-3에서 `status`가 그대로 `ready`이고 `needsRefresh`가 `true`다. 4-1은 이 묶음을 거절하지 않고 새로 만들며, 5-1은 `CARD_SET_NEEDS_REFRESH`로 거절한다.
- 카드를 만드는 중(`running`)에 이 값들을 고치면 2-4, 2-7, 2-9가 `CARD_GENERATION_IN_PROGRESS`로 거절한다. 주제 제안 승인이 있는 7-4도 같다. worker가 고치기 전 내용으로 만든 묶음이 `needsRefresh` 표시 없이 나올 수 있어서다. 예를 들어 방금 제외한 주제가 그 묶음에 다시 들어갈 수 있다.
- 카드 한 장 단위의 사용 중지 표시는 다루지 않는다.

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

`ready`인데 `needsRefresh`가 `true`이면 카드를 받은 뒤 프로필이나 일대기를 고쳤거나 변경 사항에서 주제 결정을 반영했다는 뜻이다(7-4). 카드는 4-3으로 볼 수 있지만 면회는 시작할 수 없고, 버튼을 누르면 4-1로 다시 만든다. 4-1을 부르면 상태가 `running`이 되므로 새 묶음이 나올 때까지 4-3은 `CARD_GENERATION_NOT_FOUND`이고, 다시 만들기가 실패하면 `failed`가 되어 예전 카드도 볼 수 없다.

4-1과 4-2는 상태를 보기 전에 더는 끝나지 않을 `running` 작업을 `failed`로 바꾼다. 임대 만료 정리는 원래 worker가 하므로, worker가 없거나 멈추면 작업이 `running`으로 남아 앱이 다시 요청할 수 없기 때문이다.

- `CARD_GENERATION_NOT_STARTED`: worker가 가져가지 않은 채 `SAEROK_CARD_GENERATION_START_TIMEOUT_SECONDS`(기본 360초)가 지났고, 같은 시간 동안 worker가 다른 작업도 가져가지 않았으며 처리 중인 작업도 없다. worker가 없거나 멈춘 경우다.
- `WORKER_LEASE_EXPIRED`: worker가 가져간 작업의 임대가 만료됐다.

worker가 다른 계정의 작업을 차례로 처리하는 동안에는 오래 기다린 작업도 실패시키지 않는다. 앞에 기다리는 작업이 많으면 `running`이 360초보다 길게 이어질 수 있다. 판단에는 worker가 작업을 가져간 시각(`card_sets.claimed_at`)을 쓰며 응답 형식은 바뀌지 않는다.

### 4-1. `POST /api/v1/profiles/{profileId}/card-generations` — 신규

카드를 만들어 달라고 요청한다. 작업만 만들고 바로 끝난다.

호출 시점

- 온보딩의 `마치기`(2-4 다음)
- 홈에서 `오늘의 대화카드 받기`를 눌렀을 때(4-2 `status`가 `none`이나 `failed`)
- 4-2가 `ready`이고 `needsRefresh`가 `true`일 때 다시 만들기

응답 `202`

```json
{ "schemaVersion": 1, "status": "running", "needsRefresh": false }
```

- 이미 만드는 중이면 새로 만들지 않고 같은 응답을 준다.
- 평가 전 회차가 지금 묶음을 쓰는 중(`inVisit`)이면 409로 거절한다. 새 묶음이 생기면 면회 중인 카드를 4-3으로 받을 수 없게 되기 때문이다.
- 아직 쓰지 않은 묶음이 있으면(`ready`) 409로 거절한다. 그래서 회차에 쓸 수 있는 완료 묶음은 늘 가장 최근 묶음 하나뿐이고, 5-1이 받는 묶음이 4-2, 4-3이 보는 묶음과 같다. `needsRefresh`가 `true`인 묶음은 거절하지 않고 새로 만든다. 그 묶음은 5-1이 받지 않으므로 회차에 쓸 수 있는 묶음은 여전히 하나뿐이다.
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
- `ageRange`: BE가 생년월일로 계산한 `{십 단위 나이}s` (예: `70s`, `80s`). 이름, 성별, 생년월일, 인지 상태, 증상 메모는 넣지 않는다. 카드 생성은 `10s` 이상만 받으므로 2-2, 2-4가 만 10세가 안 된 생년월일을 저장하지 않는다. 그 검사 전에 저장된 프로필은 고치기 전까지 `INVALID_CONTEXT`로 실패한다.
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
- 저장 트랜잭션은 프로필과 작업 행을 잠근 뒤 임대가 남은 `running` 작업일 때만 저장한다. 생성하는 동안 임대 시각이 지났으면 임대 만료 정리가 아직 돌지 않았어도 결과를 버리고 새 주제와 카드를 하나도 저장하지 않으며, 작업을 `WORKER_LEASE_EXPIRED`로 실패시킨다.
- 임대 시각이 지난 뒤 온 생성 실패와 검증 실패도 그 코드 대신 `WORKER_LEASE_EXPIRED`로 남긴다. 이미 `failed`나 `completed`가 된 작업은 늦게 온 결과나 실패가 바꾸지 않는다.

실패

| `errorCode` | 뜻 |
| --- | --- |
| `INVALID_CONTEXT` | 입력 형식이 맞지 않거나 모르는 `promptVersion` |
| `NOT_ENOUGH_TOPICS` | 다시 찾아도 서로 다른 주제로 12장을 채우지 못함 |
| `TEXT_CHECK_FAILED` | 문안이 금지 표현 검사(최근 기억 확인, 의료 표현)에 두 번 걸림 |
| `LLM_UNAVAILABLE` | 엘리스 API 연결 실패, 시간 초과, 호출 한도 |
| `CARD_GENERATION_FAILED` | 그 밖의 실패 |
| `INVALID_GENERATION_RESULT` | 결과가 위 검증에 맞지 않음(BE가 판단) |
| `CARD_GENERATION_NOT_STARTED` | 정해진 시간이 지나도 worker가 작업을 가져가지 않았고, 그동안 다른 작업도 가져가지 않음. worker가 없거나 멈춤(4절) |
| `WORKER_LEASE_EXPIRED` | worker가 임대 시간 안에 작업을 끝내지 못함 |


### 4-2. `GET /api/v1/profiles/{profileId}/card-generations/status` — 신규

홈 버튼 상태다. `running`이면 폴링한다.

응답 `200`

```json
{ "schemaVersion": 1, "status": "ready", "needsRefresh": false }
```

- `status`: `none`, `running`, `ready`, `inVisit`, `failed`(4절 표). 프로필의 가장 최근 작업으로 정한다.
- `needsRefresh`: `ready`인 묶음을 받은 뒤 프로필이나 일대기를 고쳤거나 변경 사항에서 주제 결정을 반영했으면(7-4) `true`. 다른 상태에서는 늘 `false`다.
- 작업이 없어도 오류가 아니라 `none`이다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |

### 4-3. `GET /api/v1/profiles/{profileId}/card-generations/current` — 신규

지금 쓸 카드 묶음이다. 4-2가 `ready`(고르기 전)나 `inVisit`(면회 시작은 했고, 평가 전)일 때 그 묶음을 준다. 카드 고르기, 면회 중, 중간에 나갔다 돌아온 경우 모두 같은 카드를 받는다. 평가(6-1)를 마치면 더는 나오지 않는다.

응답 `200` — [CardSet](#cardset)

- `position` 1~9는 선택 화면용, 10~12는 면회 중 보충용이다.
- `needsRefresh`가 `true`인 묶음도 준다. 이 묶음은 볼 수만 있고 5-1로 면회를 시작할 수 없다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND`, `CARD_GENERATION_NOT_FOUND`(쓸 묶음이 없음) |

### 4-4. `GET /api/v1/visit-sessions/{sessionId}/card-set` — 신규

회차에 쓴 카드 묶음이다. 평가를 마쳐 4-3에서 더는 나오지 않는 묶음도 보호자가 다시 볼 수 있게 한다. 평가 전 회차면 4-3과 같은 묶음을 준다.

응답 `200` — [CardSet](#cardset)

- 읽기만 한다. 이 묶음으로 면회를 다시 시작하지 않으며, 회차에 쓸 수 있는 묶음은 여전히 4-3의 가장 최근 묶음 하나뿐이다.
- `usedBySessionId`는 요청한 `sessionId`다. `selected`는 그 회차에서 고르거나 보충한 카드다.
- 카드와 근거는 저장된 그대로 준다. 이후 정정되거나 지워진 생애 정보를 반영하지 않는다. 정정 표시는 PM 결정 뒤 정한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `CARD_GENERATION_NOT_FOUND`(회차에 쓴 묶음이 없음) |

### 4-5. `PUT /api/v1/cards/{cardId}/like` — 신규

보호자가 지난 카드를 다시 보며 마음에 드는 카드에 "좋았어요"를 표시한다. 모든 카드를 평가하게 하지 않고 원하는 카드에만 선택적으로 남긴다. 본문 없음.

응답 `204`

- 보호자 평가(6-1)와 따로 저장한다(`conversation_cards.liked_at`). 6-1의 `cardReviews`, 리포트(7-2)와 회차 상태는 바꾸지 않는다. 평가를 마친 뒤에도 표시할 수 있다.
- 회차에서 고르지 않은 카드에도 표시할 수 있다. 서버는 카드의 회차 상태로 막지 않으며, 표시 버튼을 어느 화면에 둘지는 FE와 PM이 정한다.
- 이미 표시한 카드면 아무것도 바꾸지 않고 `204`다. 처음 표시한 시각을 유지한다.
- 표시는 [CardSet](#cardset)의 `liked`로 확인한다.
- 다음 카드 생성(4-1)의 `context`에는 아직 넣지 않는다. 대화 주제 추천에 반영하는 방식은 AI 담당과 정한 뒤 별도 작업으로 연결한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_NOT_FOUND` |

### 4-6. `DELETE /api/v1/cards/{cardId}/like` — 신규

4-5의 표시를 지운다. 본문 없음.

응답 `204`

- 표시하지 않은 카드여도 `204`다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `CARD_NOT_FOUND` |

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
| 409 | `CARD_GENERATION_NOT_COMPLETED`, `CARD_SET_ALREADY_USED`, `CARD_SET_NEEDS_REFRESH`(묶음을 받은 뒤 프로필이나 일대기를 고침. 4-1로 새 묶음을 만들어야 함) |
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
- 세션 서명과 본문 크기는 본문을 받기 전에 확인한다([본문 크기와 확인 순서](#본문-크기와-확인-순서)).

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

- 보호자 평가를 제출한 회차만 받는다. 평가 전이면 `EVALUATION_REQUIRED`
- 업로드 실패 또는 접수 후 분석 실패라도 유효한 전사가 남아 있지 않으면 새 작업을 만든다. 6-5 재요청 횟수를 모두 쓴 회차도 같으며, 이 제출은 재요청 횟수에 넣지 않는다.
- 유효한 전사가 남은 실패 작업은 `REPORT_RETRY_AVAILABLE`로 6-5 사용을 안내한다.
- 접수된 작업이 처리 중이면 그 작업을 `202`로 반환한다.
- 완료한 회차는 다시 받지 않는다.
- 앱은 `202`를 받아도 단말 WAV와 회차 연결을 남긴다. 실패 후 재전송에 사용한다.
- 세션 서명과 본문 크기는 본문을 받기 전에 확인한다([본문 크기와 확인 순서](#본문-크기와-확인-순서)).

| HTTP | `errorCode` |
| --- | --- |
| 403 | `SPEECH_PROCESSING_CONSENT_REQUIRED` |
| 404 | `VISIT_SESSION_NOT_FOUND` |
| 409 | `EVALUATION_REQUIRED`, `ANALYSIS_SUBMISSION_IN_PROGRESS`, `REPORT_RETRY_AVAILABLE`, `ANALYSIS_ALREADY_COMPLETED` |
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

### 6-6. `POST /api/v1/speech-transcriptions` — 프로필 입력용 전사

인증된 계정이 multipart의 `audio` 파일 하나를 보낸다. 프로필과 회차 ID는 받지 않는다.
WAV/PCM 16-bit/16kHz/mono, 최대 5분이다. 응답은 `200`과
`{"schemaVersion": 1, "text": "..."}`이며 인식 결과가 비었으면 `text`도 빈 문자열이다.

입력 오류와 동시 요청 거절은 아래 표와 같다. STT와 저장소 오류는 6-2와 같은 오류 코드를 사용하며 클라이언트는 `retryable`을 읽는다.
세션 서명과 본문 크기는 본문을 받기 전에 확인한다([본문 크기와 확인 순서](#본문-크기와-확인-순서)).

같은 계정의 6-6은 동시에 2건(서버 설정 `SAEROK_SHORT_TRANSCRIPTION_CONCURRENCY_PER_ACCOUNT`)까지
처리한다. 앱은 전사 중에도 `건너뛰기`로 다음 항목을 녹음해 보낼 수 있으므로, 앞 전사 하나가 남아
있어도 다음 녹음은 받는다. 이미 2건이 처리 중일 때 온 요청은 S3 저장과 STT 호출 없이
`SPEECH_TRANSCRIPTION_IN_PROGRESS` 429(`retryable: true`)로 거절한다. 앞 요청이 끝나면 다시 보낼
수 있다. 다른 계정의 요청은 기다리지 않는다(2026-11-09 PM 결정).

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 403 | `SPEECH_PROCESSING_CONSENT_REQUIRED` | 필수 동의 누락 |
| 413 | `AUDIO_TOO_LARGE` | 크기 또는 5분 초과 |
| 422 | `INVALID_AUDIO_FORMAT`, `INVALID_AUDIO` | 형식이 다르거나 손상됨 |
| 429 | `SPEECH_TRANSCRIPTION_IN_PROGRESS` | 같은 계정의 6-6이 이미 2건 처리 중 |

원본은 S3에 암호화해 임시 저장하고 요청이 끝나면 삭제를 시도한다. 삭제 대기열에 키를
먼저 기록하며 처리 중 조기 삭제를 막는다. 전사 결과는 DB와 로그에 남기지 않는다.
삭제 실패가 전사 성공을 취소하지 않는다. 큐 실행과 Lifecycle만으로 정확한 24시간 이내 삭제를
보장한다고 설명하지 않는다. 처리 시간과 오류 코드 선택의 남은 확인은
[프로필 음성 입력](../../backend/docs/short-speech-transcription.md)을 따른다.

<br>

---

### 6-5. `POST /api/v1/speech-analyses/{analysisId}/retry` — 신규

실패한 작업에 유효한 전사가 남아 있으면 STT를 다시 호출하지 않고 리포트만 요청한다.
기존 작업을 되살리지 않고 새 `analysisId`를 발급한다. 전사 만료 시각은 연장하지 않는다.
동시에 여러 요청이 와도 회차당 작업 하나만 접수한다. 자동 반복 요청은 하지 않는다.
재요청은 면회 회차당 3회(서버 설정 `SAEROK_REPORT_RETRIES_PER_SESSION`)까지 접수한다. 횟수는 남은
전사를 다시 쓸 때만 적용한다. 횟수를 모두 썼고 전사가 남아 있으면 새 작업을 만들지 않고
`REPORT_RETRY_LIMIT_EXCEEDED`로 거절한다. 전사가 없거나 기한이 지났으면 횟수와 관계없이
`RECORDING_REQUIRED`이므로, 앱이 기기 녹음을 6-2로 다시 보내 그 회차의 리포트를 받을 수 있다.
6-2로 다시 낸 녹음과, 처리 중인 재요청을 다시 보내 같은 작업을 돌려받는 경우는 횟수에 넣지
않는다(2026-11-09 PM 결정).

응답 `202`: 6-2와 같은 객체. 새 작업의 초기 `status`는 `sttCompleted`다.
이미 접수된 재시도가 처리 중이면 해당 ID와 현재 상태를 반환한다.
worker는 남은 전사 기한이 리포트 생성 단계 임대 시간(기본 900초) 이상일 때만 새 작업의
생성을 시작한다. 그보다 적게 남았으면 생성하지 않고 전사를 지워 작업을 `failed`(`TRANSCRIPT_EXPIRED`)로
끝내므로, 이 작업 ID로 다시 요청하면 회차의 재요청 횟수와 관계없이 `RECORDING_REQUIRED`다.

서버는 아래 순서로 확인하고 처음 걸린 오류를 돌려준다.

1. 필수 동의가 없으면 `SPEECH_PROCESSING_CONSENT_REQUIRED`, 이 계정의 작업이 아니면 `SPEECH_ANALYSIS_NOT_FOUND`.
2. 회차에 끝나지 않은 작업이 있으면 업로드 중은 `ANALYSIS_SUBMISSION_IN_PROGRESS`, 완료는 `ANALYSIS_ALREADY_COMPLETED`, 처리 중은 그 작업을 `202`로 반환.
3. 이 작업 ID로 이미 재요청했으면 `ANALYSIS_ALREADY_FAILED`.
4. 다시 쓸 전사가 없거나 기한이 지났으면 `RECORDING_REQUIRED`.
5. 회차의 재요청 횟수를 모두 썼으면 `REPORT_RETRY_LIMIT_EXCEEDED`.

| HTTP | errorCode | 처리 |
| --- | --- | --- |
| 403 | `SPEECH_PROCESSING_CONSENT_REQUIRED` | 재전송으로 우회하지 않고 동의 상태 확인 |
| 404 | `SPEECH_ANALYSIS_NOT_FOUND` | 다른 계정 또는 없는 작업 |
| 409 | `ANALYSIS_SUBMISSION_IN_PROGRESS` | 녹음 업로드가 아직 끝나지 않음 |
| 409 | `ANALYSIS_ALREADY_COMPLETED` | 완료한 리포트 조회 |
| 409 | `ANALYSIS_ALREADY_FAILED` | 해당 ID의 재요청도 이미 실패함. 5-4에서 최신 ID를 확인 |
| 409 | `RECORDING_REQUIRED` | 유효한 전사가 없으므로 기기 녹음을 6-2로 제출. 재요청 횟수를 모두 쓴 회차도 같음 |
| 409 | `REPORT_RETRY_LIMIT_EXCEEDED` | 횟수를 모두 썼고 전사가 남아 있음. 바로 다시 요청하지 않음. 전사 기한(최초 STT부터 24시간)이 지나면 같은 요청이 `RECORDING_REQUIRED`가 되어 녹음을 다시 보낼 수 있음 |

전사와 기기 녹음이 모두 없으면 해당 회차의 리포트를 새로 만들지 않는다. 면회 기록과 소감은 유지한다.

## 7. 리포트와 변경 제안

리포트는 회차에 저장하며 회차 ID로 조회한다. 변경 제안은 생애 정보 제안과 주제 제안 두 가지이며 회차마다 0개 이상이다. 리포트 확인 여부는 저장하지 않는다([미정 사항](#미정-사항) 2). 앱은 확인할 제안이 없는 리포트를 리포트(7-2)와 제안(7-3)을 모두 읽으면 확인한 것으로 보고 홈 도착 알림을 지운다. 이 기록은 앱이 켜져 있는 동안만 남는다.

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
      "mood": "good",
      "photo": {
        "photoId": "00000000-0000-4000-8000-000000000221",
        "imageUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/visit.jpg?...",
        "imageUrlExpiresAt": "2026-08-21T15:00:00+09:00"
      }
    }
  ]
}
```

- `photo`: 면회 사진이 없으면 `null`. 형식은 [VisitReport](#visitreport)의 `photo`와 같다.
- 면회 사진의 조회 URL을 만들지 못하면 목록 전체를 실패시키지 않고 그 항목만 `photo: null`로 담는다. 7-2는 같은 경우 `503`이다.

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
  - `lifeFacts[].title`, `content`: 생애 정보로 만들 최종 제목과 내용. 고치지 않았으면 제안 값을 그대로 보낸다. 2-6과 같이 `title`은 100자, `content`는 5,000자 이하이고 둘 다 비울 수 없다. 제안 값이 이 길이를 넘으면 보호자가 줄여서 보내야 한다.
  - `topics[].action`: `more`, `less`, `exclude`. 보호자가 고른 행동이며 제안의 `suggestedAction`과 달라도 된다. 바꾸지 않았으면 제안 값을 그대로 보낸다.
- `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- 제안이 없는 회차의 확인 처리는 미정([미정 사항](#미정-사항) 2)

응답 `200` — [ChangeProposal](#changeproposal)

서버 처리

- 모든 제안을 `settled`로 바꾼다.
- `accepted`인 생애 정보 제안은 요청의 `title`, `content`로 생애 정보를 만든다. 생애 정보의 `source_proposal_id`가 그 제안이다. 제안(`life_fact_proposals`)의 `title`, `content`, `reason`은 바꾸지 않는다.
- `accepted`인 주제 제안은 요청의 `action`을 `topic_feedback.action`에 기록하고 다음 카드 생성(4-1)의 `topics`에 반영한다. 제안의 `suggested_action`은 바꾸지 않는다.
- `rejected` 항목은 반영하지 않는다.
- `accepted` 주제 항목이 하나라도 있으면 다음 카드 생성에서 주제를 고르는 기준이 바뀐다. 2-4, 2-7, 2-9와 같이 프로필을 잠그고, 카드를 만드는 중이면 `CARD_GENERATION_IN_PROGRESS`로 거절하며 아무것도 저장하지 않는다. 만드는 중이 아니면 아직 면회에 안 쓴 완료 묶음은 `needsRefresh`가 `true`가 된다([4절](#사실-정정-후-카드-갱신-기준)). 카드 생성이 끝난 뒤 같은 요청을 다시 보내면 된다. 생애 정보만 승인한 확인은 이야기 추가(2-6)처럼 거절하지도 표시하지도 않는다.
- 모두 `rejected`인 요청(`반영하지 않고 마치기`)은 카드 생성 입력을 바꾸지 않는다. 카드를 만드는 중에도 받고 `needsRefresh`를 바꾸지 않는다.
- `accepted`인 생애 정보 제안을 더해 프로필의 이야기가 300개(2-6과 같은 상한)를 넘으면 `LIFE_FACT_LIMIT_EXCEEDED`로 거절하고 제안 정리와 주제 피드백을 포함해 아무것도 저장하지 않는다. 일대기에서 이야기를 지우거나 일부 제안을 `rejected`로 바꿔 다시 보낸다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `REPORT_NOT_FOUND` | |
| 409 | `PROPOSAL_ALREADY_REVIEWED` | 이미 `settled`인 제안이 있음 |
| 409 | `CARD_GENERATION_IN_PROGRESS` | `accepted` 주제 항목이 있는데 카드를 만드는 중(4-2 `running`). 404, `PROPOSAL_ALREADY_REVIEWED`, 422 검사가 먼저다 |
| 409 | `LIFE_FACT_LIMIT_EXCEEDED` | `accepted` 생애 정보 제안을 더하면 프로필의 이야기가 300개를 넘음. 404, 위 두 409, 422 검사가 먼저다 |
| 422 | `INVALID_PROPOSAL_REVIEW` | `pending` 제안이 빠졌거나 다른 회차의 제안 |
| 422 | `INVALID_REQUEST` | `accepted` 항목에 최종 값(`title`과 `content`, 또는 `action`)이 없거나 `rejected` 항목에 있음. 최종 `title`이 100자, `content`가 5,000자를 넘음 |

<br>

---

## 8. 내부 API (백엔드 → AI 서버)

백엔드 worker가 동기 호출한다. 앱은 호출하지 않는다. 원본 파일은 수명이 짧은 S3 Presigned GET URL로만 전달한다. 피보호자의 이름, 성별, 생년월일은 어떤 요청에도 넣지 않는다.

AI 서버 호출이 실패하면 해당 작업을 `failed`로 바꾸고 다음 `errorCode`를 남긴다: `AI_SERVER_TIMEOUT`, `AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `INVALID_AI_RESPONSE`. worker가 임대 시간 안에 작업을 끝내지 못하면 `WORKER_LEASE_EXPIRED`다. 자동으로 다시 시도하지 않는다. 8-3(함수 호출)에서는 리포트 생성 전체 제한 시간을 넘으면 `AI_SERVER_TIMEOUT`이고, 생성 중 임대가 끝나면 늦게 온 결과를 저장하지 않고 `WORKER_LEASE_EXPIRED`다. 남은 전사 기한이 생성 단계 임대 시간보다 짧아 생성을 시작할 수 없거나, 변경 제안 호출 직전에 전사 기한이 지났으면 `TRANSCRIPT_EXPIRED`다.

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

worker 처리 순서: 8-1 → 전사문 임시 저장(`sttCompleted`) → 원본 삭제 요청 기록과 S3 삭제 시도 → 8-3 → 리포트와 변경 제안 저장, 전사문 삭제 → 작업 `completed`

8-3 시작 전에 worker가 멈추면 작업은 `sttCompleted`로 남는다. 전사 저장 때 기록한 인계 임대(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`, 기본 900초)가 끝나면 다음 worker가 같은 작업과 저장된 전사로 8-3부터 이어 간다. 8-1과 S3 다운로드는 반복하지 않고, 원본 삭제 기록이 없으면 삭제 요청을 대기열에 남긴다. 이어받기는 작업마다 한 번이며 실패한 작업이나 남은 전사 기한이 생성 단계 임대 시간보다 짧은 작업은 이어받지 않는다. `--stt-only`로 멈춘 작업도 이어받지 않는다.

S3 삭제만 실패한 경우에는 삭제 요청을 대기열에 남기고 리포트 생성을 계속한다. `audio_deleted_at`은 삭제 성공 뒤에만 기록하며, 분석 완료와 원본 삭제 완료를 구분한다.

- 전사문은 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업(`speech_analysis_jobs.transcript`)에 임시 저장한다. 최초 STT 저장 시각부터 24시간을 `transcript_expires_at`으로 정하며, 리포트 저장이 먼저 완료되면 지운다. 실패 전사는 남은 기한 동안 유지하며 재시도로 기한을 늘리지 않는다(2026-11-03 PM 승인). 만료 전사의 재사용은 거절하고 worker 정리 시 전사를 삭제하며 `failed`와 `TRANSCRIPT_EXPIRED`로 기록한다. worker 중단이나 긴 처리 중에는 실제 정리가 늦어질 수 있다([보관 대조](../../backend/docs/speech-recovery.md#실패-전사와-기기-녹음의-보관-대조)).
- 8-3(전사문의 외부 ML 전송)은 남은 전사 기한이 생성 단계 임대 시간(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`, 기본 900초) 이상일 때만 시작한다. 임대는 생성 제한 시간보다 60초 이상 길어 시작한 생성이 기한을 넘겨 새 외부 호출을 하지 않는다. 기한이 그보다 적게 남은 `sttCompleted` 작업은 시작하지 않고 worker 정리 시 `failed`와 `TRANSCRIPT_EXPIRED`로 끝낸다([외부 ML 전송과 기한](../../backend/docs/speech-recovery.md#외부-ml-전송과-기한)).
- 전사문은 화면에 표시하지 않고 8-3 요청에만 사용한다.

8-1이 성공해도 발화 구간이 없거나 공백뿐이면 `EMPTY_TRANSCRIPT`로 끝내고 8-3을 호출하지 않는다.

화자 라벨이 누락되거나 라벨 수가 예상 인원보다 적어도 리포트와 변경 제안 모델을 호출한다.
화자 미확인 고정 안내로 대체하지 않으며, 라벨 상태만으로 생성 결과의 저장을 거절하지 않는다.
빈 전사 검사, 응답 검증, 시간 제한과 작업 임대 확인은 유지한다.
라벨은 실제 인물 역할의 증명이 아니므로 프롬프트는 대화 맥락을 참고하고 불확실한 후보의 제안 이유에 확인 필요를 적도록 지시한다.
보호자의 제안 확인 절차는 유지한다. [화자와 리포트 생성](../../backend/docs/speaker-fact-boundary.md)을 참고한다.
8-3 요청의 선택 항목 `participantCount`는 해당 분석 작업의 예상 참여 인원이다. 생략되면 미확인으로 다룬다.
실제 화자 수나 보호자와 어르신의 역할을 검증한 값이 아니다. [전사 입력 검사](../../backend/docs/speech-input-safety.md)를 참고한다.

### 8-2. 카드 생성 — 삭제

AI 서버를 거치지 않으므로 4-1의 처리 과정으로 옮겼다([4-1 카드 생성 처리](#4-1-카드-생성-처리)).

### 8-3. `POST /internal/v1/visit-reports` — 신규

전송 방식([PR #123](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/123)): AI 서버의 HTTP 경로가 아니라 음성 worker가 `ai/`의 `report_generation.generate_report`와 `proposal_generation.generate_proposals`를 차례로 부르고 `common.visit_report.combine`으로 합친다. 아래 요청과 응답 JSON, BE 검증, 오류 코드는 그대로다. 생성 함수 안에서 전사문을 포함한 요청이 외부 ML API로 전송된다. 생성 함수의 `LLM_UNAVAILABLE`은 `AI_SERVER_UNAVAILABLE`, `GENERATION_FAILED`와 `INVALID_REQUEST`는 `AI_SERVER_ERROR`, 결과 형식 오류는 `INVALID_AI_RESPONSE`로 남긴다. 요청 조립부터 검증까지 전체 제한 시간(`SAEROK_REPORT_GENERATION_TIME_LIMIT_SECONDS`, 기본 600초, 작업 임대보다 60초 이상 짧게)을 넘으면 `AI_SERVER_TIMEOUT`이다. 변경 제안 호출(전사문의 두 번째 외부 전송) 직전에는 작업 행을 다시 읽어, 행이 없거나(계정, 프로필, 회차 삭제) 임대가 남은 `generatingReport`가 아니면 `WORKER_LEASE_EXPIRED`, 전사가 지워졌거나 기한이 지났으면 `TRANSCRIPT_EXPIRED`로 멈추고 호출하지 않는다. 리포트 저장과 작업 `completed`는 한 트랜잭션이며, 임대가 남은 `generatingReport` 작업일 때만 저장한다.

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

아래는 내부 계약이다. 로컬 worker는 리포트와 같은 방식으로 `ai/photo_analysis` 함수를 직접 호출하며 이 HTTP 경로를 공개하지 않는다. 합성 사진용 연결과 운영 적용 조건은 [사진 분석 실행 문서](../../backend/docs/photo-analysis.md)를 따른다.

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

4-3, 4-4의 응답이다. 4-3은 고르기 전이거나 평가 전 회차에 쓰는 중인 카드 묶음, 4-4는 회차에 쓴 카드 묶음이다.

```json
{
  "schemaVersion": 1,
  "setId": "00000000-0000-4000-8000-000000000401",
  "usedBySessionId": null,
  "needsRefresh": false,
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
      "selected": false,
      "liked": false
    }
  ]
}
```

- `setId`: 녹음을 시작할 때 5-1에 보낸다.
- `usedBySessionId`: 이 묶음을 쓰는 평가 전 회차. 고르기 전이면 `null`. 앱을 다시 켰을 때 이 값으로 5-2, 5-3을 부른다. 4-4에서는 요청한 회차이며 평가가 끝난 회차일 수 있다.
- `needsRefresh`: 이 묶음을 받은 뒤 프로필이나 일대기를 고쳤거나 변경 사항에서 주제 결정을 반영했으면(7-4) `true`. 이 묶음으로는 5-1을 부를 수 없다(4절).
- `cards`: 12장. 회차에서 고른 카드와 더한 보충 카드는 `selected`가 `true`다.
- `liked`: 보호자가 4-5로 "좋았어요"를 표시한 카드면 `true`. 4-6으로 지우면 `false`다.
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
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 7-4가 없어 확인했는지 알 수 없음. 앱은 리포트와 제안을 모두 읽으면 확인한 것으로 보고 홈 알림을 지우며, 앱을 다시 켜면 다시 뜬다(#235). 서버 저장은 #236 | 4-1 호출 시점, 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 3 | 사진 보관과 AI 분석은 가입 화면의 별도 선택 항목으로 받고 계정별 이력에 저장하기로 PM 결정 완료(2026-10-14). 유효한 동의는 재요청하지 않으며 미동의자는 기능 사용 시 요청. AI 분석 동의는 `photoAnalysis` 항목으로 가입, 조회, 변경 API(1-1~1-3, 1-6)와 화면에 반영했고, 미동의 계정의 사진은 분석하지 않으며, 동의를 거두면 저장된 AI 설명을 지운다(2026-11-09). 남은 것은 사진 보관 동의를 따로 받는 필드와 API | 1-1~1-3, 1-6, 3-1, 5-2, 8-4 | FE, BE, AI. 기존 동의 범위를 바꾸는 경우 PM 확인 |
| 7 | 사진 삭제와 보관 동의 철회 동선 및 API 형태. DB 삭제 대기열 등록 이후 S3 실제 삭제와 결과 확인은 미구현 | 3절 | FE, BE, PM |
| 8 | 카드 생성이나 음성 분석이 처리 중인 프로필 또는 계정을 지울 때의 처리. 삭제를 허용하고 worker가 사라진 행을 건너뛸지, 처리 중에는 409로 막을지 | 1-5, 2-8 | BE |
| 9 | 입력 중(`inProgress`)인 프로필만 있을 때 로그인 직후 그 프로필의 입력을 이어서 할지, 홈으로 갈지 | 2-1, 호출 순서 | FE, BE |
| 10 | 검토 뒤 ChangeProposal 응답에 보호자가 고른 행동과 고친 생애 정보를 담을지. 지금은 원래 제안 값만 돌려줌 | 7-3, 7-4 | FE, BE |
| 11 | 일대기 분류와 그림 번호의 필드 이름(`storyCategory`, `imageNumber`는 임시) | 2-3, 2-6, 2-7 | FE, BE. [작업 D 문서](../../backend/docs/work-split/D-life-story.md) D1, D2 |
| 12 | 지운 이야기를 근거로 만든 카드와 주제의 처리, 카드 생성 기록(`generation_log`)에 남는 이야기 내용, 지운 이야기의 제안이 7-3에서 `rejected`로 보이는 문제 | 2-9, 4-1, 7-3 | PM, BE, AI. 작업 D 문서 D3, D4, D6 |
| 13 | 면회 제안을 승인해 만드는 생애 정보의 분류를 AI가 제안할지 보호자가 고를지 | 7-3, 7-4, 8-3 | PM, AI, FE, BE. 작업 D 문서 D5 |
