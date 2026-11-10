# 새록 API 명세

앱과 백엔드 사이의 공개 API, 백엔드와 AI 서버 사이의 내부 API를 정리한다. 저장 구조는 [init.sql](../../backend/database/init.sql)의 DB 스키마를 따른다. 예시 값은 모두 합성 데이터다.

2026-10-12 문서 정리: 사진 설명은 별도 승인 없이 카드 생성에 쓰고 앨범에서 선택적으로 수정한다(3-3). 카드 API와 요청 및 결과 형식은 [PR #99](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/99)에 맞췄다. 프로필 저장(2-4) 후 카드 생성을 요청(4-1)하고, BE의 4-1 처리에서 생성 함수를 호출한다. 이전 2-5와 내부 8-2는 삭제했으며, 실제 AI 생성 함수 연결은 당시 후속 작업이었고 [PR #120](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/120)에서 카드 생성 worker에 연결했다.

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
3. 본문을 다 받은 뒤 앱 버전, 세션(업로드가 아닌 경로는 이때 형식, 서명, 만료도 확인한다)과 폐기 여부, 계정, 소유권과 동의를 확인한다. 형식, 서명, 만료에서 거절한 요청은 DB 연결을 열지 않는다. 그래서 서버의 DB 설정이 없어도 이런 요청은 `503 DATABASE_NOT_CONFIGURED`가 아닌 `401`이다. 로그아웃이나 탈퇴로 폐기한 세션은 이 단계에서 `401 UNAUTHENTICATED`다.
4. 라우트가 파일 형식과 크기를 검사한다.

HTTPS 앞단(Caddy, `backend/Caddyfile`)에도 514 MiB 본문 상한이 있다. 정상 설정에서는 위 경로별 상한이 더 작아 API가 먼저 응답하고, Caddy 상한은 API 상한을 잘못 키웠을 때의 바깥 방어선이다. 그때 Caddy의 `413`에는 위 오류 형식의 본문이 없다.

상한을 넘거나 1단계에서 거절한 업로드는 본문을 끝까지 받지 않고 응답하므로, 아직 본문을 보내던 클라이언트는 `413`이나 `401` 본문 대신 연결 오류를 받을 수 있다. 앱은 올리기 전에 파일 크기를 확인한다.

현재 구현 (2026-11-09 기준): 이 절의 API 본문 상한, 본문 전 토큰 확인과 `REQUEST_TOO_LARGE`는 [#278](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/278)이며, 11/9 승인 배포([Deploy run 42568179490](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42568179490), develop `59190ba7`)부터 운영에 있다. 형식, 서명, 만료에서 거절한 토큰이 DB 연결을 열지 않는 것은 [#290](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/290)이며 같은 배포로 들어갔다. 배포 workflow는 caddy를 교체하지 않으므로 Caddy 상한은 배포 뒤 caddy를 따로 다시 만들어야 적용된다([배포 문서의 갱신](../../backend/docs/deployment.md#갱신)). 11/9 배포 뒤 caddy를 다시 만든 기록은 팀 운영 기록에 없고, 11/10 배포에서 다시 띄운 서비스도 `api`, `card-worker`, `speech-worker`, `photo-worker`다.

<br>

## API 목록

상태: `완료` 구현됨, `미병합` 구현됐으나 develop에 병합 전, `수정` 기존 API 변경, `신규` 새로 구현, `미정` 결정 전

2026-11-10 develop `83695093` 기준 아래 공개 API는 모두 구현돼 있다. `신규`는 v0.2 이후 새로 만든 API라는 뜻이며 구현 전이라는 뜻이 아니다. 8-3, 8-4는 HTTP 경로 대신 worker가 `ai/`의 함수를 직접 부른다.

현재 구현 (2026-11-10 기준): 이 문서는 develop `83695093` 코드를 따르며, 운영 서버의 BE도 같은 커밋이다. 11/10 01:41 KST 승인 배포([Release build run 42653146404](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42653146404), [Deploy run 42656825849](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42656825849), PM 승인)로 올렸고, migration은 `685f243e9f1f`에서 `9c4e2b7a1f63`(#295)까지 적용했다. 배포 뒤 `api`, `card-worker`, `speech-worker`, `photo-worker`가 다시 떠 정상이고 `/health/ready`는 200이다. 그 전 운영은 아래 11/9 배포(develop `59190ba7`)였고, 그 뒤 develop에 병합된 다음 두 변경이 이 배포로 운영에 들어갔다.

- [#293](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/293): 개인정보 처리방침과 엘리스 ML API 처리위탁 문서. API와 상관없다.
- [#295](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/295): 이야기 후보를 대화 전체에서 빠짐없이 찾도록 지시해 30개까지 받고(`proposals-8`) 후보마다 AI가 고른 분류(`storyCategory`)와 아픈 기억 표시(`sensitive`)를 저장한다(7-3, 7-4, 8-3). 리포트 본문은 화제마다 문단으로 쓴다(`report-6`). 카드 생성 2판은 아픈 경험 카드에 `sensitive`를 붙인다([CardSet](#cardset)). 음성 분석이 끝나면 처리 규모를 개수로만 로그에 남긴다. 운영 `.env`에 `SAEROK_CARD_GENERATION_PROMPT_VERSION`이 없어 코드 기본값 2가 적용되므로 배포 뒤 4-1로 요청한 운영 카드는 2판이다.

11/9 14:42 KST 승인 배포([Deploy run 42568179490](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42568179490)의 두 번째 시도, develop `59190ba7`)는 migration을 `e7c3a1f94d20`에서 `202cdc671d82`(#286), `685f243e9f1f`(#291)까지 적용했다. 그 전 운영은 11/8 승인 배포([Deploy run 42485750502](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42485750502), develop `9c2b8276`)였고, 그 뒤 develop에 병합된 다음 BE 변경이 11/9 배포로 운영에 들어갔다.

- [#275](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/275): 사진 분석이 끝나도 받아 둔 카드 묶음을 `needsRefresh`로 바꾸지 않는다([4절](#사실-정정-후-카드-갱신-기준)).
- [#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277): 7-4의 주제 결정 승인에 카드 묶음 잠금과 갱신 표시를 적용한다.
- [#278](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/278): 요청 본문 크기 상한을 두고, 업로드 경로는 본문을 받기 전에 세션 토큰을 확인한다([본문 크기와 확인 순서](#본문-크기와-확인-순서)).
- [#279](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/279): 리포트 생성이 전사 보관 기한을 넘기거나 지워진 작업의 전사를 보내지 않는다(6-5, 8절).
- [#280](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/280): 전사 저장 직후 멈춘 음성 분석 작업을 다음 worker가 이어 처리한다(8-1 아래 worker 처리 순서).
- [#281](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/281): 전사 정리의 기한 경계와, 5-1, 5-3 처리 중 프로필이 지워질 때 500 대신 404를 내도록 고쳤다. 응답 형식은 그대로다.
- [#282](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/282): 생년월일은 만 10세 이상, 이야기 내용은 5,000자, 프로필당 이야기는 300개까지 받는다(2-2, 2-4, 2-6, 2-7, 7-4).
- [#283](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/283): 작업 행이 먼저 지워진 녹음과 중간에 끊긴 사진 업로드의 S3 원본도 삭제 대기열에 남긴다. API는 그대로다.
- [#284](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/284): 가입 동의 값은 `true`, `false`만 받고 등록 토큰은 한 번만 쓴다(1-2).
- [#285](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/285): 계정별 한도(6-6 동시 2건, 푸시 기기 5대, 6-5 재요청 회차당 3회)를 둔다(1-7, 6-5, 6-6).
- [#286](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/286): worker가 다른 작업을 처리하는 동안 기다리는 카드 생성 작업을 실패시키지 않는다([4절](#4-대화-카드)).
- [#287](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/287): 배포 DB 백업을 14일만 두는 정리 timer를 더했다. API와 상관없고, Deploy가 설치하지 않으며 서버에 설치한 기록이 없어 설치되지 않은 상태다.
- [#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288): AI 사진 분석 동의를 거두면 저장된 AI 설명을 지우고, ML 업체를 부르기 바로 전에 동의를 다시 확인한다(1-6, 3절).
- [#289](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/289): 임대 시간이 지난 뒤 온 카드 생성 결과를 저장하지 않는다([4-1 카드 생성 처리](#4-1-카드-생성-처리)).
- [#290](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/290): 잘못된 토큰은 DB 연결 전에 거절하고, 모르는 `kid`의 구글 공개키 재조회를 묶는다(1-1, 1-2, [본문 크기와 확인 순서](#본문-크기와-확인-순서)).
- [#291](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/291): 카드 생성 기록에 보낸 글 대신 ID만 남기고, 근거가 모두 지워진 주제를 다음 생성 입력에서 뺀다([4-1 카드 생성 처리](#4-1-카드-생성-처리)).

6-2, 6-3, 8-1은 공통 기반 작업에서 새 스키마와 worker 공통 골격에 맞췄다.

| # | 화면 | 메서드 | 경로 | 상태 |
| --- | --- | --- | --- | --- |
| 1-1 | 로그인 | `POST` | `/auth/google` | 완료 |
| 1-2 | 가입 동의 | `POST` | `/auth/consent` | 완료 |
| 1-3 | 앱 시작 | `GET` | `/auth/me` | 완료 |
| 1-4 | 프로필 설정 | `POST` | `/auth/logout` | 완료 |
| 1-5 | 회원 탈퇴 | `DELETE` | `/auth/me` | 수정 |
| 1-6 | 프로필 설정 | `PATCH` | `/auth/me/consents` | 신규 |
| 1-7 | 앱 시작, 알림 수신 동의 | `PUT` | `/auth/me/push-devices/{fid}` | 신규 |
| 1-8 | 로그아웃, 알림 수신 철회 | `DELETE` | `/auth/me/push-devices/{fid}` | 신규 |
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
| 3-3 | 앨범에서 사진 설명 수정 | `PATCH` | `/api/v1/profile-photos/{photoId}/description` | 신규. 필수 승인 없음 |
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
| 6-5 | 홈, 리포트 실패 안내 | `POST` | `/api/v1/speech-analyses/{analysisId}/retry` | 신규 |
| 6-6 | 세부 정보 음성 입력 | `POST` | `/api/v1/speech-transcriptions` | 신규 |
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
    [온보딩]      2-2 → (사진 첨부 시 3-1 → 3-2 폴링) → 2-4 (세부 정보, 음성 입력은 6-6) → 4-1 (카드 생성 시작)
    [홈]          4-2, 5-4. 카드 받기: 4-1 → 4-2 폴링, ready 또는 inVisit이면 4-3(4절 표)
    [어르신 목록] 2-1, 2-8 (삭제). 빈 슬롯 → [온보딩]
    [카드 선택]   4-3 → 면회 사진 촬영(단말)
    [면회]        5-1 (녹음 시작) → 5-2 (사진을 찍었으면) → 5-3 (필요 시) → 녹음 종료(단말). 다시 열면 4-3(`inVisit`)
    [평가]        6-1 → 6-2 → 6-3 폴링. 실패하면 6-5, 유효한 전사가 없어 RECORDING_REQUIRED이면 기기 녹음으로 6-2 재제출
    [리포트]      7-2, 6-4 → 7-3 → 7-4. 회차의 카드 전체 보기: 4-4, 좋았어요 표시: 4-5, 4-6
    [일대기]      2-3, 2-6, 2-7, 2-9
    [마이페이지]  2-3, 2-4, 3-1, 3-2, 3-3
    [리포트 기록] 7-1
    [설정]        알림 스위치와 계정 약관 동의 화면에서 1-6, 로그아웃 1-4, 탈퇴 1-5. 사진 분석 동의 시트에서 동의해도 1-6
    [푸시 기기]   알림 수신에 동의한 계정이면 앱을 켤 때마다 1-7. 로그아웃 전과 알림 수신 철회 때 1-8

<br>

---

## 1. 계정

2026-10-14 PM 결정: 가입 화면에는 기존 필수 2개와 선택 2개에 사진 서버 보관과 AI 분석의 선택 동의를 각각 추가한다. 계정별 기존 동의 이력에 저장하며, 유효한 동의는 기능 사용 때 다시 묻지 않는다. 미동의, 철회 또는 기록 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 이용할 수 있다. 당시에는 네 항목이 계약이었고 새 두 항목의 필드명과 가입, 조회, 변경 API 확장은 FE와 BE가 맞출 후속 구현이었다(아래 현재 구현 참고). 정책 정본은 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)이다.

현재 구현 (2026-11-09 기준): 두 항목 중 AI 분석 동의만 선택 항목 `photoAnalysis`로 가입(1-1, 1-2), 조회(1-3)와 변경(1-6)에 들어갔다([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)). 사진 서버 보관 동의는 아직 필드와 API가 없다.

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

ID 토큰은 DB 연결을 열기 전에 검증하므로, 검증하지 못한 토큰은 DB 설정과 관계없이 위 `401`이나 `IDENTITY_PROVIDER_UNAVAILABLE`이다. 토큰의 `kid`가 서버가 받아 둔 구글 공개키에 없으면 공개키를 다시 받는다. 다만 받아 둔 공개키의 캐시 기간 안이면 마지막 조회 뒤 60초 안에는 다시 받지 않고, 그 조회가 성공이었으면 `401 INVALID_ID_TOKEN`, 실패였으면 `503 IDENTITY_PROVIDER_UNAVAILABLE`(`retryable: true`)로 거절한다.

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
    "pushNotification": true,
    "photoAnalysis": false
  },
  "displayName": null
}
```

- `displayName`: 선택, 50자 이하
- `consents.photoAnalysis`: 선택. 이전 앱은 보내지 않으므로 빠지면 거부로 저장한다.
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

등록 토큰은 DB 연결을 열기 전에 확인하므로, 유효하지 않거나 만료된 등록 토큰은 DB 설정과 관계없이 `401`이다.

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
- `photoAnalysis: false`를 보내면 같은 트랜잭션에서 그 계정 프로필 사진의 저장된 AI 설명을 지우고 `analysisStatus`를 `pending`으로 되돌린다(2026-11-09 PM 결정). 보호자가 쓴 설명(3-3)은 남아 2-3, 3-2의 `description`(`descriptionSource: caregiver`)과 카드 입력에 그대로 쓴다. 보호자 설명이 없는 사진의 AI 설명을 지운 프로필은 아직 면회에 안 쓴 완료 묶음의 `needsRefresh`가 `true`가 된다(4절). 3-4 사진 삭제처럼 그 묶음이 지운 설명을 실제로 입력에 썼는지는 따지지 않는다. 카드를 만드는 중이어도 동의 변경은 거절하지 않으며, 만드는 중인 묶음은 지운 설명을 입력에 썼으면 완료할 때 `needsRefresh`가 `true`가 된다. 보호자 설명이 없어 AI 설명이 지워진 사진은 다음 4-1 입력에서 빠지고, 근거가 그런 사진뿐인 주제도 빠진다(4-1의 `topics`). 카드 생성 기록(`generation_log`)에는 사진 ID만 남으므로 지울 설명 사본이 없다. 다시 `true`로 바꾸면 `pending`인 사진을 다시 분석한다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 422 | `REQUIRED_CONSENT_NOT_CHANGEABLE` | `serviceData` 또는 `sensitiveData`를 보냄 |
| 422 | `INVALID_REQUEST` | 본문이 비었음 |

<a id="1-7-put-authmepush-devicesfid--미병합"></a>

### 1-7. `PUT /auth/me/push-devices/{fid}` — 신규

리포트 완료 푸시를 받을 이 기기를 등록한다. 본문 없음. [PR #248](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/248)로 develop에 병합됐고 11/6 운영 서버 갱신(develop `da606cb0`, 운영 배포 기록)부터 운영에 있으며 지금 운영(develop `83695093`)에도 들어 있다. 계정당 5대 한도는 [#285](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/285)로 11/9 배포부터 운영에 있다.

- `fid`: 앱이 FCM에 등록하고 받은 Firebase Installation ID(FID). FCM은 기기 토큰(`getToken`) 대신 FID를 쓰도록 바꿨고, 서버는 HTTP v1 발송의 `fid`에 이 값을 넣는다. 영문 대소문자, 숫자, `-`, `_`로 된 1~64자다(지금 FID는 22자).
- 같은 요청을 다시 보내면 등록 시각(`push_devices.registered_at`)만 새로 한다. 앱은 켤 때마다 다시 보낸다.
- 다른 계정에 등록된 FID면 이 계정으로 옮긴다. 같은 기기에서 계정을 바꿔 로그인한 경우이며, 앞 계정의 알림이 이 기기로 가지 않게 된다.
- 알림 수신(`pushNotification`)에 동의하지 않은 계정이면 저장하지 않고 거절한다.
- 계정당 5대(서버 설정 `SAEROK_PUSH_DEVICES_PER_ACCOUNT`)까지 둔다. 새 기기로 한도를 넘으면 등록 시각이 가장 오래된 기기, 곧 가장 오래 앱을 켜지 않은 기기의 등록을 지우고 `204`로 답한다. 오류로 알리지 않으며 방금 등록한 기기는 지우지 않는다. 지워진 기기는 앱을 다시 켜서 1-7을 보내면 다시 등록된다(2026-11-09 PM 결정).
- 탈퇴(1-5)하면 계정과 함께 지운다.
- 리포트가 완료되면(6-3의 `completed`) 서버가 그 계정에 등록된 기기로 알림을 보낸다. 알림 문구는 `새록`, `리포트가 준비되었어요`로 고정이고, `data`에는 `type: "reportReady"`, `sessionId`, `analysisId`만 담는다. 어르신 이름과 리포트 내용은 담지 않는다. 앱은 `type`이 `reportReady`인 알림을 누르면 `sessionId`의 리포트를 연다([PR #247](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/247). 홈 밖의 화면에서 누른 알림을 여는 것은 [PR #264](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/264)).
- 분석이 실패로 끝나면(6-3의 `failed`) 같은 조건(작업이 실제로 `failed`, 지금 알림 수신 동의, 그 계정의 등록 기기)으로 알림을 보낸다. 문구는 `새록`, `리포트를 만들지 못했어요`로 고정이고, `data`에는 `type: "reportFailed"`, `sessionId`, `analysisId`만 담는다. 실패 코드와 이유는 담지 않는다. 지금 앱은 `reportFailed`를 눌렀을 때 따로 화면을 옮기지 않고 앱만 열며, 홈의 실패 안내(5-4)가 다시 요청하기를 보여 준다. worker가 실패를 기록하는 경로에서만 보내므로, 멈춘 worker의 작업을 다른 worker의 임대 정리가 끝낸 경우(`WORKER_LEASE_EXPIRED`)와 전사 기한 정리(`TRANSCRIPT_EXPIRED`)는 알리지 않는다. 현재 구현 (2026-11-10 기준): 11/10 E2E 문제 9(실패해도 앱을 열어야 안다)를 고치는 `fix/long-recording-30min-stt` 브랜치의 변경이며 아직 병합하지 않았다. 그 전 동작은 실패를 알리지 않는다.

응답 `204`

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 403 | `PUSH_NOTIFICATION_CONSENT_REQUIRED` | 알림 수신에 동의하지 않음 |
| 422 | `INVALID_REQUEST` | `fid` 형식이 맞지 않음 |

<a id="1-8-delete-authmepush-devicesfid--미병합"></a>

### 1-8. `DELETE /auth/me/push-devices/{fid}` — 신규

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
- 아픈 기억 표시(`sensitive`)는 받지 않는다. 이 경로로 담은 이야기는 `false`이고 2-7로 켠다.
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

- 받는 필드: `storyCategory`, `title`, `content`, `imageNumber`, `sensitive`. 규칙은 2-6과 같고(`title` 100자, `content` 5,000자 이하) `null`로 지울 수 없다. 이야기 수는 바뀌지 않으므로 300개 상한은 보지 않는다.
- `sensitive`: 아픈 기억일 수 있는 이야기라는 표시(`true`, `false`만 받음). 보호자가 켜고 끈다(2026-11-10 PM 결정). 지금 앱은 보내지 않는다.
- 분류를 바꿔도 `imageNumber`와 `createdAt`은 그대로다.
- `title`, `content`, `sensitive`가 실제로 바뀌면 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다(4절). 카드를 만드는 중이면 이 세 값은 고칠 수 없다.

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

- 생애 정보 행만 지운다. 다음 카드 생성(4-1)의 `context.lifeFacts`에서 빠지며, 주제와 지난 카드의 근거에 남은 그 `factId`도 4-1 입력을 만들 때 뺀다. 저장된 근거는 고치지 않는다. 그래서 이야기나 사진 근거가 하나도 남지 않은 주제는 4-1 `context.topics`에 넣지 않는다(PM 결정 2026-11-08). 보호자가 제외한 주제도 근거 이야기와 사진을 모두 지우면 넣지 않는다(PM 결정 2026-11-09, [4-1 카드 생성 처리](#4-1-카드-생성-처리)의 `topics`).
- 이미 만든 카드와 주제, 그 이야기를 출처로 한 변경 제안은 지우지 않는다. 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다(4절). 카드를 만드는 중이면 지울 수 없다. 저장된 지난 카드와 주제의 처리는 미정([미정 사항](#미정-사항) 12)
- 세부 정보 네 항목은 생애 정보가 아니므로 이 API로 지우지 않는다(2-4에서 `null`).

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |
| 409 | `CARD_GENERATION_IN_PROGRESS`(카드를 만드는 중) |

<br>

---

## 3. 프로필 사진

사진은 S3에 서버 측 암호화로 저장한다. 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 계정이 AI 사진 분석(`photoAnalysis`)에 동의한 경우에만 이미지 분석(8-4)을 거친다. 면회 사진(5-2)은 분석하지 않는다.

2026-10-14 PM 결정: 사진 서버 보관과 AI 분석은 가입 화면에서 각각 선택 동의로 받고 기존 계정 동의 이력에 저장한다. 유효한 동의는 재요청하지 않으며, 미동의, 철회 또는 기록이 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 유지한다. 가입 시 수집과 계정별 저장 방향은 결정됐고 필드명 및 API는 당시 후속 구현이었다(아래 현재 구현 참고). 상세 기준은 [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따른다.

[ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)은 사진 보관과 AI 분석 동의를 구분한다. 별도 분석 동의를 확인하지 않은 사진으로 분석 작업을 만들면 안 된다.

현재 구현 (2026-11-09 기준, [PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257), [#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288)): AI 분석 동의는 계정별 선택 동의 `photoAnalysis`(1-1~1-3, 1-6)로 받는다. 사진 분석 worker는 현재 동의 이력의 `photoAnalysis`가 켜진 계정의 `pending` 사진만 가져가고, ML 업체를 부르기 바로 전과 결과를 저장하기 직전에 동의를 다시 확인한다. 동의하지 않은 계정의 사진은 `pending`으로 남고 나중에 동의하면 그때 분석한다. 요청 필드와 응답 enum은 바꾸지 않았다. 동의하지 않은 계정은 보호자가 3-3으로 설명을 직접 적을 수 있다. 동의를 거두면(1-6) 더 가져가지 않고, 분석 중이던 사진은 업체에 보내지 않거나 결과를 버린다. 이미 저장된 AI 설명도 지우며 보호자가 쓴 설명은 남는다([1-6](#1-6-patch-authmeconsents--신규), 2026-11-09 PM 결정). 사진 서버 보관 동의를 따로 받는 필드와 API, 그 철회 처리는 아직 없다.

### 3-1. `POST /api/v1/profiles/{profileId}/photos` — 신규

온보딩의 사진 첨부와 마이페이지의 갤러리 추가에서 호출한다.

요청 `multipart/form-data`

| 필드 | 값 |
| --- | --- |
| `image` | JPEG 또는 PNG. 서버 설정의 크기 상한(기본 20MB) 이하 |

응답 `201` — [ProfilePhoto](#profilephoto), `analysisStatus`는 `pending`

- 프로필당 최대 5장이다.
- 서버는 사진을 `pending`으로 저장한다. 사진 분석 worker(8-4)는 AI 사진 분석에 동의한 계정의 사진만 가져간다.
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
- AI 사진 분석에 동의하지 않은 계정의 사진은 `pending`에 머문다. 앱은 이때 폴링하지 않고 "분석 중" 대신 설명 입력란을 보여 준다([PR #261](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/261)).

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_PHOTO_NOT_FOUND` |
| 503 | `IMAGE_STORAGE_UNAVAILABLE` (`retryable: true`), `IMAGE_STORAGE_NOT_CONFIGURED` — 사진의 조회 URL을 만들지 못함 |

<a id="3-3-사진-설명-확인--미정"></a>

<a id="3-3-앨범에서-사진-설명-수정--api-미정"></a>

### 3-3. `PATCH /api/v1/profile-photos/{photoId}/description` — 사진 설명 수정

[PR #205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205)로 구현했고 11/5 운영 배포(develop `6cebcf72`, [#187 배포 기록](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/187#issuecomment-6652039046))부터 들어 있다.

9월 23일 회의와 10월 6일 BE 논의에서 정한 대로, AI 사진 설명은 별도 승인 없이 카드 생성에 사용한다. 사용자는 원할 때 앨범에서 확인하거나 수정한다. 사진 등록과 카드 선택에 필수 확인 단계를 넣지 않으며, 수정 API가 정해지기 전에도 이를 이유로 설명 사용을 막지 않았다.

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
- 주제와 지난 카드의 근거에 남은 그 `photoId`는 4-1 입력을 만들 때 뺀다. 이야기나 사진 근거가 하나도 남지 않은 주제는 4-1 `context.topics`에 넣지 않는다(PM 결정 2026-11-08). 보호자가 제외한 주제도 근거 이야기와 사진을 모두 지우면 넣지 않는다(PM 결정 2026-11-09).
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

- 2-4, 2-7, 2-9, 3-3, 3-4로 카드 생성에 쓰는 값을 바꾸면 아직 면회에 안 쓴 완료 묶음에 고친 시각(`card_sets.stale_at`)을 남긴다. 2-4는 생년월일, 직업, 고향, 취미, 가족이고 2-7은 제목과 내용이며 3-3은 실제로 쓰이는 사진 설명이 바뀔 때다. 이름, 성별, 인지 상태, 이야기 분류와 그림 번호는 카드 생성에 쓰지 않아서 남기지 않는다. 2-9와 3-4는 항상 남긴다.
- 7-4(변경 사항 확인)는 주제 제안을 하나라도 승인하면 남긴다. 승인한 주제 피드백(`more`, `less`, `exclude`)이 다음 카드 생성에서 주제를 고르는 기준을 바꾸기 때문이다. 생애 정보 제안 승인은 이야기 추가(2-6)와 같아서 남기지 않고 다음 생성부터 반영한다. 모두 거절한 확인도 남기지 않는다.
- 1-6에서 AI 사진 분석 동의를 거둬 보호자 설명이 없는 사진의 AI 설명이 지워진 프로필도 남긴다. 동의 변경은 카드를 만드는 중이어도 거절하지 않는다. 만드는 중인 묶음은 저장할 때 입력 뒤 사진 설명이 바뀐 것을 보고 남긴다.
- 면회에 쓴 묶음은 지난 기록이라 남기지 않는다.
- `stale_at`이 있는 묶음은 4-2, 4-3에서 `status`가 그대로 `ready`이고 `needsRefresh`가 `true`다. 4-1은 이 묶음을 거절하지 않고 새로 만들며, 5-1은 `CARD_SET_NEEDS_REFRESH`로 거절한다.
- 카드를 만드는 중(`running`)에 이 값들을 고치면 2-4, 2-7, 2-9, 3-3, 3-4가 `CARD_GENERATION_IN_PROGRESS`로 거절한다. 주제 제안 승인이 있는 7-4도 같다. worker가 고치기 전 내용으로 만든 묶음이 `needsRefresh` 표시 없이 나올 수 있어서다. 예를 들어 방금 제외한 주제가 그 묶음에 다시 들어갈 수 있다.
- 카드 한 장 단위의 사용 중지 표시는 다루지 않는다.

AI 사진 분석이 끝난 사진은 새 카드 재료로 보고 다음 카드부터 쓰며, 받아 둔 묶음에 `stale_at`을 남기지 않는다. 카드 생성이 끝날 때 입력에 쓴 사진이 그사이 지워졌거나 설명이 바뀌었으면 새 묶음에 `stale_at`을 남기고, 생성 중에 분석이 끝나 새로 생긴 사진은 남기지 않는다([사진 분석 실행 문서](../../backend/docs/photo-analysis.md)).

현재 구현 (2026-11-09 기준): 위 7-4 항목은 [#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277), 1-6 동의 철회 항목은 [#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), 사진 분석 완료 처리는 [#275](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/275)이며 11/9 승인 배포(develop `59190ba7`)부터 운영에 있다. 그 전 운영(11/8 배포, develop `9c2b8276`)은 7-4의 주제 결정 승인을 카드 생성 중에도 받고 `stale_at`을 남기지 않았다. 또 AI 사진 분석이 끝난 사진에 보호자 설명이 없으면 받아 둔 완료 묶음에 `stale_at`을 남겨, 온보딩에서 사진을 올리고 `마치기`로 받은 첫 묶음이 분석이 끝나면 `needsRefresh`가 됐다.

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

`ready`인데 `needsRefresh`가 `true`이면 카드를 받은 뒤 프로필이나 일대기, 프로필 사진 설명을 고쳤거나 사진을 지웠거나 AI 사진 분석 동의를 거둬 AI 설명이 지워졌거나(1-6) 변경 사항에서 주제 결정을 반영했다는 뜻이다(7-4, [4절 기준](#사실-정정-후-카드-갱신-기준)). 카드는 4-3으로 볼 수 있지만 면회는 시작할 수 없고, 버튼을 누르면 4-1로 다시 만든다. 4-1을 부르면 상태가 `running`이 되므로 새 묶음이 나올 때까지 4-3은 `CARD_GENERATION_NOT_FOUND`이고, 다시 만들기가 실패하면 `failed`가 되어 예전 카드도 볼 수 없다.

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
- 첫 성공 묶음이 없고 사진 분석 동의가 있으면 요청 당시 등록된 프로필 사진의 준비를 먼저 기다린다. 기다리는 사진 목록은 요청 이후 늘리지 않는다. 4-2와 같은 `photoPreparation`을 추가로 줄 수 있다. 사진이 없거나 동의가 없으면 기존 흐름으로 진행한다. 이미 완료된 첫 카드에는 소급 적용하지 않는다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `VISIT_IN_PROGRESS` (평가 전 회차가 있음), `CARD_SET_READY` (아직 쓰지 않은 묶음이 있음) |
| 503 | `CARD_GENERATION_NOT_CONFIGURED` (LLM 키가 설정되지 않음) |

#### 4-1 카드 생성 처리

카드 생성 worker(`card-worker`)가 `ai/card_generation`의 생성 함수를 부르고, 그 함수가 ML API를 호출한다([PR #120](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/120)에서 연결).

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
        "source": "visit",
        "sensitive": false
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

- `model`, `promptVersion`: BE 설정값(`SAEROK_CARD_GENERATION_MODEL`, `SAEROK_CARD_GENERATION_PROMPT_VERSION`). 4-1에서 `card_sets`를 `running`으로 만들 때 저장하고 그 값을 그대로 넘긴다. `promptVersion`은 카드 생성 방식의 번호(정수)이며 카드 생성은 아는 번호만 받는다. 현재 새 작업의 기본 모델은 `gpt-6-luna`이고, 예시의 모델은 이전 값이다.
- `schemaVersion`: 요청과 결과 JSON 형식의 버전. 받는 쪽은 모르는 버전을 거절한다.
- `ageRange`: BE가 생년월일로 계산한 `{십 단위 나이}s` (예: `70s`, `80s`). 이름, 성별, 생년월일, 인지 상태, 증상 메모는 넣지 않는다. 카드 생성은 `10s` 이상만 받으므로 2-2, 2-4가 만 10세가 안 된 생년월일을 저장하지 않는다. 그 검사 전에 저장된 프로필은 고치기 전까지 `INVALID_CONTEXT`로 실패한다.
- `lifeFacts.source`: 면회 제안을 승인해 생긴 이야기는 `visit`, 직접 넣은 이야기는 `caregiver`
- `lifeFacts.sensitive`: 아픈 기억일 수 있는 이야기([LifeFact](#lifefact)의 `sensitive`). 보호자가 지우지 않은 아픈 이야기도 빼지 않고 넣는다(2026-11-10 PM 결정). 카드 생성 2판은 이 이야기를 근거로 한 카드를 늘 `sensitive`로 낸다. 1판은 보지 않는다.
- `photos`: 프로필 사진(`session_id`가 없음)의 설명. 보호자가 고친 설명(3-3)이 있으면 그 값, 없으면 분석이 끝난 AI 설명이며 둘 다 없는 사진은 넣지 않는다. 별도 내용 승인 없이 사용하고, 사용자가 원하면 앨범에서 수정한다(3-3). 사진 분석 동의 확인은 별도로 유지한다.
- `topics`: 이 프로필의 기존 주제와 승인된 주제 피드백(`topic_feedback`)이다. 승인 전 제안은 넣지 않는다. 첫 생성에는 빈 배열이다. 근거(`evidence`)에서는 입력에 없는 이야기와 사진(지운 것, 설명이 없어 `photos`에 넣지 않는 사진, 제외한 주제의 근거)을 뺀다. 빼고 나서 근거가 하나도 남지 않은 주제는 넣지 않는다(PM 결정 2026-11-08). 원래 근거가 없던 주제와 세부 정보 칸 근거가 남은 주제는 넣는다. 보호자가 `exclude`를 고른 주제는 근거 이야기와 사진이 제외 규칙으로 늘 입력에서 빠지므로, 보낸 입력이 아니라 DB에 남은 이야기와 `photos`에 넣을 수 있는 사진으로 정한다. 하나라도 남아 있으면 같은 이야기로 새 주제를 만들지 않도록 근거만 빼고 넣는다. 보호자가 모두 지웠으면 제목과 설명에 지운 이야기의 내용이 담겨 있을 수 있으므로 넣지 않는다(PM 결정 2026-11-09). 세부 정보 칸 근거가 있는 제외 주제는 이야기와 사진을 모두 지워도 다른 주제처럼 넣는다. AI 사진 분석 동의를 거둬 AI 설명이 지워진 사진(보호자 설명 없음, 1-6)도 `photos`에 넣지 않으므로, 근거가 그런 사진뿐인 주제는 제외 여부와 상관없이 넣지 않고 다시 분석이 끝나면 넣는다. 저장된 주제와 근거는 지우지 않는다.
- `visits`: 평가까지 끝난 회차(`evaluated_at` 있음)만, 시간순. 녹음을 시작했다가 그만둔 회차는 넣지 않는다.
- `pastCards`: 그 회차에 쓰인 카드 묶음의 카드. 직전에 보여 준 주제를 미루고, 지난번과 다른 장면을 고르는 데 쓴다. 회차에 쓰이지 않은 묶음은 넣지 않는다. 위에서 뺀 주제를 가리키는 카드도 그대로 넣는다. 받는 쪽은 `pastCards[].topicId`가 `topics`에 있다고 가정하지 않는다.
- 면회 평가 메모, 리포트 본문, 전사문은 넣지 않는다.
- BE는 보낸 `context`를 `card_sets.generation_log.input`에 ID로만 남긴다. 형태는 아래 '카드 생성 기록'에 있다.

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
      "sensitive": false,
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
      "sensitive": false,
      "extra": { "...": "..." }
    }
  ],
  "log": { "...": "..." }
}
```

- 카드는 12장이다. `position` 1~9가 선택용, 10~12가 보충용이며 `followUpQuestions`는 카드마다 3개다.
- `topic`: 기존 주제면 `topicId`, 새 주제면 `title`, `description`, `evidence`. 새 주제는 BE가 `profile_topics`에 만든다. 한 묶음 안에서 같은 `topicId`는 두 번 나오지 않는다.
- `evidenceSource`: `lifeFact`, `photo`, `profile`, `none`. `none`이면 `evidence`는 빈 배열이고 나머지는 하나 이상이다. 근거 항목은 `{"factId": ...}`, `{"photoId": ...}`, `{"profileField": "occupation" | "hometown" | "hobby" | "family"}` 중 하나이며, 카드의 근거 항목은 모두 `evidenceSource`와 같은 종류다(`lifeFact`는 `factId`, `photo`는 `photoId`, `profile`은 `profileField`). `profileField`는 context의 `profileFacts`에서 값이 있는 항목만 가리킨다.
- `sensitive`: 저장된 이야기나 세부 정보에 담긴 아픈 경험(사별, 전쟁, 사고, 병)을 다루는 카드면 `true`다(2026-11-09 PM 결정). 카드 생성 2판(`promptVersion` 2)만 `true`를 낼 수 있고 1판은 늘 `false`다. 2판은 근거 이야기 중 `lifeFacts[].sensitive`가 `true`인 것이 있으면 모델이 무엇을 적든 `true`로 낸다(2026-11-10 PM 결정, 코드로 보장). BE는 `conversation_cards.sensitive`로 저장해 [CardSet](#cardset)에 담는다.
- `extra`, `log`: 생성 쪽이 자유롭게 채우는 객체다. BE는 화면과 결과 검증에 쓰지 않고, `generation_log`에는 정해진 값과 숫자만 남긴다(아래 '카드 생성 기록').
- `cardId`와 새 주제의 `topicId`는 백엔드가 부여한다.

검증과 저장

- BE는 저장 전에 확인한다: 12장, `position` 1~12가 한 번씩, 꼬리 질문 3개, 카드 제목, 설명, 첫 질문, 꼬리 질문이 공백만으로 되어 있지 않음, 한 묶음 안 같은 `topicId` 중복 없음, 기존 `topicId`와 근거 ID가 context에 있음, 보호자가 `exclude`를 고른 주제는 쓰지 않음, `profileField`는 context에 값이 있는 항목, 근거 항목 형식, 카드의 근거 항목이 `evidenceSource`와 같은 종류(`none`이면 빈 배열). 맞지 않으면 `INVALID_GENERATION_RESULT`로 실패시킨다.
- 저장은 한 트랜잭션이다: 새 주제, 카드 12장, `card_sets`를 `completed`로(임대도 지움), `generation_log`(`input`, `log`, `cards`).
- 저장 트랜잭션은 프로필과 작업 행을 잠근 뒤 임대가 남은 `running` 작업일 때만 저장한다. 생성하는 동안 임대 시각이 지났으면 임대 만료 정리가 아직 돌지 않았어도 결과를 버리고 새 주제와 카드를 하나도 저장하지 않으며, 작업을 `WORKER_LEASE_EXPIRED`로 실패시킨다.
- 임대 시각이 지난 뒤 온 생성 실패와 검증 실패도 그 코드 대신 `WORKER_LEASE_EXPIRED`로 남긴다. 이미 `failed`나 `completed`가 된 작업은 늦게 온 결과나 실패가 바꾸지 않는다.

카드 생성 기록 (`generation_log`)

PM 결정(2026-11-08)으로 기록에는 생성에 보낸 글을 복사하지 않고 ID만 남긴다. 보호자가 지운 이야기나 사진 설명이 기록에 계속 남지 않게 한다. 기록은 다음 생성 입력에 쓰지 않고 실패를 살펴볼 때만 본다. 규칙은 `backend/app/services/card_generation_log.py`에 있다.

```json
{
  "input": {
    "ageRange": "80s",
    "profileFields": ["hobby"],
    "lifeFactIds": ["00000000-0000-4000-8000-000000000111"],
    "photoIds": [],
    "topicIds": ["00000000-0000-4000-8000-000000000451"],
    "visitSessionIds": ["00000000-0000-4000-8000-000000000300"],
    "pastCardIds": ["00000000-0000-4000-8000-000000000501"]
  },
  "log": { "candidates": 18, "refills": 1, "selectionSeed": 7 },
  "cards": [ { "position": 1, "kind": "personal", "bucket": "new" } ]
}
```

- `input`: 보낸 이야기, 사진, 주제, 회차, 지난 카드의 ID와 `ageRange`, 값이 있던 세부 정보 칸의 이름(`profileFields`). 세부 정보 값, 이야기 제목과 내용, 사진 설명, 주제 제목과 설명, 지난 카드 문구는 남기지 않는다.
- `log`: 결과 `log`에서 숫자와 참거짓은 그대로, 목록은 개수로 남기고 글과 객체는 버린다. 다시 찾기 요청 글, 빠진 후보의 카드 제목과 이유, 문안 검사에 걸린 질문에 이야기 내용이 들어갈 수 있어서다.
- `cards`: 카드별 `extra`에서 `kind`, `bucket`만 남긴다. `angle`, `pickReason`, `agentReason`, `matchReason`은 남기지 않는다.
- 생성 함수가 실패 코드를 돌려줬거나 결과 검증에서 실패한 작업은 `input`만 남긴다. 임대 시각이 지난 뒤 결과나 이 두 실패가 와서 worker가 `WORKER_LEASE_EXPIRED`로 끝낸 작업도 `input`만 남긴다. 만료 정리(worker의 정리, 4-1과 4-2의 정리)가 먼저 `WORKER_LEASE_EXPIRED`로 끝낸 작업, worker가 가져가지 않은 작업(`CARD_GENERATION_NOT_STARTED`)과 그 밖의 예상하지 못한 오류는 `{"input": null}`이다. 진행 중(`running`)인 작업은 `NULL`이다.
- 이 형태 전에 저장된 기록은 migration `685f243e9f1f`가 같은 형태로 고친다.

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
- `needsRefresh`: `ready`인 묶음을 받은 뒤 프로필이나 일대기, 프로필 사진 설명을 고쳤거나 사진을 지웠거나 AI 사진 분석 동의를 거둬 AI 설명이 지워졌거나(1-6) 변경 사항에서 주제 결정을 반영했으면(7-4) `true`. 다른 상태에서는 늘 `false`다.
- 작업이 없어도 오류가 아니라 `none`이다.
- 첫 카드가 사진을 기다릴 때만 아래 `photoPreparation`이 추가된다. `waiting`은 폴링하고, `choice`는 자동 재시도 없이 4-7의 선택을 받는다. 대기 시간은 카드 worker 시작 제한에 포함하지 않는다. 준비가 끝난 작업은 앱의 조회 없이도 카드 worker가 가져간다.

```json
{
  "schemaVersion": 1,
  "status": "running",
  "needsRefresh": false,
  "photoPreparation": {
    "setId": "d0b0132a-b18e-4200-9ce2-df4469630388",
    "state": "choice",
    "total": 5,
    "completed": 3,
    "failed": 1,
    "pending": 1,
    "reason": "analysisFailed"
  }
}
```

- `completed`: AI 분석 완료 또는 보호자 설명이 있는 사진 수. 삭제된 사진은 `total`에서 빠진다.
- `failed`: 실패했거나 분석 임대가 만료된 사진 수. 나머지가 `pending`이다.
- `reason`: `analysisFailed`, `timedOut`, `consentRequired`. `waiting`일 때는 없다. 선택 사유가 겹치면 동의 철회, 분석 실패, 시간 초과 순으로 표시한다.

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

### 4-7. `POST /api/v1/profiles/{profileId}/card-generations/photo-preparation`

첫 카드 사진 대기가 `choice`일 때 보호자의 선택을 받는다. 로그인한 계정 소유의 프로필만 처리한다.

요청:

```json
{ "setId": "d0b0132a-b18e-4200-9ce2-df4469630388", "action": "retry" }
```

- `retry`: 실패 또는 임대 만료 사진만 다시 분석 대기로 바꾸고 사진 대기 기한을 갱신한다. 살아 있는 분석은 그대로 둔다. 동의 철회 상태에서는 거절한다.
- `continue`: 사진 대기를 해제하고 현재 사용 가능한 설명으로 카드를 만든다. 준비된 사진이 없으면 사진 없이 만든다. 아직 처리 중인 사진 분석 자체는 취소하지 않는다.
- 두 선택 모두 기존 카드 작업 ID를 유지한다. 이전 작업이나 이미 바뀐 상태에 대한 요청은 409다. 앱은 4-2로 상태를 다시 읽는다.
- 응답 `200`: 4-2와 같은 형식. 카드 생성이 끝났다는 뜻이 아니며 `running`이면 계속 상태를 확인한다.

| HTTP | `errorCode` |
| --- | --- |
| 404 | `PROFILE_NOT_FOUND` |
| 409 | `PHOTO_PREPARATION_CHANGED`, `PHOTO_ANALYSIS_CONSENT_REQUIRED` |
| 422 | `INVALID_REQUEST` (잘못된 UUID 또는 action) |

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
- 30분을 넘는 녹음은 worker가 30분 이하 조각으로 나눠 차례로 전사하므로(8-1) `transcribing`이 길어질 수 있다. 그 사이 worker가 종료 요청을 받으면 진행 중인 조각만 마치고 작업을 `queued`로 되돌리며, 다음 worker가 처음 조각부터 다시 전사한다. 응답 형식과 상태 이름은 같다(`fix/long-recording-30min-stt`, 미병합).

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
WAV/PCM 16-bit/16kHz/mono, 최대 5분이다. 앱이 5분 타이머로 녹음을 멈추면 파일이 300초를 조금 넘으므로 2초 여유를 둔다([PR #267](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/267)). 응답은 `200`과
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

- 생애 정보 제안마다 AI가 고른 일대기 분류(`storyCategory`: `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`)와 아픈 기억일 수 있다는 표시(`sensitive`)를 담는다(2026-11-09 PM 결정, #139). 11/10 배포(develop `83695093`)부터 운영에 있다.

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
      "content": "한복과 두루마기를 주로 만드셨어요.",
      "storyCategory": "hobby"
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
  - `lifeFacts[].storyCategory`: 선택. 보호자가 고른 일대기 분류이며 값은 2-6과 같다. 빼면 제안의 `storyCategory`(AI가 고른 값)로 만든다. 앱은 보호자가 분류를 바꾼 항목에만 담는다(예시는 `work` 제안을 `hobby`로 바꾼 경우). `null`이나 7개 밖의 값은 422 `INVALID_REQUEST`다(2026-11-09 PM 결정, #139). 서버는 11/10 배포(develop `83695093`)부터 운영에 있다. 앱의 분류 고르기는 새 APK를 만들어야 휴대폰에 들어가며, 설치된 앱(Play와 11/8 Releases APK)에는 없다.
  - `topics[].action`: `more`, `less`, `exclude`. 보호자가 고른 행동이며 제안의 `suggestedAction`과 달라도 된다. 바꾸지 않았으면 제안 값을 그대로 보낸다.
- `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- 제안이 없는 회차의 확인 처리는 미정([미정 사항](#미정-사항) 2)

응답 `200` — [ChangeProposal](#changeproposal)

서버 처리

- 모든 제안을 `settled`로 바꾼다.
- `accepted`인 생애 정보 제안은 요청의 `title`, `content`로 생애 정보를 만든다. 분류는 요청의 `storyCategory`이고 없으면 제안의 `storyCategory`이며, 그림 번호는 서버가 1~5 중에 고른다. 아픈 기억 표시(`sensitive`)는 제안의 값을 그대로 옮긴다(2026-11-10 PM 결정). 요청으로 바꾸지 않고, 만든 뒤 2-7로 바꾼다. 생애 정보의 `source_proposal_id`가 그 제안이다. 제안(`life_fact_proposals`)의 `title`, `content`, `reason`, `story_category`, `sensitive`는 바꾸지 않는다.
- `accepted`인 주제 제안은 요청의 `action`을 `topic_feedback.action`에 기록하고 다음 카드 생성(4-1)의 `topics`에 반영한다. 제안의 `suggested_action`은 바꾸지 않는다.
- `rejected` 항목은 반영하지 않는다.
- `accepted` 주제 항목이 하나라도 있으면 다음 카드 생성에서 주제를 고르는 기준이 바뀐다. 2-4, 2-7, 2-9와 같이 프로필을 잠그고, 카드를 만드는 중이면 `CARD_GENERATION_IN_PROGRESS`로 거절하며 아무것도 저장하지 않는다. 만드는 중이 아니면 아직 면회에 안 쓴 완료 묶음은 `needsRefresh`가 `true`가 된다([4절](#사실-정정-후-카드-갱신-기준)). 카드 생성이 끝난 뒤 같은 요청을 다시 보내면 된다. 생애 정보만 승인한 확인은 이야기 추가(2-6)처럼 거절하지도 표시하지도 않는다.
- 모두 `rejected`인 요청(`반영하지 않고 마치기`)은 카드 생성 입력을 바꾸지 않는다. 카드를 만드는 중에도 받고 `needsRefresh`를 바꾸지 않는다.
- `accepted`인 생애 정보 제안을 더해 프로필의 이야기가 300개(2-6과 같은 상한)를 넘으면 `LIFE_FACT_LIMIT_EXCEEDED`로 거절하고 제안 정리와 주제 피드백을 포함해 아무것도 저장하지 않는다. 일대기에서 이야기를 지우거나 일부 제안을 `rejected`로 바꿔 다시 보낸다.

현재 구현 (2026-11-09 기준): 위 첫 항목의 주제 승인 처리(프로필 잠금, 카드 생성 중 거절, `needsRefresh` 표시)와 아래 409 `CARD_GENERATION_IN_PROGRESS`는 [#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277), 이야기 300개 상한과 `content` 5,000자는 [#282](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/282)이며 11/9 승인 배포(develop `59190ba7`)부터 운영에 있다. 그 전 운영(11/8 배포, develop `9c2b8276`)은 주제 결정을 승인해도 카드를 만드는 중에 거절하지 않았고, 받아 둔 묶음의 `needsRefresh`도 바꾸지 않았다.

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `VISIT_SESSION_NOT_FOUND`, `REPORT_NOT_FOUND` | |
| 409 | `PROPOSAL_ALREADY_REVIEWED` | 이미 `settled`인 제안이 있음 |
| 409 | `CARD_GENERATION_IN_PROGRESS` | `accepted` 주제 항목이 있는데 카드를 만드는 중(4-2 `running`). 404, `PROPOSAL_ALREADY_REVIEWED`, 422 검사가 먼저다 |
| 409 | `LIFE_FACT_LIMIT_EXCEEDED` | `accepted` 생애 정보 제안을 더하면 프로필의 이야기가 300개를 넘음. 404, 위 두 409, 422 검사가 먼저다 |
| 422 | `INVALID_PROPOSAL_REVIEW` | `pending` 제안이 빠졌거나 다른 회차의 제안 |
| 422 | `INVALID_REQUEST` | `accepted` 항목에 최종 값(`title`과 `content`, 또는 `action`)이 없거나 `rejected` 항목에 있음. 최종 `title`이 100자, `content`가 5,000자를 넘음. `storyCategory`가 `null`이거나 7개 값이 아니거나 `rejected` 항목에 있음 |

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

30분을 넘는 녹음(2026-11-10 PM 결정, `fix/long-recording-30min-stt`, 미병합): 한 번의 8-1은 BE 제한 시간(`SAEROK_AI_SERVER_TIMEOUT_SECONDS`, 기본 600초)을 넘길 수 없고, 11/10 E2E에서 예비 STT는 71분 녹음에 690초, 88분 녹음에 1,016초가 걸렸다. 그래서 worker는 원본을 내려받아 헤더의 실제 길이가 30분을 넘으면 30분 이하 조각(각 조각 30분 직전 40초 안의 가장 조용한 100ms에서 자름)으로 나눠 8-1을 조각마다 차례로 부른다. 요청 형식은 위와 같고 `analysisId`, `speakerCount`, `dataExpiresAt`은 원본 작업의 값, `sizeBytes`와 `sha256`은 그 조각의 값이다. 제한 시간은 호출마다 따로 적용된다. 조각은 원본과 같은 버킷과 접두사의 임시 객체이며, 그 조각의 8-1이 끝나도 지우지 않고 원본과 같은 때(합친 전사 저장 뒤, 실패하면 실패 처리)에 함께 지운다(11/10 PM 정정). 받은 결과는 조각 시작 시각만큼 `startMs`, `endMs`를 옮겨 순서대로 합치고, 화자 분리가 조각마다 따로 돌므로 `speakerLabel` 앞에 조각 번호를 붙인다(`PART2_SPEAKER_00`). 알려진 무음 문장 거르기와 빈 전사(`EMPTY_TRANSCRIPT`) 확인은 합친 결과에 한다. 조각 하나라도 실패하면 작업은 그 오류 코드로 `failed`다. 30분 이하 녹음은 지금처럼 원본 하나로 한 번 부른다. 보호자가 공유하는 녹음은 기기의 전체 WAV이며 조각과 관계없다.

8-3 시작 전에 worker가 멈추면 작업은 `sttCompleted`로 남는다. 전사 저장 때 기록한 인계 임대(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`, 기본 900초)가 끝나면 다음 worker가 같은 작업과 저장된 전사로 8-3부터 이어 간다. 8-1과 S3 다운로드는 반복하지 않고, 원본 삭제 기록이 없으면 삭제 요청을 대기열에 남긴다. 이어받기는 작업마다 한 번이며 실패한 작업이나 남은 전사 기한이 생성 단계 임대 시간보다 짧은 작업은 이어받지 않는다. `--stt-only`로 멈춘 작업도 이어받지 않는다.

S3 삭제만 실패한 경우에는 삭제 요청을 대기열에 남기고 리포트 생성을 계속한다. `audio_deleted_at`은 삭제 성공 뒤에만 기록하며, 분석 완료와 원본 삭제 완료를 구분한다.

- 전사문은 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업(`speech_analysis_jobs.transcript`)에 임시 저장한다. 최초 STT 저장 시각부터 24시간을 `transcript_expires_at`으로 정하며, 리포트 저장이 먼저 완료되면 지운다. 실패 전사는 남은 기한 동안 유지하며 재시도로 기한을 늘리지 않는다(2026-11-03 PM 승인). 만료 전사의 재사용은 거절하고 worker 정리 시 전사를 삭제하며 `failed`와 `TRANSCRIPT_EXPIRED`로 기록한다. worker 중단이나 긴 처리 중에는 실제 정리가 늦어질 수 있다([보관 대조](../../backend/docs/speech-recovery.md#실패-전사와-기기-녹음의-보관-대조)).
- 8-3(전사문의 외부 ML 전송)은 남은 전사 기한이 생성 단계 임대 시간(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`, 기본 900초) 이상일 때만 시작한다. 임대는 생성 제한 시간보다 60초 이상 길어 시작한 생성이 기한을 넘겨 새 외부 호출을 하지 않는다. 기한이 그보다 적게 남은 `sttCompleted` 작업은 시작하지 않고 worker 정리 시 `failed`와 `TRANSCRIPT_EXPIRED`로 끝낸다([외부 ML 전송과 기한](../../backend/docs/speech-recovery.md#외부-ml-전송과-기한)).
- 전사문은 화면에 표시하지 않고 8-3 요청에만 사용한다.

현재 구현 (2026-11-09 기준): 위의 이어받기는 [#280](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/280), 남은 전사 기한에 따른 8-3 시작 제한과 8-3 전송 방식의 변경 제안 호출 직전 확인은 [#279](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/279)이며 11/9 승인 배포(develop `59190ba7`)부터 운영에 있다. 그 전 운영(11/8 배포, develop `9c2b8276`)에서는 전사를 저장한 뒤 8-3을 시작하기 전에 멈춘 작업을 다시 가져가는 경로가 없어, 그 작업은 전사 기한(24시간)이 지나 worker 정리로 `TRANSCRIPT_EXPIRED`가 될 때까지 `sttCompleted`로 남았다.

8-1이 성공해도 발화 구간이 없거나 공백뿐이면 `EMPTY_TRANSCRIPT`로 끝내고 8-3을 호출하지 않는다. 이 검사 전에 무음에서 STT가 지어내는 알려진 문장을 지우며([PR #263](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/263)), 나뉘어 온 구간도 이어 붙여 비교한다([PR #267](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/267), [전사 입력 검사](../../backend/docs/speech-input-safety.md)).

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
      "reason": "이번 면회에서 확인되었어요.",
      "storyCategory": "work",
      "sensitive": false
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
- `lifeFactProposals`는 30개까지다(2026-11-09 PM 결정, AI 쪽이 먼저 자름). 항목마다 AI가 고른 일대기 분류 `storyCategory`(`family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`)와 아픈 기억일 수 있는지 `sensitive`가 있어야 하며, 어기면 `INVALID_AI_RESPONSE`다. 두 값은 `life_fact_proposals`에 저장하고 7-3에 담는다. 11/10 배포(develop `83695093`)부터 운영에 있다.
- 카드를 쓰지 않았거나 답하지 않았다는 사실만으로 `less`, `exclude`를 제안하지 않는다(2026-09-19 PM 결정).
- 보호자가 `negative`(아쉬웠어요)로 평가한 카드에는 `more`를 제안하지 않는다(`proposals-9`, 11/10 E2E 문제 12). 앱이 AI 제안을 미리 골라 두기 때문이다. AI 쪽 코드가 그 `more`를 버리고 보내므로 BE 검증 규칙은 바꾸지 않았다.
- `mood`는 AI가 만들지 않는다. 백엔드가 `conversationSatisfaction`으로 계산한다(1~2 `hard`, 3 `normal`, 4~5 `good`).
- `proposalId`는 백엔드가 부여한다.

### 8-4. `POST /internal/v1/image-analyses` — 신규

아래는 내부 계약이다. 사진 분석 worker(`photo-worker`)는 리포트와 같은 방식으로 `ai/photo_analysis` 함수를 직접 호출하며 이 HTTP 경로를 공개하지 않는다. AI 사진 분석에 동의한 계정의 사진만 처리한다([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)). 운영에는 11/8 배포([Deploy run 42385596940](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/actions/runs/42385596940))부터 들어갔고, 11/8 운영 시험에서 공개 사진 43장을 두 번씩 분석한 86건이 모두 완료됐다([안정성 시험](../../backend/docs/stability-test-20261108.md)). 실행 조건은 [사진 분석 실행 문서](../../backend/docs/photo-analysis.md)를 따른다.

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
  "sensitive": false,
  "createdAt": "2026-08-21T12:10:00+09:00"
}
```

- `sensitive`: 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 이야기면 `true`(2026-11-10 PM 결정, migration `5d2e8b1c9a47`). 7-4로 만든 이야기는 승인한 제안의 표시를 옮기고, 2-6으로 담은 이야기는 `false`이며, 보호자가 2-7로 바꾼다. 이 열을 더하기 전에 승인한 이야기는 migration이 출처 제안의 표시를 옮겼다. 보호자가 지우지 않는 한 아픈 이야기도 일대기와 카드 생성(4-1 `lifeFacts[].sensitive`)에 쓴다. 앱은 일대기에 `조심스러운 이야기` 표시를 달고 홈 말풍선의 이야기 추천에서 뺀다. 이 필드를 모르는 클라이언트는 무시하면 되고, 앱은 없으면 `false`로 읽는다. 운영 배포 전이다.
- `storyCategory`, `imageNumber`: 2-6과 같다. 7-4로 만든 생애 정보의 분류는 보호자가 승인 때 고른 값이고, 고르지 않았으면 AI가 제안에 붙인 분류다(2026-11-09 PM 결정, [미정 사항](#미정-사항) 13). 만든 뒤에는 2-7로 바꿀 수 있다. 번호는 서버가 1~5 중에 고른다.

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
  "descriptionSource": "ai",
  "error": null,
  "createdAt": "2026-08-21T12:20:00+09:00"
}
```

- `analysisStatus`: `pending`, `processing`, `completed`, `failed`. AI 사진 분석에 동의하지 않은 계정의 사진은 `pending`에 머문다.
- `description`: 보호자가 3-3으로 고친 설명이 있으면 그 값, 없으면 `completed`인 AI 설명, 둘 다 없으면 `null`
- `descriptionSource`: `caregiver`, `ai`, 설명이 없으면 `null`(3-3)
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
      "liked": false,
      "sensitive": false
    }
  ]
}
```

- `setId`: 녹음을 시작할 때 5-1에 보낸다.
- `usedBySessionId`: 이 묶음을 쓰는 평가 전 회차. 고르기 전이면 `null`. 앱을 다시 켰을 때 이 값으로 5-2, 5-3을 부른다. 4-4에서는 요청한 회차이며 평가가 끝난 회차일 수 있다.
- `needsRefresh`: 이 묶음을 받은 뒤 프로필이나 일대기, 프로필 사진 설명을 고쳤거나 사진을 지웠거나 AI 사진 분석 동의를 거둬 AI 설명이 지워졌거나(1-6) 변경 사항에서 주제 결정을 반영했으면(7-4) `true`. 이 묶음으로는 5-1을 부를 수 없다(4절).
- `cards`: 12장. 회차에서 고른 카드와 더한 보충 카드는 `selected`가 `true`다.
- `liked`: 보호자가 4-5로 "좋았어요"를 표시한 카드면 `true`. 4-6으로 지우면 `false`다.
- `sensitive`: 아픈 경험(사별, 전쟁, 사고, 병)을 다루는 카드면 `true`. 앱이 표시를 달아 보호자가 고를지 정하게 한다(2026-11-09 PM 결정). 카드 생성 2판(`promptVersion` 2)으로 만든 묶음에서만 `true`가 나오고, 1판 묶음과 이 필드를 더하기 전에 만든 카드는 `false`다. 서버는 11/10 배포(develop `83695093`)부터 운영에 있고, 운영 `.env`에 `SAEROK_CARD_GENERATION_PROMPT_VERSION`이 없어 코드 기본값 2가 적용되므로 배포 뒤 4-1로 요청한 묶음은 2판이다. 앱의 표시는 새 APK를 만들어야 휴대폰에 들어가며, 설치된 앱(Play와 11/8 Releases APK)에는 없다.
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
      "storyCategory": "work",
      "sensitive": false,
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

- `topic.description`: 주제 설명이다. [CardSet](#cardset)의 `topic.description`, 4-1 요청의 `topics[].description`과 같은 값이다.
- `suggestedAction`: `more`, `less`, `exclude`
- `reviewStatus`: `pending`, `accepted`, `rejected`. DB에는 `pending`과 `settled`만 저장하므로, `settled`인 제안은 승인 결과(생애 정보 또는 주제 피드백)가 있으면 `accepted`, 없으면 `rejected`로 반환한다.
- `storyCategory`: AI가 고른 일대기 분류(2-6과 같은 7개 값). 7-4에서 보호자가 바꾸지 않으면 이 분류로 이야기를 만든다. `sensitive`: 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 후보면 `true`이며 앱이 안내를 붙인다. 두 필드를 더하기 전에 만든 제안은 `other`, `false`다(2026-11-09 PM 결정, #139, migration `9c4e2b7a1f63`).
- `lifeFactProposals`의 `title`, `content`, `storyCategory`, `sensitive`와 `topicProposals`의 `suggestedAction`은 AI의 원래 제안이며 검토 뒤에도 바뀌지 않는다. 보호자가 고친 값은 생애 정보와 주제 피드백에만 남는다. 검토 뒤 응답에 보호자가 고른 값을 담을지는 미정([미정 사항](#미정-사항) 10)

<br>

---

## 미정 사항

| # | 항목 | 영향 | 확인할 곳 |
| --- | --- | --- | --- |
| 1 | 앨범에서 사진 설명을 수정하는 API와 분석 중 수정 처리. 설명의 별도 승인은 필요 없음. 해결: 3-3으로 구현했고 늦게 온 AI 결과는 보호자 설명을 덮지 않는다([PR #205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205)) | 3-3, 카드 생성, 8-4 | FE, BE, AI. 카드 입력 사용과 생애 사실 승인을 구분 |
| 2 | 리포트 확인 여부 저장(보류). 제안이 없는 리포트는 7-4가 없어 확인했는지 알 수 없음. 앱은 리포트와 제안을 모두 읽으면 확인한 것으로 보고 홈 알림을 지우며, 앱을 다시 켜면 다시 뜬다(#235). 서버 저장은 #236 | 4-1 호출 시점, 5-4 홈 표시, 7-4 | `visit_sessions.report_acknowledged_at` 추가 검토 |
| 3 | 사진 보관과 AI 분석은 가입 화면의 별도 선택 항목으로 받고 계정별 이력에 저장하기로 PM 결정 완료(2026-10-14). 유효한 동의는 재요청하지 않으며 미동의자는 기능 사용 시 요청. AI 분석 동의(`photoAnalysis`)의 필드, 가입, 조회, 변경 API(1-1~1-3, 1-6)와 화면, 미동의 사진의 `pending` 유지와 철회 시 분석 중단은 [PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)로 구현했고, 동의를 거두면 저장된 AI 설명을 지운다([#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), 2026-11-09 PM 결정). 남은 것은 사진 서버 보관 동의를 따로 받는 필드, API와 화면, 그 철회 처리 | 1-1~1-3, 1-6, 3-1, 5-2, 8-4 | FE, BE, AI. 기존 동의 범위를 바꾸는 경우 PM 확인 |
| 7 | 사진 삭제와 보관 동의 철회 동선 및 API 형태. 사진 한 장 삭제 API는 3-4로 구현했다([PR #240](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/240)). 앱에는 올라간 사진을 지우는 버튼이 아직 없어 3-4를 부르지 않는다. 보관 동의가 없어 그 철회 동선은 정하지 않았다. 삭제 대기열의 S3 삭제 실행기([PR #204](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/204)) 코드는 운영 이미지(develop `83695093`)에 들어 있지만 compose 서비스가 아니라 손으로 실행하는 명령이다. 실행기의 정기 실행과 실행기를 통한 실제 원본 삭제는 11/6 PM 결정으로 보류 중이다(팀 운영 기록) | 3절 | FE, BE, PM |
| 8 | 카드 생성이나 음성 분석이 처리 중인 프로필 또는 계정을 지울 때의 처리. 삭제를 허용하고 worker가 사라진 행을 건너뛸지, 처리 중에는 409로 막을지 | 1-5, 2-8 | BE |
| 9 | 입력 중(`inProgress`)인 프로필만 있을 때 로그인 직후 그 프로필의 입력을 이어서 할지, 홈으로 갈지 | 2-1, 호출 순서 | FE, BE |
| 10 | 검토 뒤 ChangeProposal 응답에 보호자가 고른 행동과 고친 생애 정보를 담을지. 지금은 원래 제안 값만 돌려줌 | 7-3, 7-4 | FE, BE |
| 11 | 일대기 분류와 그림 번호의 필드 이름(`storyCategory`, `imageNumber`는 임시) | 2-3, 2-6, 2-7 | FE, BE. [작업 D 문서](../../backend/docs/work-split/D-life-story.md) D1, D2 |
| 12 | 지운 이야기를 근거로 만든 저장된 카드와 주제의 처리, 지운 이야기의 내용이 담긴 지난 카드 문구를 다음 생성 입력(`pastCards`)에 넣을지, 지운 이야기의 제안이 7-3에서 `rejected`로 보이는 문제. 카드 생성 기록은 ID만 남기고, 이야기나 사진 근거가 모두 사라진 주제는 다음 생성 입력에서 빼기로 정했다(PM 결정 2026-11-08, 제외한 주제는 2026-11-09) | 2-9, 4-1, 7-3 | PM, BE, AI. 작업 D 문서 D3, D4, D6 |
| 13 | 면회 제안을 승인해 만드는 생애 정보의 분류를 AI가 제안할지 보호자가 고를지. 해결(PM 결정 2026-11-09, #139): AI가 이야기 후보마다 분류를 붙이고(8-3, 7-3의 `storyCategory`) 보호자가 승인 때 바꿀 수 있다(7-4의 선택 `storyCategory`). 만든 뒤에도 일대기에서 2-7로 바꾼다. 서버는 11/10 배포(develop `83695093`)부터 운영에 있고, 승인 때 분류를 고르는 앱 화면은 새 APK를 만들어야 휴대폰에 들어가며 설치된 앱(Play와 11/8 Releases APK)에는 없다 | 7-3, 7-4, 8-3 | PM, AI, FE, BE. 작업 D 문서 D5 |
