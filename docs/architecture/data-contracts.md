# 공통 데이터 계약

- 상태: v0.2, [API 명세](api-spec.md)의 요청과 응답 기준. 실제 저장과 모델 연동에 필요한 미결 항목 포함
- 아래 예시는 모두 합성 데이터다. 구현 과정에서 변경할 수 있지만 필드와 enum 변경은 세 영역이 공동 검토한다.

## 현재 적용 범위

PR #37의 문서 정리는 기존 JSON과 enum을 유지했고, PR #38에서 Account의 `loginId`를 `authProvider`로 바꾸고 nullable `email`을 반영했다. v0.2에서는 [API 명세](api-spec.md)와 변경된 DB 스키마([init.sql](../../backend/database/init.sql))에 맞춰 피보호자 기본 정보와 사진의 서버 저장, 비동기 카드 생성, 계산되는 회차 상태, 평가 제출 뒤 음성 제출 순서를 반영했다. 객체의 필드는 API 명세의 응답 객체와 같으며, 앱과 BE의 경로, 요청과 오류 코드는 API 명세를 따른다. 아래의 나머지 차이는 실제 연동 전에 FE, AI, BE와 PM이 함께 맞춰야 한다.

| 항목 | 현재 계약 또는 목 화면 | 적용할 기준과 남은 일 |
| --- | --- | --- |
| 알림 동의 | 공통 계약, FE와 BE 모두 선택 | [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)에서 BE 규칙과 회귀 테스트를 맞춤. 실제 앱 로그인 연동 검증은 PR #50의 후속 작업 |
| 목 데이터 | `mock/`의 합성 데이터와 FE 파싱은 v0.2 이전 형식. `profile.json`의 사진만 v0.2 `ProfilePhoto` 목록으로 갱신함 | 나머지 v0.2 객체에 맞춰 갱신 필요 |
| 사진 저장 | v0.2에서 프로필 사진과 면회 사진을 서버(S3)에 저장하도록 변경 | 프로필 사진의 `mock/`과 FE 파싱은 `imageUrl`로 갱신함. 면회 사진(`VisitPhoto`)의 `localUri` 갱신 필요. [법률 문서](../legal/README.md), [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md), [ADR-006](decisions/ADR-006-server-side-ai-processing.md)의 이미지 원본 임시 처리 문구를 새 저장 방식에 맞춰 갱신 필요 |
| 카드 수와 선택 | 12장 생성, 9장 제시와 3장 보충, 보호자 선택으로 명시 | [PM 미결 항목](../pm/README.md#검토-중인-제품-결정)과 달라 확정 여부 확인 필요. 이번 정리에서 수치와 선택 규칙은 변경하지 않음 |
| 이미지 출력 | 태그 후보 대신 사진마다 설명 한 문장(`description`) | 보호자 확인 방식([API 3-3](api-spec.md#3-3-사진-설명-확인--미정))이 정해질 때까지 카드 생성에 쓰지 않음 |
| 피보호자 동의 | 회차마다 동의를 받지 않음. 녹음과 음성 처리 동의는 가입 때 보호자의 필수 동의로 받음 | 피보호자 본인 확인과 대리 동의의 자격과 절차는 법률 검토 필요 |
| 저장과 상태 전이 | [API 명세](api-spec.md)에 저장 API와 상태 전이 정의. 구현 전 | [이슈 18](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/18)에서 접근 권한, 보관 기간과 삭제 범위 합의 |
| 직접 식별정보 | 피보호자의 이름, 성별, 생년월일을 서버의 프로필에 저장. AI 서버 요청에는 넣지 않고 BE가 계산한 연령대만 보냄 | 서버 저장의 목적, 동의 근거와 보관 기간을 [법률 문서](../legal/README.md)에 반영 필요 |
| 보호자 평가 | PR #42로 미사용, 미응답과 중립 평가를 구분하는 화면 및 계약 반영 | 2026-09-19 PM 결정으로 미사용 및 미응답만으로 비선호 추정, 추천 하향 및 제외 금지. 카드 평가는 카드별로 저장하며 미응답은 `null`([API 6-1, 6-4](api-spec.md#6-평가와-음성-제출)) |
| 승인된 사실의 출처 | 변경 제안을 승인해 만든 LifeFact는 그 제안을 출처로 저장 | 면회 삭제 시 승인된 사실은 유지하고 해당 출처 연결만 해제. 회차 삭제 기능과 삭제 후 처리의 구현은 후속 작업 |
| 리포트 | 일기형 요약과 카드별 요약 | 테크스펙의 관찰값과 계산 불가 이유를 어떤 필드로 전달할지 조율 |

공통 규칙과 [객체 목록](#객체와-담당)에서 필요한 항목으로 이동한다. [결정 대기 항목](#결정-대기-항목)의 카드 생성, STT와 주제 갱신은 아직 완성된 처리 계약이 아니다.

## 공통 규칙

| 항목 | 기준 |
| --- | --- |
| JSON 필드 | `lowerCamelCase` |
| 시간 | 시간대를 포함한 ISO 8601 문자열. 날짜만 필요한 값은 `YYYY-MM-DD` |
| 음성 구간 | 밀리초 정수 |
| 없는 값 | 빈 문자열 대신 `null` |
| 빈 목록 | 빈 배열 |
| 버전 | 최상위 `schemaVersion` |
| 신뢰도 | 0.0 이상 1.0 이하, 제공할 수 없으면 `null` |
| 오류 | `errorCode`와 사용자용 `message` 분리 |
| ID | 서버가 발급하는 UUID 문자열. `mock/`의 `*_demo_*`는 읽기 쉽게 쓴 합성 값 |
| 이미지 조회 | `imageUrl`은 수명이 짧은 S3 Presigned GET URL. `imageUrlExpiresAt`이 지나면 해당 자원을 다시 조회 |

- 피보호자의 이름, 성별, 생년월일 같은 직접 식별정보와 로컬 파일 경로는 AI 서버 요청에 포함하지 않는다.
- 원본 음성은 BE가 처리 동의를 확인한 경우에만 서버에 임시 저장한다. STT 직후 삭제하며 최대 24시간을 넘기지 않는다. 동의 확인 이력과 삭제 상태는 BE가 관리한다.
- 전사문은 리포트를 저장할 때까지만 임시 보관하며, 늦어도 STT 완료 후 24시간이 지나면 지운다.
- 사진은 BE가 S3에 서버 측 암호화로 저장하며 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 모두 이미지 분석을 요청하고 면회 사진은 요청하지 않는다.
- BE는 AI 서버에 원본을 수명이 짧은 S3 Presigned GET URL로만 전달한다.

<br>

## 화면 흐름

    구글 로그인 → 필수 동의 확인
    → 기본 정보 입력 → 세부 정보 입력 → 사진 첨부 → 사진 분석 결과 확인
    → 대화 카드 선택 → 면회 사진 촬영
    → 녹음 → 면회 중 대화 카드 → 대화 카드 보충
    → 보호자 평가 → 음성 제출
    → 리포트 → 변경 사항 확인

- 별도의 회원가입 단계를 두지 않는다. 구글 인증에 성공하면 필수 동의를 확인하고, 동의가 완료될 때 계정과 동의 이력을 함께 만든다. 녹음과 음성 처리 동의도 이때 필수 동의로 함께 받는다. 동의를 거부하거나 중단하면 계정을 만들지 않는다. 현재 구현은 최초 가입 시 동의만 처리하며, 약관 변경 시 재동의는 후속 설계한다.
- 로그인 뒤 프로필이 없으면 기본 정보 입력부터, `setupStatus`가 `inProgress`이면 세부 정보 입력부터 이어서, `completed`이면 홈으로 간다.
- 세부 정보는 프로필 입력을 마칠 때 한 번에 보내며, 이때 카드 생성을 시작한다. 홈의 `오늘의 대화카드 받기`는 생성이 끝난 뒤 활성화한다.
- 사진 분석 결과를 보호자가 확인하는 방식은 아직 정하지 않았다([API 3-3](api-spec.md#3-3-사진-설명-확인--미정)).
- 면회 사진은 녹음 전에 단말에서 찍는다. 회차는 녹음을 시작할 때 만들고 사진은 그 뒤에 올린다. 녹음 일시정지와 종료는 단말에서 처리한다.
- 보호자 평가를 제출한 뒤 면회 음성을 제출한다. 리포트는 STT 결과와 보호자 평가로 만든다.
- 마이페이지에서 프로필 수정과 리포트 기록 확인을 할 수 있으며 위 흐름과 별개로 언제든 진입 가능하다.

<br>

---

## 객체와 담당

| 객체 | 만드는 쪽 | 읽는 쪽 |
| --- | --- | --- |
| [Account](#계정-account) | BE | FE |
| [Profile](#프로필-profile) | FE, BE | FE, BE |
| [LifeFact](#확인된-생애-사실-lifefact) | FE, BE | FE, BE, AI |
| [LifeFactCollectionState](#생애-정보-입력-상태-lifefactcollectionstate) | FE | FE |
| [ProfilePhoto](#프로필-사진-profilephoto) | FE, BE | FE, BE |
| [ImageAnalysisCandidate](#이미지-분석-후보-imageanalysiscandidate) | AI | BE, FE |
| [CardGenerationRequest](#카드-생성-요청-cardgenerationrequest) | BE | AI |
| [CardSet](#대화-카드-묶음-cardset) | AI, BE | FE |
| [VisitSession](#면회-회차-visitsession) | FE, BE | FE |
| [VisitPhoto](#면회-사진-visitphoto) | FE, BE | FE |
| [SpeechAnalysisJob](#비동기-음성-분석-작업-speechanalysisjob) | BE | FE, BE |
| [SpeechAnalysisResult](#stt와-화자-처리-결과-speechanalysisresult) | AI | BE |
| [CaregiverEvaluation](#보호자-평가-caregiverevaluation) | FE | FE, BE, AI |
| [VisitReport](#리포트-초안-visitreport) | AI, BE | FE |
| [ChangeProposal](#변경-제안-changeproposal) | AI | FE, BE |

- `LifeFactCollectionState`는 단말에만 둔다. 나머지 객체는 BE가 저장하며, `SpeechAnalysisResult`의 전사문은 리포트를 저장할 때까지만 임시 보관한다. 접근 권한, 보관 기간과 삭제 범위는 아직 확정하지 않았다.
- 앱과 BE 사이의 요청과 응답은 [API 명세](api-spec.md)를 따른다. BE와 AI 서버 사이의 요청은 API 명세의 내부 API를 따른다.
- `Account`는 백엔드가 구글 ID 토큰을 검증하고 필수 동의가 완료될 때 서버에서 만든다. FE는 로그인과 동의 화면을 제공하고 결과를 읽는다.
- 카드의 `selected`와 변경 제안의 `reviewStatus`처럼 사용자가 확인해서 바꾸는 값은 AI가 만든 객체라도 FE의 요청([API 5-1, 5-3](api-spec.md#5-면회), [7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규))으로 BE가 바꾼다.

<br>

---

## 계정 (Account)
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

- 인증은 구글 소셜 로그인을 사용하며 백엔드가 ID 토큰을 직접 검증하는 방향에 PM이 동의했다. 개인정보 저장 항목 등 [ADR-007](decisions/ADR-007-google-social-login.md)의 검토안은 별도로 남아 있다. 아이디와 비밀번호는 받지 않으며, 계정은 구글 인증 뒤 필수 동의가 완료될 때 동의 이력과 함께 만들어진다.
- `authProvider`의 값은 현재 `google` 하나다. 다른 제공자를 더하는 것은 계약 변경으로 본다.
- `displayName`과 `email`의 영구 저장 범위는 검토 중이다. PM은 이메일과 구글 계정 이름을 저장하지 않는 안을 제안했고 BE와 FE가 구현 영향을 확인한다([ADR-007](decisions/ADR-007-google-social-login.md)). 현재 서버의 기본 설정에서는 사용자 입력 표시 이름이 없으면 `보호자`를 사용하고 `email`은 `null`로 반환한다. `displayName`에는 실명이 들어올 수 있으므로 사용자가 수정할 수 있어야 한다.
- `email`은 문자열 또는 `null`이다. 서버가 값을 저장하지 않거나 제공하지 않는 경우 `null`로 보내며, FE는 이를 임의의 주소나 빈 문자열로 채우지 않는다. 누락된 `email`도 FE에서 없는 값으로 읽는다. nullable 응답을 지원하는 변경이며 이메일 미저장 정책을 확정한 것은 아니다.
- `serviceData`(개인정보 수집 동의)와 `sensitiveData`(민감정보 수집 동의)는 필수 동의 사항이며 거부하면 가입을 진행하지 않는다. 녹음과 음성 처리 동의는 가입 때의 필수 동의로 함께 받으며 면회 회차마다 따로 받지 않는다.
- 나머지 둘(`serviceImprovement` 데이터를 서비스 개선에 활용, `pushNotification` 알림 수신)은 선택 동의이며 거부해도 가입과 핵심 기능을 차단하지 않는다.
- 동의가 바뀔 때마다 이력을 추가하며 `consent`는 가장 최근 이력이다. `consentVersion`은 그 이력의 약관 버전이다.
- 가입 후에는 선택 동의만 마이페이지에서 바꿀 수 있다([API 1-6](api-spec.md#1-6-patch-authmeconsents--신규)). `grantedAt`은 동의 중인 항목이면 거부에서 동의로 바뀐 가장 최근 이력의 시각이고, 처음부터 동의했으면 가입 시각이다. 거부 중이면 `null`이다.
- `pushNotification`을 거부한 계정에는 푸시 알림을 보내지 않는다. 홈 화면은 회차 목록([API 5-4](api-spec.md#5-4-get-apiv1profilesprofileidvisit-sessions--신규))의 `sessionStatus`로 리포트 도착을 표시하므로, 알림을 거부해도 리포트를 받아볼 수 있다.
- 앱은 구글에서 받은 ID 토큰을 백엔드로 보내고, 백엔드가 구글 공개키로 검증한 뒤 기존 계정을 찾거나 필수 동의 완료 시 계정을 만든다. 제공자 식별자(구글 `sub`), 비밀번호와 인증 토큰은 이 계정 객체에 포함하지 않는다.
- 탈퇴하면([API 1-5](api-spec.md#1-5-delete-authme--수정)) 계정과 동의 이력, 프로필과 그 아래의 모든 기록을 지운다. 사진과 음성 원본은 S3 삭제 대기열로 지운다. 탈퇴 이유는 계정과 연결하지 않고 저장한다.
- PR 50의 약관 서버 관리, 앱 재실행 시 세션 복원과 만료 후 자동 재인증은 후속 구현 요청이다. 이 계정 계약 변경만으로 해당 기능이 완료되지는 않는다.

**없어도 되는 값** — `email`, 선택 동의 항목의 `grantedAt`

<br>

---

## 프로필 (Profile)

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

- 계정당 프로필은 1개다.
- `setupStatus` 값은 `inProgress`, `completed`이다. 저장하지 않고 계산하며, 카드 생성 작업이 하나라도 있으면 `completed`, 없으면 `inProgress`다. 기본 정보 입력을 마치면 `inProgress`로 만들어지고, 프로필 입력을 마치면([API 2-5](api-spec.md#2-5-post-apiv1profilesprofileidcomplete-setup--신규)) 첫 카드 생성 작업과 함께 `completed`가 된다.
- `name`은 50자 이하다. `gender` 값은 `male`, `female`이다. `birthDate`는 `YYYY-MM-DD`다.
- 피보호자의 이름, 성별, 생년월일은 서버에 저장하지만 AI 서버 요청에는 넣지 않는다. BE가 `birthDate`로 연령대를 계산해 `{십 단위 나이}s` 형식(예: `70s`, `80s`)으로 보낸다.
- `condition.stage` 값은 `mildCognitiveImpairment`, `mildDementia`, `unknown`이다.
- `occupation`, `hometown`, `hobby`, `family`는 세부 정보 네 항목이다. 건너뛰었거나 프로필 입력을 마치기 전이면 `null`이며 빈 문자열은 받지 않는다. 수정할 때 `null`을 보내면 지운다.
- 세부 정보를 음성과 텍스트 중 어떤 방식으로 입력했는지와 항목별 입력 시도 상태는 [LifeFactCollectionState](#생애-정보-입력-상태-lifefactcollectionstate)로 단말에서만 쓰고 보내지 않는다.

**없어도 되는 값** — `condition.symptomNote`, `occupation`, `hometown`, `hobby`, `family`

<br>

---

## 확인된 생애 사실 (LifeFact)

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

- 세부 정보 네 항목 밖의 생애 정보다. 네 항목은 [Profile](#프로필-profile)의 필드로 저장한다.
- `title`은 100자 이하이며 `title`과 `content`는 비울 수 없다.
- 두 경로로 만든다. 보호자가 마이페이지에서 추가하거나([API 2-6](api-spec.md#2-6-post-apiv1profilesprofileidlife-facts--신규)), 보호자가 변경 제안의 생애 정보 제안을 승인하면([API 7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규)) BE가 만든다. 승인으로 만든 사실은 그 제안을 출처로 저장하며 응답에는 출처를 담지 않는다.
- 출처 면회가 삭제되면 보호자가 승인한 사실은 유지하고 해당 출처 연결만 해제한다. 생성 시 출처 연결과 삭제 후 연결 해제를 구분하며, 출처 연결을 이유로 회차 삭제를 막지 않는다.
- 이 규칙은 [2026-09-19 PM 결정](../pm/README.md#2026-09-19-pm-결정)에 따른 면회 기록 삭제 범위다. 계정 탈퇴와 프로필 삭제 범위를 정하거나, 삭제 행동을 부정적 감정 및 비선호로 해석하지 않는다. DB 삭제 동작과 연결이 없는 사실의 화면 표시는 후속 검증이 필요하다.
- 마이페이지에서 내용을 고칠 수 있다([API 2-7](api-spec.md#2-7-patch-apiv1life-factsfactid--신규)).

<br>

---

## 생애 정보 입력 상태 (LifeFactCollectionState)

> **단말 전용.** 서버에 보내지 않는다.

```json
{
  "schemaVersion": 1,
  "profileId": "00000000-0000-4000-8000-000000000101",
  "categories": [
    {
      "category": "occupation",
      "status": "collected",
      "attemptCount": 1
    },
    {
      "category": "hometown",
      "status": "skipped",
      "attemptCount": 0
    },
    {
      "category": "hobby",
      "status": "manualFallback",
      "attemptCount": 2
    },
    {
      "category": "family",
      "status": "collected",
      "attemptCount": 1
    }
  ]
}
```

- `category` 값은 세부 정보 네 항목인 `occupation`, `hometown`, `hobby`, `family`이다.
- `status` 값은 `pending`, `collected`, `skipped`, `manualFallback`이다.
- 음성 인식이 2회 실패하면 `manualFallback`으로 전환한다.
- 프로필 입력을 마칠 때 건너뛴 항목은 `null`로 보낸다.

<br>

---

## 프로필 사진 (ProfilePhoto)

온보딩의 사진 첨부와 마이페이지의 갤러리 추가에서 올린 사진이다. 첨부는 선택이며 프로필당 최대 5장이다.

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

- 사진 원본은 JPEG 또는 PNG이며 BE가 S3에 저장한다. `imageUrl`은 수명이 짧은 조회용 URL이다.
- 프로필 사진은 모두 이미지 분석을 거친다. 분석의 동의 근거는 아직 정하지 않았다([결정 대기 항목](#결정-대기-항목)).
- `analysisStatus` 값은 `pending`, `processing`, `completed`, `failed`이다.
  - 분석에 실패해도 프로필 입력을 계속 진행할 수 있어야 한다.
  - `description`은 `completed`일 때만 채우고 그 밖에는 `null`이다. 다루는 기준은 [ImageAnalysisCandidate](#이미지-분석-후보-imageanalysiscandidate)를 따른다.
  - `failed`이면 `error`에 `{ "errorCode": "..." }`를 담고, 그 밖에는 `null`이다.

**없어도 되는 값** — `description`, `error`

<br>

---

## 이미지 분석 후보 (ImageAnalysisCandidate)

AI가 프로필 사진 한 장에 대해 만드는 설명 한 문장이다. 이전 계약의 태그 후보 목록 대신 사용한다. BE가 [API 8-4](api-spec.md#8-4-post-internalv1image-analyses--신규)로 요청하고, 결과는 `ProfilePhoto.description`으로 앱에 전달한다.

```json
{
  "schemaVersion": 1,
  "photoId": "00000000-0000-4000-8000-000000000121",
  "model": "synthetic-model",
  "promptVersion": "image-v1",
  "description": "한복을 입은 사람들이 잔치 자리에 모여 있는 사진이에요."
}
```

- 프로필 사진만 요청하며 면회 사진은 요청하지 않는다. 원본은 S3 Presigned GET URL로만 전달한다.
- `model`과 `promptVersion`은 결과와 함께 저장한다.
- `description`은 AI가 만든 후보이며 확인된 사실이 아니다. 보호자가 설명을 확인하거나 고치는 방식과 확인 여부의 저장 위치([API 3-3](api-spec.md#3-3-사진-설명-확인--미정))가 정해질 때까지 카드 생성 요청에 넣지 않는다.
- 사진 메타데이터는 이 객체의 확정값이 아니라 AI 분석에 제공할 수 있는 보조 입력이다. 누락되거나 원래 사건과 다른 값일 수 있으므로 메타데이터만으로 생애 사실과 스토리를 확정하지 않는다.
- AI 설명과 문맥 정보도 보호자가 확인하기 전에는 후보로만 취급한다. 메타데이터를 보조 입력으로 제한하는 측정 근거는 [사진 메타데이터 추출 보고서](../../local_ai/docs/image_tagging/metadata-extraction-report.md)에 기록한다.

<br>

---

## 카드 생성 요청 (CardGenerationRequest)

> **상태: 요청 형식은 [API 8-2](api-spec.md#8-2-post-internalv1card-generations--신규) 기준.** 카드 생성과 추천은 핵심 기능으로 별도 설계한다. [PM 제품 기준](../pm/README.md#카드-미사용과-추천-제외)을 지키며 각 값을 생성에 어떻게 쓸지는 AI가 로직으로 정하고 PM, FE와 BE가 제품 및 연동 범위를 함께 확인한다.

BE가 카드 생성 작업을 만들 때 프로필 값으로 만들어 AI 서버에 보낸다. 앱은 이 객체를 보내지 않는다.

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

- `ageRange`는 BE가 생년월일로 계산한 값이다. 피보호자의 이름, 성별, 생년월일은 넣지 않는다.
- `profileFacts`는 [Profile](#프로필-profile)의 세부 정보 네 항목이다.
- `topics`는 이 프로필의 기존 주제와 보호자가 승인한 주제 피드백이며 첫 생성에는 빈 배열이다.
- 사진 설명은 [API 3-3](api-spec.md#3-3-사진-설명-확인--미정)이 정해질 때까지 넣지 않는다.
- BE는 요청의 `context`를 카드 생성 작업의 기록으로 저장한다.
- AI 응답 형식은 API 8-2를 따른다. 카드 12장을 만들고 새 주제는 제목과 설명으로 돌려주며, BE가 카드와 새 주제에 ID를 부여한다.

<br>

---

## 대화 카드 묶음 (CardSet)

카드 생성 작업과 그 결과인 카드 12장이다. API에서 카드 생성 작업의 응답으로 사용한다([API 4절](api-spec.md#4-대화-카드)).

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

- 카드 생성은 비동기 작업이다. 프로필 입력을 마칠 때, 변경 제안을 검토한 뒤와 실패 후 다시 시도할 때 만든다. 변경 제안이 없는 리포트 뒤의 생성 시점은 아직 정하지 않았다.
- `generationStatus` 값은 `running`, `completed`, `failed`이다. 프로필마다 `running`인 작업은 하나뿐이다.
  - `cards`는 `completed`일 때 12장이고 그 밖에는 빈 배열이다. `cardId`는 BE가 부여한다.
  - `failed`이면 `error`에 `{ "errorCode": "..." }`를 담고, 그 밖에는 `null`이다.
- `usedBySessionId`는 이 카드 묶음으로 만든 회차이며 없으면 `null`이다. 홈의 `오늘의 대화카드 받기`는 최신 작업이 `completed`이고 `usedBySessionId`가 `null`일 때 활성화한다.
- `position` 1~9가 선택 화면 대상이고 10~12가 면회 중 보충용이다.
- `topic`은 프로필의 주제이며 `topicId`로 회차 간에 같은 주제를 잇는다. 한 묶음 안에서 주제는 겹치지 않는다.
- `topic.description`과 `description`은 보호자에게 주제와 카드를 알려주는 설명이다. 어르신에게 그대로 여쭙는 문장은 `primaryQuestion`이며 둘은 역할이 다르다.
- `followUpQuestions`는 카드마다 3개다.
- `evidenceSource` 값은 `lifeFact`, `photo`, `none`이다. `none`이면 `evidence`는 빈 배열이다. `evidence` 항목의 형식은 아직 정하지 않았다.
- `selected`는 회차를 만들 때 고른 카드와 면회 중 보충 화면에서 추가한 카드가 `true`다. 선택하지 않은 카드도 삭제하지 않는다.

**없어도 되는 값** — `error`, `usedBySessionId`

<br>

---

## 면회 회차 (VisitSession)

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

- 회차는 녹음을 시작할 때 고른 카드로 만든다([API 5-1](api-spec.md#5-1-post-apiv1visit-sessions--신규)). `startedAt`은 서버 수신 시각이다.
- 녹음 일시정지와 종료는 단말에서 처리하며 서버에 알리지 않는다.
- `selectedCardIds`는 회차를 만들 때 카드 묶음의 `position` 1~9에서 1~9개를 고르고, 면회 중 10~12에서 고른 카드를 더한다.
- `sessionStatus`는 저장하지 않고 평가, 음성 분석 작업과 리포트로 계산한다.

| `sessionStatus` | 조건 |
| --- | --- |
| `evaluationPending` | 보호자 평가 전 |
| `audioPending` | 평가 후 음성 접수 전. 작업이 없거나 업로드 단계에서 실패한 작업만 있음 |
| `processing` | 음성 분석 작업이 `queued`, `transcribing`, `sttCompleted`, `generatingReport` |
| `completed` | 리포트 저장 |
| `failed` | 접수된 음성 분석 작업이 `failed` |

- 녹음과 음성 처리 동의는 가입 때 받으므로 회차에서 받지 않는다.
- `participantCount`는 녹음을 끝낼 때 보호자가 확인한 1~8의 인원수다. 음성과 함께 제출하며 STT 요청의 `speakerCount`로 이름만 바꾸어 전달한다. 앱이나 서버가 추정하지 않는다.
- `photoId`는 면회 사진을 올리면 채운다. 사진 없이 시작하면 `null`이다.
- `participantCount`와 `analysisId`는 음성 접수 후 채우며 가장 최근 작업의 값이다.

**없어도 되는 값** — `photoId`, `participantCount`, `analysisId`

<br>

---

## 면회 사진 (VisitPhoto)

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

- 사진은 녹음 전에 단말에서 찍고 회차를 만든 뒤 올린다([API 5-2](api-spec.md#5-2-post-apiv1visit-sessionssessionidphoto--신규)).
- 사진 원본은 JPEG 또는 PNG이며 BE가 S3에 저장한다. `imageUrl`은 수명이 짧은 조회용 URL이다.
- 회차가 `evaluationPending`일 때만 받으며, 다시 올리면 기존 사진을 지우고 교체한다.
- 이미지 분석을 하지 않는다.
- 촬영하지 않으면 올리지 않고 `VisitSession.photoId`를 `null`로 둔다.

<br>

---

## 비동기 음성 분석 작업 (SpeechAnalysisJob)

> **상태: ADR-008 제안 및 BE 구현 검증 중.** FE, AI, PM 공동 확인 전에는 실제 사용자
> 자료 전송 승인을 뜻하지 않는다.

앱은 보호자 평가를 제출한 뒤 WAV와 `participantCount`를 multipart 요청으로 제출한다.
BE는 `audioPending`인 회차만 받으며, 원본을 S3에 임시 저장하고 작업을 영속화한 뒤 다음
`202 Accepted` 응답을 반환한다. 접수하면 회차의 `sessionStatus`는 `processing`이 되고,
앱은 `202`를 받으면 단말의 WAV 파일을 삭제한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "status": "queued"
}
```

`GET /api/v1/speech-analyses/{analysisId}`는 같은 계정이 소유한 작업에 한해 다음 상태를
반환한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "00000000-0000-4000-8000-000000000601",
  "sessionId": "00000000-0000-4000-8000-000000000201",
  "status": "transcribing",
  "errorCode": null
}
```

- 공개 상태는 `queued`, `transcribing`, `sttCompleted`, `generatingReport`,
  `completed`, `failed`다.
- `sttCompleted`는 AI 응답 검증과 원본 삭제까지 끝났지만 리포트는 아직 준비되지 않은 상태다.
- `completed`는 STT뿐 아니라 리포트와 변경 제안 저장까지 끝난 상태다.
- 실패 시 `errorCode`만 제공하며 AI 오류 본문, 전사문, S3 URL과 객체 키를 제공하지 않는다.
- 업로드 단계에서 실패한 작업만 있으면 새 작업을 만들고, 접수된 작업이 처리 중이면 그 작업을 반환한다. 접수 후 실패했거나 완료된 회차는 다시 받지 않는다.
- 자세한 상태 전이, 삭제와 재시도 경계는 [ADR-008](decisions/ADR-008-stt-pipeline.md)을 따른다.

<br>

---

## STT와 화자 처리 결과 (SpeechAnalysisResult)

> **상태: v1 구현.** BE가 동의를 확인한 요청만 AI 서버에 전달하며 동의 이력은 BE가 관리한다.

- 전사문은 화면에 표시하지 않으며 리포트 생성 요청([API 8-3](api-spec.md#8-3-post-internalv1visit-reports--신규))의 입력으로만 사용한다. 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록 작업에 임시 저장하고, 리포트를 저장하면 지운다. 늦어도 STT 완료 후 24시간이 지나면 지운다.
- 입력 음성은 WAV/PCM 16-bit/16kHz/mono 규격으로 고정한다.
- 운영에서는 S3 Presigned GET URL을 사용하고, `localFile`은 개발과 테스트 환경에서만 허용한다.
- `SPEAKER_00` 같은 값은 파일 안의 화자 군집 라벨이며 보호자 또는 피보호자 역할을 뜻하지 않는다.
- 화자를 명확하게 배정할 수 없는 구간의 `speakerLabel`은 `null`이다.

BE에서 AI로 보내는 운영 요청은 다음과 같다.

```json
{
  "schemaVersion": 1,
  "analysisId": "analysis_demo_001",
  "language": "ko",
  "speakerCount": 2,
  "audioSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/audio.wav?...",
    "downloadUrlExpiresAt": "2026-09-22T15:10:00+09:00",
    "sizeBytes": 123456,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "dataExpiresAt": "2026-09-22T16:00:00+09:00"
}
```

AI에서 BE로 반환하는 성공 응답은 다음과 같다.

```json
{
  "schemaVersion": 1,
  "analysisId": "analysis_demo_001",
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
        {
          "startMs": 0,
          "endMs": 800,
          "text": "합성",
          "probability": 0.93
        }
      ]
    }
  ]
}
```
> **상태: AI v1 결과를 BE worker가 소비하는 내부 계약.** 공개 상태 계약과 원본 처리
> 경계는 ADR-008의 공동 검토가 남아 있다.

BE가 AI 서버로 보내는 요청은 다음과 같다.

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
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

AI 성공 응답은 다음과 같다.

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
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
        {"startMs": 0, "endMs": 800, "text": "합성", "probability": 0.93}
      ]
    }
  ]
}
```

- 입력은 WAV/PCM 16-bit/16kHz/mono이고 `speakerCount`는 1~8이다.
- `SPEAKER_00` 등의 값은 파일 안의 화자 군집이며 실제 인물 역할을 뜻하지 않는다.
- 화자를 명확히 배정할 수 없는 구간의 `speakerLabel`은 `null`이다.
- 전사문은 화면에 표시하지 않으며 리포트 생성 입력으로만 사용한다.

<br>

---

## 보호자 평가 (CaregiverEvaluation)

리포트보다 먼저 만들어지며 리포트 생성의 입력이 된다. 보호자 평가 화면의 `리포트 만들기`에서 제출하고 이어서 면회 음성을 제출한다. 회차가 `evaluationPending`일 때 한 번만 받으며, 저장하면 회차는 `audioPending`이 된다.

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
    },
    {
      "cardId": "00000000-0000-4000-8000-000000000502",
      "wasUsed": false,
      "caregiverReaction": null
    }
  ],
  "freeNote": null,
  "evaluatedAt": "2026-08-21T14:25:00+09:00"
}
```

- `conversationSatisfaction`은 1 이상 5 이하의 정수다.
- `careRecipientReaction` 값은 `pleased`, `calm`, `angry`, `lowEnergy`, `unknown`이다.
- `caregiverReaction` 값은 `positive`, `neutral`, `negative`이다.
- `cardReviews[].cardId`는 회차의 `selectedCardIds` 안에 있어야 한다.
- `cardReviews`는 **미사용과 미응답을 구분한다.** 어느 쪽도 그 사실만으로 비선호를 추정하거나 추천 순위를 낮추거나 추천 대상에서 제외하지 않는다.

| 보호자가 한 일 | `cardReviews` | 추천에 반영할 기준 |
| --- | --- | --- |
| 카드를 쓰고 평가했다 | `wasUsed`가 `true`이고 `caregiverReaction`을 담는다 | 명시된 평가는 보존하되 가중치와 반영 방식은 별도 추천 로직에서 정한다 |
| 쓰지 않았다고 답했다(미사용) | `wasUsed`가 `false`이고 `caregiverReaction`은 `null`이다 | 미사용만으로 비선호를 추정하거나 추천을 낮추거나 제외하지 않는다 |
| 답하지 않고 넘어갔다(미응답) | 그 카드를 **담지 않는다** | 응답이 없으므로 비선호를 추정하거나 추천을 낮추거나 제외하지 않는다 |

- 미응답을 미사용으로 읽지 않는다. 미사용도 시간 부족이나 나중에 이야기하려는 선택일 수 있어 사용자의 의도를 대신 판단하지 않는다.
- 추천 대상 제외는 사용자가 명시적으로 선택했을 때 적용한다. 이는 과거 카드와 면회 기록 삭제가 아니다. API 명세에서는 보호자가 주제 제안의 `exclude`를 승인할 때([API 7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규)) 주제 단위로 적용하며, `wasUsed=false`로 대신 표현하지 않는다. 제안 없이 보호자가 직접 제외를 고르는 기능은 아직 정하지 않았다.
- 리포트의 `cardSummaries`는 평가한 카드만 담는다. 리포트 화면은 미사용과 미응답을 이 평가([API 6-4](api-spec.md#6-4-get-apiv1visit-sessionssessionidevaluation--신규))로 분석 결과 대신 그 사실로 표시한다.

**없어도 되는 값** — `freeNote`, `wasUsed`가 `false`일 때의 `caregiverReaction`

<br>

---

## 리포트 초안 (VisitReport)

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

- 리포트는 회차에 저장하며 회차 ID로 조회한다([API 7-2](api-spec.md#7-2-get-apiv1visit-sessionssessionidreport--신규)). 음성 분석 작업이 `completed`가 되면 조회할 수 있다.
- 리포트 확인 여부는 저장하지 않는다. 홈 화면은 회차의 `sessionStatus`가 `completed`이면 리포트 도착을 표시하며, 확인한 뒤의 표시는 아직 정하지 않았다.
- `title`, `body`와 `cardSummaries[].summary`는 AI가 만든다([API 8-3](api-spec.md#8-3-post-internalv1visit-reports--신규)).
- `body`는 일기 형식의 본문이다.
  - 보호자 평가에서 입력받은 값을 모두 재료로 사용하며, 입력하지 않은 값은 빼고 작성한다.
- `visitDate`는 회차 `startedAt`의 한국 시간 날짜다.
- `mood`는 보호자의 감정이며 별도로 입력받지 않고 BE가 `conversationSatisfaction`에서 계산한다. AI가 만들지 않는다.
  - 값은 `hard`, `normal`, `good`이며 1~2는 `hard`, 3은 `normal`, 4~5는 `good`이다.
- `photo`는 면회 사진이며 없으면 `null`이다.
- `cardSummaries`는 보호자가 `positive`, `neutral`, `negative`로 평가한 카드만 담는다.
- 리포트는 보호자 평가와 대화 내용을 정리해 보여주며 의료적 해석과 대화 품질 점수를 만들지 않는다.

**없어도 되는 값** — `photo`

<br>

---

## 변경 제안 (ChangeProposal)

> **상태: 산출 방식 결정 대기.** 주제 관리 방식은 AI 영역에서 확정한다. 아래는 변경 사항 확인 화면과 [API 7-3, 7-4](api-spec.md#7-리포트와-변경-제안)에 필요한 값이며 산출 방식 제안이 아니다.

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

- 변경 제안은 생애 정보 제안과 주제 제안 두 가지이며 회차마다 0개 이상이다. AI가 리포트와 함께 만들고 `proposalId`는 BE가 부여한다.
- 기존 생애 사실의 수정은 제안하지 않으며 사용자가 마이페이지에서 직접 수정한다.
- 주제 제안은 다음 카드 생성에서 이 주제를 더 다룰지, 덜 다룰지, 제외할지에 대한 제안이며 주제 단위로 적용한다. 회차에서 고른 카드당 최대 1개다.
  - `suggestedAction` 값은 `more`, `less`, `exclude`이다.
  - 카드를 쓰지 않았거나 답하지 않았다는 사실만으로 `less`, `exclude`를 제안하지 않는다(2026-09-19 PM 결정).
- `reviewStatus` 값은 `pending`, `accepted`, `rejected`이다. 제안은 승인 전까지 프로필에 반영하지 않는다.
- 검토는 회차의 `pending` 제안을 모두 한 번에 보낸다. 화면에 남긴 항목은 `accepted`, 제외한 항목은 `rejected`다. `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- `accepted`인 생애 정보 제안은 BE가 그 제안을 출처로 하는 [LifeFact](#확인된-생애-사실-lifefact)로 만든다. `accepted`인 주제 제안은 주제 피드백으로 기록하고 다음 [CardGenerationRequest](#카드-생성-요청-cardgenerationrequest)의 `topics`에 넣는다.
- 승인한 제안을 되돌리는 기능은 없다. 승인으로 만든 생애 사실은 마이페이지에서 직접 고친다.
- 제안이 없는 회차의 확인 처리와, 주제 제안을 승인할 때 보호자가 제안과 다른 행동을 고를 수 있는지는 아직 정하지 않았다.

<br>

---

## 변경 절차

[객체 목록](#객체와-담당)의 이름과 enum은 연동 전에 FE, AI, BE가 함께 확인한다.

- 필드 추가와 enum 값 추가도 계약 변경으로 본다. 한 영역이 단독으로 변경하지 않는다.
- 계약을 변경하면 [API 명세](api-spec.md)와 `mock/`의 합성 데이터를 같은 PR에서 함께 갱신한다.
- 하위 호환성을 깨는 변경은 관련 README와 ADR을 함께 갱신한다.

<br>

---

## 결정 대기 항목

아래 항목은 아직 정해지지 않았다. 확정 전까지 구현으로 먼저 정하지 않는다. 괄호의 번호는 [API 명세의 미정 사항](api-spec.md#미정-사항)이다.

| 항목 | 무엇이 미정인가 | 확인 주체 |
| --- | --- | --- |
| 계정과 로그인 | 구글 로그인 API는 PR #47에 반영됐다. ADR-007과 공통 Account는 `authProvider`, nullable 이메일을 설명한다. 저장 항목과 DB 연결, 앱 로그인 유지는 후속 검토 및 구현이다. | PM, BE, FE |
| 서버 중심 데이터 관리 | 저장 항목은 [API 명세](api-spec.md)에 정의했다. 접근 권한, 보관 기간과 삭제 구현을 정해야 한다. 음성 원본 임시 처리의 최대 24시간 제한은 유지한다. | BE 제안, FE, AI, PM 공동 확인 |
| 사진 보관과 삭제 | 서버에 저장한 프로필 사진과 면회 사진의 보관 기간, 삭제 방법, 탈퇴 시 처리와 이에 맞춘 동의 문구를 정해야 한다. 프로필 사진 삭제 API가 필요한지도 정해야 한다(7). | PM, BE, FE, 법률 문서 |
| 사진 설명 확인 | AI가 만든 사진 설명을 보호자가 확인하거나 고치는 방식과 확인 여부의 저장 위치(1). 정해지기 전에는 카드 생성에 쓰지 않는다. | PM |
| 프로필 사진 분석의 동의 근거 | 이전 계약은 업로드마다 분석 동의를 받았으나 API 명세는 모든 프로필 사진을 분석한다(3). | PM, 법률 문서 |
| 리포트 확인 여부 | 리포트 확인 여부를 저장하지 않아, 확인 후 홈 표시, 제안이 없는 리포트 뒤의 카드 생성 시점과 확인 처리가 정해지지 않았다(2). | PM, BE |
| 피보호자 본인 동의와 대리 동의 | API 명세는 회차마다 동의를 받지 않고 가입 때 보호자의 필수 동의로 녹음과 음성 처리 동의를 받는다. 피보호자 본인 확인과, 병세가 진행되어 본인이 동의하기 어려운 경우 누가 어떤 근거로 대신 동의할 수 있는지 정해야 한다. | PM, 법률 문서 |
| 카드 생성 로직 | `CardGenerationRequest`의 요청 형식은 API 8-2를 따른다. 각 값과 주제 피드백을 생성에 어떻게 사용할지, 카드 근거(`evidence`)의 항목 형식(5)은 AI가 정한다. | AI |
| 주제 관리 방식 | 다음 회차에 어떤 주제를 더 자주 다룰지 계산하는 방법을 정해야 한다. 주제는 BE가 부여한 `topicId`로 회차 간에 잇는다. 주제 제안 승인 시 보호자가 제안과 다른 행동을 고를 수 있는지도 정해야 한다(4). | AI, BE |
| STT 저신뢰도와 실패 상태 | 성공 응답 형식은 확정했지만 신뢰도가 낮거나 모델 처리가 실패한 작업의 상태와 오류 계약은 정해지지 않았다. | AI, BE |
