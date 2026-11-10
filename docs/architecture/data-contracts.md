# 공통 데이터 계약

- 상태: v0.2, [API 명세](api-spec.md)의 요청과 응답 기준. 2026-11-10 develop `83695093` 기준 서버 저장과 모델 연동은 구현됐고(같은 커밋이 11/10 운영 배포본이다) 남은 미결 항목은 [결정 대기 항목](#결정-대기-항목)에 둔다
- 아래 예시는 모두 합성 데이터다. 구현 과정에서 변경할 수 있지만 필드와 enum 변경은 세 영역이 공동 검토한다.

## 현재 적용 범위

정정은 즉시 저장하고 영향받은 카드의 사용을 중지한다. 매번 재생성하지 않고 ‘다음 대화 준비’에서 누적 정정을 반영해 카드 묶음 전체를 한 번 재생성한다. 완료 후 카드 선택과 대화 시작을 허용한다.

2026-10-16 PM 기준: [사실 정정과 다음 면회 카드 반영](../pm/README.md#사실-정정과-다음-면회-카드-반영)을 따른다. 사용 중지는 평가의 미사용과 다르며 추천 불이익을 주지 않는다. 갱신 대기와 영향받은 카드, 생성 중 정정 저장 제한을 위한 필드와 API는 당시 담당자 설계 대상이었다.

현재 구현 (2026-11-09 기준): 묶음 단위의 갱신 대기는 [CardSet](#대화-카드-묶음-cardset)과 API 4-2의 `needsRefresh`로, 카드 생성 중 정정 거절은 `CARD_GENERATION_IN_PROGRESS`로 구현했다([API 4절 기준](api-spec.md#사실-정정-후-카드-갱신-기준), 이슈 #158). 프로필 사진의 설명 수정과 삭제도 같은 표시를 남긴다. 카드 한 장 단위의 사용 중지 표시는 없다. 변경 사항 확인에서 주제 결정을 승인한 7-4에도 같은 표시와 생성 중 거절을 적용하고([#277](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/277)), AI 사진 분석이 끝난 것만으로는 표시하지 않는다([#275](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/275)). AI 사진 분석 동의를 거둬 보호자 설명이 없는 사진의 AI 설명이 지워진 프로필도 같은 표시를 남긴다([#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288)). 세 변경은 11/9 승인 배포(develop `59190ba7`)부터 운영에 있고, 그 전 운영의 동작은 [API 4절 기준](api-spec.md#사실-정정-후-카드-갱신-기준)에 적었다.

PR #37의 문서 정리는 기존 JSON과 enum을 유지했고, PR #38에서 Account의 `loginId`를 `authProvider`로 바꾸고 nullable `email`을 반영했다. v0.2에서는 [API 명세](api-spec.md)와 변경된 DB 스키마([init.sql](../../backend/database/init.sql))에 맞춰 피보호자 기본 정보와 사진의 서버 저장, 비동기 카드 생성, 계산되는 회차 상태, 평가 제출 뒤 음성 제출 순서를 반영했다. 객체의 필드는 API 명세의 응답 객체와 같으며, 앱과 BE의 경로, 요청과 오류 코드는 API 명세를 따른다. 아래 표의 남은 일은 FE, AI, BE와 PM이 함께 맞춘다.

| 항목 | 현재 계약 또는 목 화면 | 적용할 기준과 남은 일 |
| --- | --- | --- |
| 알림 동의 | 공통 계약, FE와 BE 모두 선택 | [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)에서 BE 규칙과 회귀 테스트를 맞춤. 앱 로그인은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50), 푸시 기기 등록은 BE API 1-7, 1-8([PR #248](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/248))과 앱의 FCM 등록([PR #247](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/247))으로 연결했고, 11/8 운영 시험에서 리포트 완료 푸시 39건이 실기기에 모두 도착했다([안정성 시험](../../backend/docs/stability-test-20261108.md)) |
| 목 데이터 | `mock/`의 합성 데이터와 FE 파싱은 v0.2 이전 형식. `profile.json`의 사진은 v0.2 `ProfilePhoto` 목록으로, `caregiver-evaluation.json`의 `changeProposal`, `conversation-cards.json`의 `cardSet`과 `visit-session.json`의 `visitSession`은 v0.2로 갱신함 | 나머지 v0.2 객체에 맞춰 갱신 필요 |
| 사진 저장 | v0.2에서 프로필 사진과 면회 사진을 서버(S3)에 저장하도록 변경 | 프로필 사진의 `mock/`과 FE 파싱은 `imageUrl`로 갱신함. 면회 사진(`VisitPhoto`)의 `localUri` 갱신 필요. 보관 문구는 [ADR-001의 PR #92 개정안](decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)으로 정리 중이다. AI 분석 동의는 `photoAnalysis`로 분리해 구현했고([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)) 사진 보관 동의는 아직 없다. S3 삭제 실행기([PR #204](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/204)) 코드는 운영 이미지에 들어 있지만 손으로 실행하는 명령이며, 정기 실행과 실행기를 통한 실제 원본 삭제는 11/6 PM 결정으로 보류 중이다 |
| 카드 수와 선택 | 12장 생성, 9장 제시와 3장 보충, 보호자 선택으로 명시 | [PM의 현재 기준](../pm/README.md#카드와-이야기의-현재-기준)과 일치. 카드당 첫 질문 1개와 꼬리 질문 3개를 면회 전에 준비하며, 실시간 생성은 현재 MVP에서 제외 |
| 이미지 출력 | 태그 후보 대신 사진 설명(`description`) 사용 | 별도 승인 없이 카드 입력에 사용. 앨범의 선택적 수정은 [3-3](api-spec.md#3-3-앨범에서-사진-설명-수정--api-미정)으로 구현([PR #205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205)) |
| 피보호자 동의 | 회차마다 동의를 받지 않음. 녹음과 음성 처리 동의는 가입 때 보호자의 필수 동의로 받음 | 피보호자 본인 확인과 대리 동의의 자격과 절차는 법률 검토 필요 |
| 저장과 상태 전이 | [API 명세](api-spec.md)에 저장 API와 상태 전이 정의. develop에 구현했고 PostgreSQL에 저장 | [이슈 18](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/18)(닫힘)에서 저장 규칙을 다뤘다. 사진 보관 기간, 원본 삭제의 정기 실행과 실제 삭제 확인은 남음 |
| 직접 식별정보 | 피보호자의 이름, 성별, 생년월일을 서버의 프로필에 저장. AI 서버 요청에는 넣지 않고 BE가 계산한 연령대만 보냄 | 서버 저장의 목적, 동의 근거와 보관 기간을 [법률 문서](../legal/README.md)에 반영 필요 |
| 보호자 평가 | PR #42로 미사용, 미응답과 중립 평가를 구분하는 화면 및 계약 반영 | 2026-09-19 PM 결정으로 미사용 및 미응답만으로 비선호 추정, 추천 하향 및 제외 금지. 카드 평가는 카드별로 저장하며 미응답은 `null`([API 6-1, 6-4](api-spec.md#6-평가와-음성-제출)) |
| 승인된 사실의 출처 | 변경 제안을 승인해 만든 LifeFact는 그 제안을 출처로 저장 | 면회 삭제 시 승인된 사실은 유지하고 해당 출처 연결만 해제. 회차 삭제 기능과 삭제 후 처리의 구현은 후속 작업 |
| 변경 제안 검토 | 보호자가 주제 제안에서 AI 제안과 다른 행동(`exclude` 포함)을 고르고, 생애 정보 제안의 제목과 내용을 고친 뒤 승인한다. 주제 제안에 `topic.description`을 담는다([변경 제안](#변경-제안-changeproposal)) | [API 7-3, 7-4](api-spec.md#7-리포트와-변경-제안)에 반영됨(PR #104). 로그인한 앱은 7-3, 7-4를 서버로 부르고, 목 데이터는 로그인 없이 여는 실행에서만 쓴다. 승인이 있는 7-4와 카드 묶음의 관계는 [API 4절](api-spec.md#사실-정정-후-카드-갱신-기준)을 따른다 |
| 리포트 | 일기형 요약과 카드별 요약 | 테크스펙의 관찰값과 계산 불가 이유를 어떤 필드로 전달할지 조율 |

공통 규칙과 [객체 목록](#객체와-담당)에서 필요한 항목으로 이동한다. [결정 대기 항목](#결정-대기-항목)에는 주제 관리 계산, STT 저신뢰도 상태처럼 아직 정하지 않은 계약과 후속 구현이 남아 있다.

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
- 전사문은 최초 STT 저장부터 24시간을 만료 기한으로 두고 리포트 저장이 먼저 완료되면 지운다. 실패 전사를 남은 기한까지 유지하는 변경은 2026-11-03 PM이 승인했다. 만료 재사용은 차단하지만 실제 DB 정리는 worker 실행에 의존하므로 정리 주기와 지연 감시가 필요하다([보관 대조](../../backend/docs/speech-recovery.md#실패-전사와-기기-녹음의-보관-대조)).
- 전사문을 외부 ML API로 보내는 리포트 생성은 남은 전사 기한이 생성 단계 임대 시간 이상일 때만 시작하고, 두 번째 전송(변경 제안) 직전에 작업과 전사가 남아 있는지 다시 확인한다. 조건을 못 맞추면 보내지 않고 `TRANSCRIPT_EXPIRED` 또는 `WORKER_LEASE_EXPIRED`로 끝낸다([외부 ML 전송과 기한](../../backend/docs/speech-recovery.md#외부-ml-전송과-기한)). 현재 구현 (2026-11-09 기준): 이 확인은 [#279](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/279)이며 11/9 승인 배포(develop `59190ba7`)부터 운영에 있다.
- 사진은 BE가 S3에 서버 측 암호화로 저장하며 객체 키에는 개인정보를 넣지 않는다. 프로필 사진은 계정이 AI 사진 분석(`photoAnalysis`)에 동의한 경우에만 분석하고 면회 사진은 분석하지 않는다.
- BE는 AI 서버에 원본을 수명이 짧은 S3 Presigned GET URL로만 전달한다.

2026-10-14 PM 결정: [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)에 따라 사진 서버 보관과 AI 분석은 가입 화면의 별도 선택 항목으로 받고 기존 계정 동의 이력에 각각 저장한다. 유효한 동의는 반복 요청하지 않으며, 미동의, 철회 또는 기록이 없는 계정이 해당 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 이용할 수 있다. 기록이 없는 계정을 동의한 것으로 처리하지 않는다. API와 DB 확장은 당시 후속 구현이었다.

사진 보관과 AI 분석 동의는 구분한다. 현재 구현 (2026-11-09 기준): AI 분석 동의는 [Account](#계정-account)의 `photoAnalysis`로 가입, 조회, 변경 API에 들어갔고([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)), 사진 분석 worker는 동의한 계정의 사진만 처리한다. 동의하지 않은 계정의 사진은 `pending`으로 남고 보호자가 설명을 직접 적을 수 있다. 동의를 거두면 저장된 AI 설명을 지운다([#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), 2026-11-09 PM 결정). 사진 보관 동의를 따로 받는 필드와 API는 아직 없다. 별도 분석 동의 확인 없이 사진 분석을 실행할 근거로 이 문서를 사용하지 않는다.

<br>

## 화면 흐름

    구글 로그인 → 가입 동의 화면(필수와 선택 구분. 사진 관련 두 항목 중 AI 분석만 구현, 사진 보관은 추가 구현 필요)
    → 기본 정보 입력 → 세부 정보 입력 → 사진 첨부(선택)
    → 대화 카드 선택 → 면회 사진 촬영
    → 녹음 → 면회 중 대화 카드 → 대화 카드 보충
    → 보호자 평가 → 음성 제출
    → 리포트 → 변경 사항 확인

- 별도의 회원가입 단계를 두지 않는다. 구글 인증에 성공하면 필수 동의를 확인하고, 동의가 완료될 때 계정과 동의 이력을 함께 만든다. 녹음과 음성 처리 동의도 이때 필수 동의로 함께 받는다. 필수 동의를 거부하거나 가입을 중단하면 계정을 만들지 않는다. 선택 동의 거부만으로 가입을 막지 않는다. 현재 구현은 최초 가입 시 동의와 가입 후 선택 동의 변경([API 1-6](api-spec.md#1-6-patch-authmeconsents--신규))을 처리하며, 약관 변경 시 재동의는 후속 설계한다.
- 가입하면 기본 정보 입력부터 시작한다. 로그인 뒤에는 프로필이 없거나 `setupStatus`가 `completed`인 프로필이 있으면 홈으로 간다. 입력을 마친 프로필이 생길 때까지 대화 카드, 면회와 리포트처럼 프로필이 필요한 기능은 막는다. `inProgress`인 프로필만 있을 때 어디로 갈지는 아직 정하지 않았다([API 미정 사항](api-spec.md#미정-사항) 9).
- 세부 정보는 프로필 입력을 마칠 때 한 번에 저장하고 이어서 카드 생성을 시작한다([API 2-4](api-spec.md#2-4-patch-apiv1profilesprofileid--신규), [4-1](api-spec.md#4-1-post-apiv1profilesprofileidcard-generations--신규)). 홈의 `오늘의 대화카드 받기`는 [API 4-2](api-spec.md#4-2-get-apiv1profilesprofileidcard-generationsstatus--신규)의 상태로 정한다.
- 사진 설명은 별도 승인 없이 카드 생성에 사용한다. 사용자가 원하면 앨범에서 확인하거나 [API 3-3](api-spec.md#3-3-앨범에서-사진-설명-수정--api-미정)으로 수정한다.
- 면회 사진은 녹음 전에 단말에서 찍는다. 회차는 녹음을 시작할 때 만들고 사진은 그 뒤에 올린다. 녹음 일시정지와 종료는 단말에서 처리한다.
- 보호자 평가를 제출한 뒤 면회 음성을 제출한다. 리포트는 STT 결과와 보호자 평가로 만든다.
- 마이페이지에서 프로필 수정과 리포트 기록 확인을, 일대기에서 생애 정보 확인, 추가와 수정을 할 수 있으며 위 흐름과 별개로 언제든 진입 가능하다.

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

- `LifeFactCollectionState`는 단말에만 둔다. 나머지 객체는 BE가 저장하며, `SpeechAnalysisResult`의 전사문은 위 임시 보관 기준을 적용한다. 실패 후 보관 변경의 동의 화면 반영과 실제 사용자 자료 처리 조건은 PM 확인이 남아 있다.
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
    "pushNotification": { "granted": true, "grantedAt": "2026-08-21T11:40:00+09:00" },
    "photoAnalysis": { "granted": false, "grantedAt": null }
  },
  "createdAt": "2026-08-21T11:40:00+09:00"
}
```

- 인증은 구글 소셜 로그인을 사용하며 백엔드가 ID 토큰을 직접 검증하는 방향에 PM이 동의했다. 개인정보 저장 항목 등 [ADR-007](decisions/ADR-007-google-social-login.md)의 검토안은 별도로 남아 있다. 아이디와 비밀번호는 받지 않으며, 계정은 구글 인증 뒤 필수 동의가 완료될 때 동의 이력과 함께 만들어진다.
- `authProvider`의 값은 현재 `google` 하나다. 다른 제공자를 더하는 것은 계약 변경으로 본다.
- `displayName`과 `email`의 영구 저장 범위는 검토 중이다. PM은 이메일과 구글 계정 이름을 저장하지 않는 안을 제안했고 BE와 FE가 구현 영향을 확인한다([ADR-007](decisions/ADR-007-google-social-login.md)). 현재 서버의 기본 설정에서는 사용자 입력 표시 이름이 없으면 `보호자`를 사용하고 `email`은 `null`로 반환한다. `displayName`에는 실명이 들어올 수 있으므로 사용자가 수정할 수 있어야 한다.
- `email`은 문자열 또는 `null`이다. 서버가 값을 저장하지 않거나 제공하지 않는 경우 `null`로 보내며, FE는 이를 임의의 주소나 빈 문자열로 채우지 않는다. 누락된 `email`도 FE에서 없는 값으로 읽는다. nullable 응답을 지원하는 변경이며 이메일 미저장 정책을 확정한 것은 아니다.
- `serviceData`(개인정보 수집 동의)와 `sensitiveData`(민감정보 수집 동의)는 필수 동의 사항이며 거부하면 가입을 진행하지 않는다. 녹음과 음성 처리 동의는 가입 때의 필수 동의로 함께 받으며 면회 회차마다 따로 받지 않는다.
- 현재 계약의 선택 항목은 `serviceImprovement`(서비스 개선 활용), `pushNotification`(알림 수신), `photoAnalysis`(AI 사진 분석)이며 거부해도 가입과 핵심 기능을 차단하지 않는다. `photoAnalysis`는 2026-10-14 PM 결정에 따라 11/7에 추가했다(이슈 #183, [PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)). 같은 결정의 사진 보관 선택 동의는 아직 없다.
- `photoAnalysis`를 거부한 계정의 사진은 AI가 분석하지 않고 `pending`으로 남는다. 보호자가 직접 쓴 설명은 동의와 관계없이 카드에 쓴다. 분석 중에 동의를 거두면 ML 업체에 보내기 전이면 보내지 않고, 보낸 뒤면 결과를 저장하지 않는다. 2026-11-09 PM 결정에 따라 동의를 거두면(1-6) 이미 저장된 AI 설명도 지우고 그 사진을 `pending`으로 되돌린다. 보호자가 쓴 설명은 남는다. 보호자 설명이 없는 사진의 AI 설명을 지운 프로필은 아직 면회에 안 쓴 카드 묶음의 `needsRefresh`가 `true`가 된다. 그 묶음이 지운 설명을 실제로 썼는지는 따지지 않는다. 다시 동의하면 `pending`인 사진을 다시 분석한다. 이전 앱은 이 항목을 보내지 않으므로 가입 요청에서 빠지면 거부로 본다.
- 동의가 바뀔 때마다 이력을 추가하며 `consent`는 가장 최근 이력이다. `consentVersion`은 그 이력의 약관 버전이다.
- 가입 후에는 선택 동의만 바꿀 수 있다([API 1-6](api-spec.md#1-6-patch-authmeconsents--신규)). 앱에서는 설정의 계정 약관 동의 화면에서 바꾼다([PR #271](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/271)). `grantedAt`은 동의 중인 항목이면 거부에서 동의로 바뀐 가장 최근 이력의 시각이고, 처음부터 동의했으면 가입 시각이다. 거부 중이면 `null`이다.
- `pushNotification`을 거부한 계정에는 푸시 알림을 보내지 않는다. 홈 화면은 회차 목록([API 5-4](api-spec.md#5-4-get-apiv1profilesprofileidvisit-sessions--신규))의 `sessionStatus`로 리포트 도착을 표시하므로, 알림을 거부해도 리포트를 받아볼 수 있다.
- 푸시를 받을 기기는 앱이 FCM에 등록하고 받은 등록 ID(FID)로 [API 1-7](api-spec.md#1-7-put-authmepush-devicesfid--신규)에서 등록한다. 서버는 알림 수신에 동의한 계정의 등록만 받고, 동의를 거두면(1-6) 그 계정의 등록을 지운다. 계정당 기기는 5대까지이며, 넘으면 등록 시각이 가장 오래된 기기의 등록을 오류 없이 지운다(2026-11-09 PM 결정).
- 앱은 구글에서 받은 ID 토큰을 백엔드로 보내고, 백엔드가 구글 공개키로 검증한 뒤 기존 계정을 찾거나 필수 동의 완료 시 계정을 만든다. 제공자 식별자(구글 `sub`), 비밀번호와 인증 토큰은 이 계정 객체에 포함하지 않는다.
- 탈퇴하면([API 1-5](api-spec.md#1-5-delete-authme--수정)) 계정과 동의 이력, 프로필과 그 아래의 모든 기록을 지운다. 사진과 음성 원본은 S3 삭제 대기열로 지운다. 탈퇴 이유는 계정과 연결하지 않고 저장한다.
- 앱 재실행 시 세션 복원은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50), 사용 중 세션 만료 후 자동 재인증은 [PR #175](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/175)로 구현했다. PR 50 리뷰에서 요청한 약관 서버 관리는 없다. 약관 문구는 앱에 있고 서버는 `consentVersion`만 확인한다.

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

- 계정당 프로필은 입력 중(`inProgress`)인 것을 포함해 최대 3개다.
- 프로필 하나를 지우면([API 2-8](api-spec.md#2-8-delete-apiv1profilesprofileid--신규)) 그 프로필 아래의 모든 기록을 지우고 계정과 다른 프로필은 남긴다. 마지막 프로필도 지울 수 있다.
- `setupStatus` 값은 `inProgress`, `completed`이다. 저장하지 않고 계산하며, 카드 생성 작업이 하나라도 있으면 `completed`, 없으면 `inProgress`다. 기본 정보 입력을 마치면 `inProgress`로 만들어지고, 프로필 입력을 마칠 때 첫 카드 생성 작업([API 4-1](api-spec.md#4-1-post-apiv1profilesprofileidcard-generations--신규))이 만들어지면 `completed`가 된다.
- `name`은 50자 이하다. `gender` 값은 `male`, `female`이다. `birthDate`는 `YYYY-MM-DD`다.
- `birthDate`는 만 10세 이상인 날짜만 받는다(서버의 UTC 날짜 기준). 미래 날짜와 10년이 안 된 날짜는 만들거나 고칠 때 `422 INVALID_REQUEST`다. 카드 생성 요청의 연령대가 `10s` 이상이어야 하기 때문이며, 그 밖의 나이 제한은 정하지 않았다.
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
  "storyCategory": "work",
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요.",
  "imageNumber": 3,
  "sensitive": false,
  "createdAt": "2026-08-21T12:10:00+09:00"
}
```

- 세부 정보 네 항목 밖의 생애 정보다. 네 항목은 [Profile](#프로필-profile)의 필드로 저장한다.
- `title`은 100자, `content`는 5,000자 이하이며 `title`과 `content`는 비울 수 없다. 글자 수는 유니코드 코드 포인트 수로 센다.
- 프로필 하나의 생애 사실은 300개까지다. 일대기에서 추가한 것과 변경 제안 승인으로 만든 것을 함께 센다. 넘으면 저장하지 않고 `409 LIFE_FACT_LIMIT_EXCEEDED`다. 내용 길이와 개수 상한은 2026-11-09 PM 결정이다.
- 생애 사실은 일대기에서 확인하고 직접 추가한다. 마이페이지(프로필 설정)에는 세부 정보 네 항목만 둔다.
- 두 경로로 만든다. 보호자가 일대기에서 추가하거나([API 2-6](api-spec.md#2-6-post-apiv1profilesprofileidlife-facts--신규)), 보호자가 변경 제안의 생애 정보 제안을 승인하면([API 7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규)) BE가 만든다. 승인할 때 보호자가 제목, 내용과 분류를 고칠 수 있으며, BE는 고친 값으로 만들고 원래 제안은 바꾸지 않는다. 분류를 고르지 않으면 AI가 제안에 붙인 분류로 만든다(2026-11-09 PM 결정). 승인으로 만든 사실은 그 제안을 출처로 저장하며 응답에는 출처를 담지 않는다. 승인은 이야기 추가(2-6)와 같아서 아직 면회에 안 쓴 카드 묶음을 다시 만들 대상(`needsRefresh`)으로 바꾸지 않고, 카드를 만드는 중에도 받는다. 다음 카드 생성부터 반영된다.
- 출처 면회가 삭제되면 보호자가 승인한 사실은 유지하고 해당 출처 연결만 해제한다. 생성 시 출처 연결과 삭제 후 연결 해제를 구분하며, 출처 연결을 이유로 회차 삭제를 막지 않는다.
- 이 규칙은 [2026-09-19 PM 결정](../pm/README.md#2026-09-19-pm-결정)에 따른 면회 기록 삭제 범위다. 계정 탈퇴와 프로필 삭제 범위를 정하거나, 삭제 행동을 부정적 감정 및 비선호로 해석하지 않는다. DB 삭제 동작과 연결이 없는 사실의 화면 표시는 후속 검증이 필요하다.
- 일대기에서 내용을 고칠 수 있다([API 2-7](api-spec.md#2-7-patch-apiv1life-factsfactid--신규)).
- `sensitive`는 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 이야기면 `true`다(2026-11-10 PM 결정). 변경 제안 승인으로 만든 사실은 승인한 제안의 `sensitive`를 그대로 옮기고, 일대기에서 추가한 사실은 `false`이며, 보호자가 2-7로 바꾼다. 보호자가 지우지 않는 한 아픈 이야기도 일대기에 남기고 카드 생성 요청에 넣는다. 앱은 일대기에 작은 표시를 달고 홈 말풍선의 이야기 추천에서 뺀다. 이 필드가 없는 응답은 `false`로 읽는다.
- `storyCategory`는 일대기의 분류(`family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`), `imageNumber`는 분류별 기본 그림 번호(1~5)다. 그림 파일은 앱에 있다. 필드 이름은 임시다([API 미정 사항](api-spec.md#미정-사항) 11).
- 일대기에서 지울 수 있다([API 2-9](api-spec.md#2-9-delete-apiv1life-factsfactid--신규)). 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 된다. 이야기나 사진 근거가 하나도 남지 않은 주제는 다음 카드 생성 입력에서 빠진다(PM 결정 2026-11-08). 보호자가 제외한 주제도 근거 이야기와 사진을 모두 지우면 빠진다(PM 결정 2026-11-09, 아래 [카드 생성 요청](#카드-생성-요청-cardgenerationrequest)). 저장된 지난 카드와 주제의 처리는 미정이다([API 미정 사항](api-spec.md#미정-사항) 12).

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
  "descriptionSource": "ai",
  "error": null,
  "createdAt": "2026-08-21T12:20:00+09:00"
}
```

- 사진 원본은 JPEG 또는 PNG이며 BE가 S3에 저장한다. `imageUrl`은 수명이 짧은 조회용 URL이다.
- 처음 API 제안은 프로필 사진을 모두 분석하는 구조였다. 현재는 계정이 AI 사진 분석(`photoAnalysis`)에 동의한 경우에만 분석한다([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)). 동의하지 않은 계정의 사진은 `pending`으로 남고, 동의를 거두면 더 분석하지 않으며 분석 중이던 사진은 ML 업체에 보내지 않거나 결과를 버린다. 이미 저장된 AI 설명도 지우고 `pending`으로 되돌린다([#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), 2026-11-09 PM 결정). PR #92의 PM 수정안이 구분한 사진 보관 동의는 아직 구현되지 않았다([결정 대기 항목](#결정-대기-항목)).
- `analysisStatus` 값은 `pending`, `processing`, `completed`, `failed`이다.
  - 분석에 실패해도 프로필 입력을 계속 진행할 수 있어야 한다.
  - `description`은 보호자가 고친 설명이 있으면 그것을 우선하며, 없으면 완료된 AI 설명이다. 둘 다 없으면 `null`이다. 선택 필드 `descriptionSource`는 `caregiver`, `ai`, `null`이다. AI 분석 상태와 보호자 설명의 저장을 구분한다. 다루는 기준은 [ImageAnalysisCandidate](#이미지-분석-후보-imageanalysiscandidate)를 따른다.
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
- `description`은 사진 설명이며 별도 승인 없이 카드 생성 요청에 넣는다. 사용자는 원할 때 앨범에서 수정한다([API 3-3](api-spec.md#3-3-앨범에서-사진-설명-수정--api-미정)). 사진 설명을 승인된 `LifeFact`로 자동 저장하지 않는다.
- 사진 메타데이터는 기존 결정대로 AI 분석과 주제 추천 입력에서 제외한다. 과거 [사진 메타데이터 추출 보고서](../../ai/docs/image_tagging/metadata-extraction-report.md)는 실험 기록으로 보존하며 입력에 포함할 근거로 사용하지 않는다.
- 사진 설명의 카드 입력 사용과 이야기 후보의 승인을 구분한다. [주제 카드 설계 검토안](card-generation-flow.md#4-사진-설명은-바로-사용하고-앨범에서-선택적으로-수정)에 기존 결정과 앨범 수정 흐름을 정리한다.

<br>

---

## 카드 생성 요청 (CardGenerationRequest)

> **상태: 요청과 결과 형식은 [API 4-1 카드 생성 처리](api-spec.md#4-1-카드-생성-처리) 기준.** 카드 생성과 추천은 핵심 기능으로 별도 설계한다. [PM 제품 기준](../pm/README.md#카드-미사용과-추천-제외)을 지키며 각 값을 생성에 어떻게 쓸지는 AI가 로직으로 정하고 PM, FE와 BE가 제품 및 연동 범위를 함께 확인한다.

BE의 카드 생성 worker가 작업([API 4-1](api-spec.md#4-1-post-apiv1profilesprofileidcard-generations--신규))을 가져가 DB 값으로 만들고 카드 생성 함수에 넘긴다. AI 서버를 거치지 않으며 앱은 이 객체를 보내지 않는다. 최신 전체 설계는 [주제 카드 흐름](card-generation-flow.md#8-단계별-데이터와-역할)을 따른다.

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

- `model`, `promptVersion`은 BE 설정값이며 작업을 만들 때 저장한 값을 그대로 넘긴다. `promptVersion`은 정수다.
- 현재 develop의 새 작업 기본 모델은 `gpt-6-luna`다(11/3 전환). 위 예시의 이전 모델도 명시적으로 선택할 수 있으며 이미 저장된 작업의 모델은 바꾸지 않는다. 모델 전환으로 요청 필드와 응답 형식은 바꾸지 않는다.
- `ageRange`는 BE가 생년월일로 계산한 값이다. 피보호자의 이름, 성별, 생년월일, 인지 상태와 증상 메모는 넣지 않는다.
- `profileFacts`는 [Profile](#프로필-profile)의 세부 정보 네 항목이다.
- `lifeFacts.source`는 면회 제안을 승인해 생긴 이야기면 `visit`, 직접 넣은 이야기면 `caregiver`다.
- `lifeFacts.sensitive`는 [LifeFact](#확인된-생애-사실-lifefact)의 아픈 기억 표시다. 카드 생성 2판은 이 이야기를 근거로 한 카드를 늘 `sensitive`로 내고, 문안은 아픈 순간을 캐묻지 않고 그분과의 좋았던 기억이나 그 시절의 일상을 여쭙는다(2026-11-10 PM 결정). 카드 생성은 이 필드가 없으면 `false`로 읽는다.
- `photos`는 보호자가 고친 설명이 있으면 그 값, 없으면 분석이 끝난 AI 설명이 있는 프로필 사진이며 별도 내용 승인 없이 넣는다. 사용자는 원하면 앨범에서 수정한다([API 3-3](api-spec.md#3-3-앨범에서-사진-설명-수정--api-미정)). 사진 분석 동의 확인은 별도로 유지하며, 사진 설명을 승인된 생애 사실로 저장하는 것은 아니다. 메타데이터는 입력에서 제외한다.
- `topics`는 이 프로필의 기존 주제와 보호자가 승인한 주제 피드백이며 첫 생성에는 빈 배열이다. 근거(`evidence`)에서는 입력에 없는 이야기와 사진(지운 것, 설명이 없어 `photos`에 넣지 않는 사진, 제외한 주제의 근거)을 뺀다. 빼고 나서 근거가 하나도 남지 않은 주제는 넣지 않는다(PM 결정 2026-11-08). 원래 근거가 없던 주제와 세부 정보 칸 근거가 남은 주제는 넣는다. 보호자가 `exclude`를 고른 주제는 근거 이야기와 사진이 제외 규칙으로 늘 입력에서 빠지므로, 보낸 입력이 아니라 DB에 남은 이야기와 `photos`에 넣을 수 있는 사진으로 정한다. 하나라도 남아 있으면 근거만 빼고 넣고, 보호자가 모두 지웠으면 넣지 않는다(PM 결정 2026-11-09). 세부 정보 칸 근거가 있는 제외 주제는 이야기와 사진을 모두 지워도 다른 주제처럼 넣는다. AI 사진 분석 동의를 거둬 AI 설명이 지워진 사진(보호자 설명 없음, API 1-6)도 `photos`에 넣지 않으므로, 근거가 그런 사진뿐인 주제는 제외 여부와 상관없이 넣지 않고 다시 분석이 끝나면 넣는다. 저장된 주제와 근거는 지우지 않는다.
- `visits`는 평가까지 끝난 회차만 시간순으로 넣고, `pastCards`는 그 회차에 쓰인 카드 묶음의 카드다. 위에서 뺀 주제를 가리키는 지난 카드도 넣으므로 `pastCards[].topicId`가 `topics`에 있다고 가정하지 않는다. 면회 평가 메모, 리포트 본문과 전사문은 넣지 않는다.
- 카드 생성 작업의 기록(`generation_log`)에는 보낸 글을 복사하지 않는다(PM 결정 2026-11-08). 보낸 이야기, 사진, 주제, 회차, 지난 카드의 ID와 `ageRange`, 값이 있던 세부 정보 칸의 이름, 생성 쪽 실행 기록의 숫자와 카드별 `kind`, `bucket`만 남긴다. 형태는 [API 4-1 카드 생성 처리](api-spec.md#4-1-카드-생성-처리)의 카드 생성 기록에 있다.
- 결과 형식, 검증과 실패 코드는 [API 4-1 카드 생성 처리](api-spec.md#4-1-카드-생성-처리)를 따른다. 카드 12장을 만들고 새 주제는 제목, 설명과 근거로 돌려주며, BE가 카드와 새 주제에 ID를 부여한다.

<br>

---

## 첫 카드 사진 준비 (PhotoPreparation)

카드 생성 요청과 상태 응답(API 4-1, 4-2)에 선택적으로 붙는 `photoPreparation`이다. 사진을 기다리는 동안만 있으며 기존 `status`는 `running`을 유지한다. 준비가 끝나면 이 필드를 보내지 않는다.

| 필드 | 값과 의미 |
| --- | --- |
| setId | 진행 중인 카드 작업 UUID. 재시도와 계속 진행 요청에 그대로 보냄 |
| state | `waiting`: 분석 대기, `choice`: 보호자 선택 필요 |
| total | 요청 시 고정한 사진 중 아직 존재하는 수 |
| completed | AI 분석 완료 또는 보호자가 쓴 설명이 있는 수 |
| failed | 분석 실패 또는 임대 만료 수 |
| pending | 아직 준비되지 않은 나머지 수 |
| reason | 선택이 필요할 때 `analysisFailed`, `timedOut`, `consentRequired` |

합계는 `completed + failed + pending = total`이다. 사진 없는 첫 생성, 사진 분석 동의가 없는 첫 생성과 두 번째 이후 생성에는 대기를 만들지 않는다. 보호자 선택과 오류는 [API 4-7](api-spec.md#4-7-post-apiv1profilesprofileidcard-generationsphoto-preparation)에 정의한다. 사진이 입력에 포함돼도 최종 카드 수와 사진별 선택 수를 보장하지는 않는다.

## 대화 카드 묶음 (CardSet)

카드 묶음과 그 카드 12장이다. 지금 쓸 묶음은 [API 4-3](api-spec.md#4-3-get-apiv1profilesprofileidcard-generationscurrent--신규), 회차에 쓴 묶음은 [API 4-4](api-spec.md#4-4-get-apiv1visit-sessionssessionidcard-set--신규)의 응답이다.

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

- 카드 생성은 비동기 작업이다([API 4-1](api-spec.md#4-1-post-apiv1profilesprofileidcard-generations--신규)). 프로필마다 만드는 중인 작업은 하나뿐이다. 변경 제안이 없는 리포트 뒤의 생성 시점은 아직 정하지 않았다.
- 작업 상태는 이 객체에 넣지 않는다. 홈의 `오늘의 대화카드 받기`는 [API 4-2](api-spec.md#4-2-get-apiv1profilesprofileidcard-generationsstatus--신규)의 `status`(`none`, `running`, `ready`, `inVisit`, `failed`)로 정한다. 4-3으로는 `ready`(고르기 전)나 `inVisit`(평가 전 회차에 쓰는 중)일 때만 받는다. 평가가 끝난 회차의 묶음은 4-4로 읽기만 하며 면회에 다시 쓰지 않는다.
- `setId`는 녹음을 시작할 때 [API 5-1](api-spec.md#5-1-post-apiv1visit-sessions--신규)에 보낸다.
- `usedBySessionId`는 이 묶음을 쓰는 평가 전 회차이며 고르기 전이면 `null`이다. 앱을 다시 켰을 때 이 값으로 5-2, 5-3을 부른다. 4-4에서는 요청한 회차이며 평가가 끝난 회차일 수 있다.
- `needsRefresh`는 카드를 받은 뒤 프로필이나 일대기를 고치거나 프로필 사진 설명을 고치거나 사진을 지우거나 AI 사진 분석 동의를 거둬 AI 설명이 지워지거나([API 1-6](api-spec.md#1-6-patch-authmeconsents--신규)) 변경 사항에서 주제 결정을 반영해서([API 7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규)) 다시 만들어야 하는 묶음이면 `true`다. 볼 수는 있지만 이 묶음으로 면회를 시작할 수 없다. 4-2 응답에도 같은 값이 있다([API 4절](api-spec.md#4-대화-카드)).
- `cards`는 12장이다. `cardId`는 BE가 부여한다. `position` 1~9가 선택 화면 대상이고 10~12가 면회 중 보충용이다.
- `topic`은 프로필의 주제이며 `topicId`로 회차 간에 같은 주제를 잇는다. 한 묶음 안에서 같은 `topicId`는 두 번 나오지 않는다.
- `topic.description`과 `description`은 보호자에게 주제와 카드를 알려주는 설명이다. 어르신에게 그대로 여쭙는 문장은 `primaryQuestion`이며 둘은 역할이 다르다.
- `followUpQuestions`는 카드마다 3개다.
- `evidenceSource` 값은 `lifeFact`, `photo`, `profile`, `none`이다. `none`이면 `evidence`는 빈 배열이고, 나머지는 같은 종류의 근거 항목이 하나 이상이다. 항목은 `lifeFact`면 `{"factId": ...}`, `photo`면 `{"photoId": ...}`, `profile`이면 `{"profileField": "occupation" | "hometown" | "hobby" | "family"}`다.
- `selected`는 회차를 만들 때 고른 카드와 면회 중 보충 화면에서 추가한 카드가 `true`다. 선택하지 않은 카드도 삭제하지 않는다.
- `liked`는 보호자가 원하는 카드에만 남기는 "좋았어요" 표시다([API 4-5](api-spec.md#4-5-put-apiv1cardscardidlike--신규), [4-6](api-spec.md#4-6-delete-apiv1cardscardidlike--신규)). 보호자 평가(6-1)의 카드 반응과 따로 저장하고, 평가를 마친 뒤에도 켜고 끌 수 있다. 다음 카드 생성 입력에는 아직 넣지 않는다.
- `sensitive`는 저장된 이야기나 세부 정보에 담긴 아픈 경험(사별, 전쟁, 사고, 병)을 다루는 카드면 `true`다. 앱은 표시를 달아 보호자가 고를지 정하게 한다(2026-11-09 PM 결정). 카드 생성 2판으로 만든 묶음에서만 `true`가 나오고, 1판 묶음과 이 필드를 더하기 전에 만든 카드는 `false`다. 서버는 11/10 배포(develop `83695093`)부터 운영에 있고, 운영 `.env`에 `SAEROK_CARD_GENERATION_PROMPT_VERSION`이 없어 코드 기본값 2가 적용되므로 배포 뒤 요청한 묶음은 2판이다. 앱의 표시는 새 APK를 만들어야 휴대폰에 들어가며, 설치된 앱(Play와 11/8 Releases APK)에는 없다.

**없어도 되는 값** — `usedBySessionId`

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

> **상태: ADR-008 제안(proposed).** BE 구현은 develop에 있고 11/10 운영 배포(develop `83695093`)에서 동작한다.
> `sttCompleted` 작업 이어받기([#280](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/280))와 전사 기한에 따른 리포트 생성 제한
> ([#279](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/279))은 11/9 배포(develop `59190ba7`)로 운영에 들어갔다. FE, AI, PM
> 공동 확인 전에는 이것이 실제 사용자 자료 전송 승인을 뜻하지 않는다.

앱은 보호자 평가를 제출한 뒤 WAV와 `participantCount`를 multipart 요청으로 제출한다.
BE는 `audioPending`인 회차만 받으며, 원본을 S3에 임시 저장하고 작업을 영속화한 뒤 다음
`202 Accepted` 응답을 반환한다. 접수하면 회차의 `sessionStatus`는 `processing`이 된다.
앱은 `202`를 받아도 단말의 WAV와 회차 연결을 지우지 않고 보냈다고만 적는다. 서버 분석이 실패하면 먼저 리포트 재요청([API 6-5](api-spec.md#6-5-post-apiv1speech-analysesanalysisidretry--신규))을 보내고, 유효한 전사가 없어 `RECORDING_REQUIRED`이면 이 녹음으로 6-2를 다시 제출한다([API 6-2](api-spec.md#6-2-post-apiv1visit-sessionssessionidspeech-analyses--완료)).

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
- `sttCompleted`는 AI 응답 검증과 전사문 임시 저장이 끝났지만 리포트는 아직 준비되지 않은 상태다. 원본 삭제는 즉시 시도하며 실패 시 삭제 대기열에 남긴다. 이 상태가 원본 삭제 완료를 뜻하지는 않는다.
- 리포트를 이어 갈 worker가 `sttCompleted`에서 멈추면 작업을 실패로 바꾸지 않는다. 인계 임대(기본 900초)가 끝나면 다른 worker가 같은 `analysisId`로 `generatingReport`부터 이어 가므로, 그동안 `sttCompleted`가 유지될 수 있다. 상태 이름과 응답 형식은 바뀌지 않는다.
- `completed`는 STT뿐 아니라 리포트와 변경 제안 저장까지 끝난 상태다.
- 실패 시 `errorCode`만 제공하며 AI 오류 본문, 전사문, S3 URL과 객체 키를 제공하지 않는다.
- 유효한 전사가 남은 실패 작업은 6-5로 리포트만 다시 요청하고, 전사가 없거나 만료됐으면 6-2로 기기 녹음을 다시 제출한다. 처리 중인 작업은 반환하고 완료한 회차는 다시 받지 않는다. 6-5는 전사가 남아 있을 때 면회 회차당 3회까지 받는다(`REPORT_RETRY_LIMIT_EXCEEDED`). 전사가 없거나 만료됐으면 횟수와 관계없이 6-2로 기기 녹음을 다시 제출하며, 이 제출은 횟수에 넣지 않는다. [API 명세](api-spec.md)의 6-2와 6-5를 따른다.
- 자세한 상태 전이, 삭제와 재시도 경계는 [ADR-008](decisions/ADR-008-stt-pipeline.md)을 따른다.

<br>

---

## STT와 화자 처리 결과 (SpeechAnalysisResult)

> **상태: v1 구현.** BE가 동의를 확인한 요청만 AI 서버에 전달하며 동의 이력은 BE가 관리한다.

- 전사문은 화면에 표시하지 않으며 리포트 생성 요청([API 8-3](api-spec.md#8-3-post-internalv1visit-reports--신규))의 입력으로만 사용한다. 리포트 재시도는 최초 STT 저장부터 24시간의 남은 기한 안에서만 허용하고, 리포트 저장 완료 시 삭제한다. 재시도한 생성도 남은 기한이 생성 단계 임대 시간 이상일 때만 시작한다. 실패 전사 보관 기준과 만료 삭제의 worker 의존성은 위 공통 규칙 및 [보관 대조](../../backend/docs/speech-recovery.md#실패-전사와-기기-녹음의-보관-대조)를 따른다.
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
- 추천 대상 제외는 사용자가 명시적으로 선택했을 때 적용한다. 이는 과거 카드와 면회 기록 삭제가 아니다. API 명세에서는 보호자가 주제 제안을 승인하며 `exclude`를 고를 때([API 7-4](api-spec.md#7-4-post-apiv1visit-sessionssessionidproposalsreview--신규)) 주제 단위로 적용하며, `wasUsed=false`로 대신 표현하지 않는다. 제안 없이 보호자가 직접 제외를 고르는 기능은 아직 정하지 않았다. 제외한 주제의 근거 이야기와 사진은 다음 카드 생성 입력에서 뺀다. 근거가 남으면 같은 이야기로 이름만 다른 새 주제가 만들어지기 때문이다. 세부 정보 네 칸(하시던 일, 고향, 취미, 가족)은 남긴다. 제외를 승인하면 아직 면회에 안 쓴 카드 묶음은 `needsRefresh`가 `true`가 되고, 카드를 만드는 중에는 승인을 받지 않는다. 제외 전 입력으로 만든 묶음에 그 주제가 남을 수 있기 때문이다.
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

- 변경 제안은 생애 정보 제안과 주제 제안 두 가지이며 회차마다 0개 이상이다. AI가 리포트와 함께 만들고 `proposalId`는 BE가 부여한다.
- 기존 생애 사실의 수정은 제안하지 않으며 사용자가 일대기에서 직접 수정한다.
- 생애 정보 제안의 `storyCategory`는 AI가 고른 일대기 분류([LifeFact](#확인된-생애-사실-lifefact)와 같은 7개 값)이고, `sensitive`는 사별, 전쟁, 사고, 병처럼 아픈 기억일 수 있는 후보면 `true`다. 앱은 `sensitive` 후보에 안내를 붙인다. 두 필드를 더하기 전에 만든 제안은 `other`, `false`다(2026-11-09 PM 결정, #139). 서버는 11/10 배포(develop `83695093`)부터 운영에 있다. 앱의 안내는 새 APK를 만들어야 휴대폰에 들어가며, 설치된 앱(Play와 11/8 Releases APK)에는 없다.
- 주제 제안은 다음 카드 생성에서 이 주제를 더 다룰지, 덜 다룰지, 제외할지에 대한 제안이며 주제 단위로 적용한다. 회차에서 고른 카드당 최대 1개다.
  - `topic.description`은 [CardSet](#대화-카드-묶음-cardset)의 `topic.description`과 같은 주제 설명이다.
  - `suggestedAction` 값은 `more`, `less`, `exclude`이다.
  - 카드를 쓰지 않았거나 답하지 않았다는 사실만으로 `less`, `exclude`를 제안하지 않는다(2026-09-19 PM 결정).
  - 보호자가 아쉬웠어요(`negative`)로 평가한 카드에는 `more`를 제안하지 않는다. AI 쪽 코드가 거른다(`proposals-9`).
- `reviewStatus` 값은 `pending`, `accepted`, `rejected`이다. 제안은 승인 전까지 프로필에 반영하지 않는다.
- 검토는 회차의 `pending` 제안을 모두 한 번에 보낸다. 화면에 남긴 항목은 `accepted`, 제외한 항목은 `rejected`다. `반영하지 않고 마치기`는 모든 항목을 `rejected`로 보낸다.
- `accepted`인 항목에는 보호자가 확인한 최종 값을 함께 보낸다. 생애 정보 제안은 최종 제목과 내용(분류를 바꿨으면 `storyCategory`도), 주제 제안은 보호자가 고른 행동(`more`, `less`, `exclude`)이며 제안과 달라도 된다. 고치지 않았으면 제안 값을 그대로 보낸다. 최종 제목과 내용은 [LifeFact](#확인된-생애-사실-lifefact)와 같이 100자와 5,000자 이하이고, 승인한 생애 정보 제안을 더해 300개를 넘으면 검토 전체를 저장하지 않는다.
- `accepted`인 생애 정보 제안은 BE가 보호자가 확인한 제목과 내용, 분류(보내지 않았으면 제안의 `storyCategory`)로, 그 제안을 출처로 하는 [LifeFact](#확인된-생애-사실-lifefact)를 만든다. 아픈 기억 표시는 제안의 `sensitive`를 그대로 옮긴다(2026-11-10 PM 결정). `accepted`인 주제 제안은 보호자가 고른 행동을 주제 피드백으로 기록하고 다음 [CardGenerationRequest](#카드-생성-요청-cardgenerationrequest)의 `topics`에 넣는다. 원래 제안의 값은 바꾸지 않는다.
- 승인한 제안을 되돌리는 기능은 없다. 승인으로 만든 생애 사실은 일대기에서 직접 고친다.
- 거절한 이야기 후보의 30일 보관과 복구는 [별도 복구 기준](card-generation-flow.md#이야기-후보의-승인-거절과-복구)을 따른다. 복구 시 다시 확인할 후보가 되며 자동 승인하지 않는다. 복구 API와 상태 전환은 후속 설계 대상이다. 현재 `reviewStatus`에 `reverted`를 추가하거나 승인 취소를 뜻하도록 바꾸지 않는다.
- 제안이 없는 회차의 확인 처리와, 검토 뒤 응답에 보호자가 고친 값을 담을지는 아직 정하지 않았다.
- 변경 사항 확인 화면은 주제 제안마다 `suggestedAction`을 처음에 골라 두고 보호자가 다른 행동을 고를 수 있게 한다. 다만 `exclude` 제안은 되돌리기 어려워 미리 고르지 않고 보호자가 직접 고른다. 주제 제목 아래에 `topic.description`을 보여주며, 없으면 제목만 보여준다. 생애 정보 제안은 제목, 내용과 분류를 고칠 수 있다. `exclude`를 미리 고르지 않는 것과 분류 고치기는 #295의 앱 변경이라 새 APK를 만들어야 휴대폰에 들어가며, 설치된 앱(Play와 11/8 Releases APK)에는 없다.
- 화면은 `pending` 제안만 보여주고 검토 요청에 담는다. 이미 `accepted`나 `rejected`인 제안과 `reviewStatus`를 읽지 못한 제안은 다시 보내지 않는다. 검토할 제안이 없으면 요청을 보내지 않는다.
- 승인 요청 예시는 다음과 같다. `rejected` 항목에는 `action`, `title`, `content`, `storyCategory`를 담지 않는다. 예시의 생애 정보 항목은 분류를 바꾸지 않아 `storyCategory`가 없으므로 제안의 분류로 만든다. `storyCategory`의 `null`이나 7개 밖의 값은 `422 INVALID_REQUEST`다.

```json
{
  "lifeFacts": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000801",
      "reviewStatus": "accepted",
      "title": "한복",
      "content": "한복을 주로 만드셨고 단골이 많았어요."
    }
  ],
  "topics": [
    {
      "proposalId": "00000000-0000-4000-8000-000000000802",
      "reviewStatus": "accepted",
      "action": "exclude"
    }
  ]
}
```

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

아래에는 미정 정책과 후속 구현 항목이 함께 있다. 미정 정책을 코드로 확정하지 않되, 테스트 가정을 명시하고 기능 개발과 검증은 먼저 진행한다. 개인정보와 법률 검토가 남았다는 이유로 기능 전체를 보류하지 않는다. 실제 사용자 자료를 사용하기 전에는 [사용 전 확인 사항](../legal/README.md#개발-우선과-실제-사용자-자료-사용-전-확인)을 처리한다. 괄호의 번호는 [API 명세의 미정 사항](api-spec.md#미정-사항)이다.

| 항목 | 무엇이 미정인가 | 확인 주체 |
| --- | --- | --- |
| 계정과 로그인 | 구글 로그인 API는 PR #47에 반영됐다. ADR-007과 공통 Account는 `authProvider`, nullable 이메일을 설명한다. 계정과 동의 이력은 PostgreSQL에 저장하고, 앱 재실행 시 로그인 유지([PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50))와 사용 중 만료 후 자동 재인증([PR #175](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/175))은 구현했다. `displayName`과 `email`의 저장 범위 검토는 남아 있다. | PM, BE, FE |
| 서버 중심 데이터 관리 | 저장 항목은 [API 명세](api-spec.md)에 정의했고 다른 계정의 자원은 404로 막는다. S3 삭제 대기열과 삭제 실행기([PR #204](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/204))는 구현했다. 사진 보관 기간, 단말 보관 범위, 삭제 실행기의 정기 실행과 실제 삭제 확인이 남았다. 음성 원본 임시 처리의 최대 24시간 제한은 유지한다. | BE 제안, FE, AI, PM 공동 확인 |
| 사진 보관과 삭제 | [ADR-001](decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)에 따라 가입 시 선택 동의, 기존 계정 동의 이력 저장과 미동의자의 기능 사용 시 요청으로 PM 결정 완료(2026-10-14). 사진 한 장 삭제(API 3-4, 앱의 삭제 버튼은 아직 없음)와 S3 삭제 실행기([PR #204](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/204))는 구현했다. 사진 보관 동의의 항목과 API, 그 철회 동선, 삭제 실행기의 정기 실행과 실제 삭제 결과 확인은 남아 있다(7). | BE, FE, PM |
| 처리 중인 작업이 있는 삭제 | 카드 생성이나 음성 분석이 처리 중인 프로필 또는 계정을 지울 때 작업을 어떻게 끝낼지 정해야 한다(8). | BE |
| 입력 중인 프로필만 있을 때의 로그인 분기 | 입력 중인 프로필만 있을 때 로그인 직후 그 프로필의 입력을 이어서 할지, 홈으로 갈지 정해야 한다(9). | FE, BE |
| 사진 설명 수정 | 별도 승인 없이 카드 생성에 쓰는 기존 결정은 유지. 앨범 수정 API와 분석 중 수정의 처리는 API 3-3으로 구현했다([PR #205](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/205)). 늦게 온 AI 결과는 보호자 설명을 덮지 않는다(1). | FE, BE, AI |
| 프로필 사진 분석의 동의 구분 | 사진 보관과 AI 분석은 가입 시 별도 선택 항목으로 받고 계정별 이력에 저장하기로 결정했다. 유효한 동의는 반복 요청하지 않는다. AI 분석 동의는 `photoAnalysis` 항목(API 1-1~1-3, 1-6)으로 구현했다([PR #257](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/257)). 미동의 사진은 `pending`에 머물고, 철회하면 분석을 멈추고 저장된 AI 설명을 지운다([#288](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/288), 2026-11-09 PM 결정). 앱은 미동의 계정이 사진을 올리기 전에 동의 시트를 띄우며, 거절 뒤 앱 실행 중이나 다시 띄우지 않기를 고른 기기에서는 묻지 않는다([PR #272](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/272)). 사진 보관 동의를 따로 받는 필드와 API가 남았다(3). | FE, BE, AI, PM |
| 리포트 확인 여부 | 리포트 확인 여부를 저장하지 않아, 확인 후 홈 표시, 제안이 없는 리포트 뒤의 카드 생성 시점과 확인 처리가 정해지지 않았다(2). | PM, BE |
| 피보호자 본인 동의와 대리 동의 | 가입 시 계정의 필수 동의를 받고 매회 녹음 전 같은 체크박스를 다시 요구하지 않는다. [ADR-001의 PM 수정안](decisions/ADR-001-consent-and-temporary-processing.md#녹음-동의-확인-시점)은 피보호자 최초 정보 입력 전 본인 동의를 확인하고, 대리인이 동의할 때는 적법한 대리 권한도 확인하도록 정리한다. 확인 방법과 기록, 철회 처리는 후속 설계이며 현재 프로필 API에 구현돼 있지 않다. | PM, FE, BE, 법률 문서 |
| 카드 생성 로직 | 요청과 결과 형식, 카드 근거(`evidence`) 형식은 [API 4-1 카드 생성 처리](api-spec.md#4-1-카드-생성-처리)를 따른다. 실제 생성 함수 연결은 [PR #120](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/120)으로 마쳤다. 각 값과 주제 피드백의 활용은 PR #110의 설계와 함께 맞춘다. | AI, BE |
| 주제 관리 방식 | 다음 회차에 어떤 주제를 더 자주 다룰지 계산하는 방법을 정해야 한다. 주제는 BE가 부여한 `topicId`로 회차 간에 잇는다. | AI, BE |
| 변경 제안 검토 결과 표시 | 검토 뒤 응답에 보호자가 고른 행동과 고친 생애 정보를 담을지 정해야 한다(10). | FE, BE |
| STT 저신뢰도와 실패 상태 | 성공 응답 형식은 확정했지만 신뢰도가 낮거나 모델 처리가 실패한 작업의 상태와 오류 계약은 정해지지 않았다. | AI, BE |
