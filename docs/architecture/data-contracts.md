# 공통 데이터 계약

- 상태: v0.1, 현재 목 화면과 합성 데이터의 기준. 실제 저장과 모델 연동에 필요한 미결 항목 포함
- 아래 예시는 모두 합성 데이터다. 구현 과정에서 변경할 수 있지만 필드와 enum 변경은 세 영역이 공동 검토한다.

## 현재 적용 범위

PR #37의 문서 정리는 기존 JSON과 enum을 유지했고, PR #38에서 Account의 `loginId`를 `authProvider`로 바꾸고 nullable `email`을 반영했다. 계정 목 데이터와 FE 파싱도 같은 변경을 따르며, 아래의 나머지 차이는 실제 연동 전에 FE, AI, BE와 PM이 함께 맞춰야 한다.

| 항목 | 현재 계약 또는 목 화면 | 적용할 기준과 남은 일 |
| --- | --- | --- |
| 알림 동의 | 공통 계약, FE와 BE 모두 선택 | [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)에서 BE 규칙과 회귀 테스트를 맞춤. 실제 앱 로그인 연동 검증은 PR #50의 후속 작업 |
| 사진 전송 | ProfilePhoto 절에서 서버 요청 제외 | [ADR-006](decisions/ADR-006-server-side-ai-processing.md)은 동의한 원본의 임시 처리를 허용. 업로드 요청과 삭제 상태 계약은 별도 설계 필요 |
| 카드 수와 선택 | 12장 생성, 9장 제시와 3장 보충, 보호자 선택으로 명시 | [PM 미결 항목](../pm/README.md#검토-중인-제품-결정)과 달라 확정 여부 확인 필요. 이번 정리에서 수치와 선택 규칙은 변경하지 않음 |
| 이미지 출력 | 단어 태그와 acceptedTags | 태그, 설명과 결합 출력 비교 중. 확정 후 계약과 화면을 함께 변경 |
| 피보호자 동의 | 본인 확인 필드만 존재 | 대리 동의의 자격과 확인 절차는 법률 검토 필요 |
| 저장과 상태 전이 | 값 정의는 있으나 영속 저장 미연결. 단말 중심 필드가 남아 있음 | [ADR-006](decisions/ADR-006-server-side-ai-processing.md)의 서버 중심 방향에 맞춰 [이슈 18](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/18)에서 저장 항목, 단말 보관 범위, 접근 권한, 기간, 삭제와 갱신 주체 합의 |
| 직접 식별정보 | Profile의 `localOnly`는 서버 요청에서 제외 | 현행 제한 유지. 서버 중심 방향만으로 전송하지 않으며 필드별 필요성, 동의와 접근 범위 검토 후 별도 계약 변경 |
| 보호자 평가 | PR #42로 미사용, 미응답과 중립 평가를 구분하는 화면 및 계약 반영 | 2026-09-19 PM 결정으로 미사용 및 미응답만으로 비선호 추정, 추천 하향 및 제외 금지. DB null 허용과 회차별 조회는 구현 확인 필요 |
| 승인된 사실의 출처 | 면회 중 확인한 LifeFact는 생성 시 sourceSessionId 연결 | 면회 삭제 시 승인된 사실은 유지하고 해당 출처 연결만 null로 해제. 저장과 삭제 후 표시의 구현 검증은 후속 작업 |
| 리포트 | 일기형 요약과 카드별 요약 | 테크스펙의 관찰값과 계산 불가 이유를 어떤 필드로 전달할지 조율 |

공통 규칙과 [객체 목록](#객체와-담당)에서 필요한 항목으로 이동한다. [결정 대기 항목](#결정-대기-항목)의 카드 생성, STT와 주제 갱신은 아직 완성된 처리 계약이 아니다.

## 공통 규칙

| 항목 | 기준 |
| --- | --- |
| JSON 필드 | `lowerCamelCase` |
| 시간 | 시간대를 포함한 ISO 8601 문자열 |
| 음성 구간 | 밀리초 정수 |
| 없는 값 | 빈 문자열 대신 `null` |
| 빈 목록 | 빈 배열 |
| 버전 | 최상위 `schemaVersion` |
| 신뢰도 | 0.0 이상 1.0 이하, 제공할 수 없으면 `null` |
| 오류 | `errorCode`와 사용자용 `message` 분리 |

- 실제 이름, 직접 식별정보와 로컬 파일 경로는 외부 AI 요청 객체에 포함하지 않는다.
- 원본 음성과 이미지를 프로젝트 서버에서 임시 처리하는 요청은 동의 상태, 만료시각과 삭제 상태를 포함해야 하며 최대 24시간을 넘기지 않는다.

<br>

## 화면 흐름

    구글 로그인 → 필수 동의 확인
    → 기본 정보 입력 → 세부 정보 입력 → 사진 첨부 → 사진 분석 결과 확인
    → 대화 카드 선택 → 면회 사진 촬영
    → 녹음 → 면회 중 대화 카드 → 대화 카드 보충
    → 보호자 평가
    → 리포트 → 변경 사항 확인

- 별도의 회원가입 단계를 두지 않는다. 구글 인증에 성공하면 필수 동의를 확인하고, 동의가 완료될 때 계정과 동의 이력을 함께 만든다. 동의를 거부하거나 중단하면 계정을 만들지 않는다. 현재 구현은 최초 가입 시 동의만 처리하며, 약관 변경 시 재동의는 후속 설계한다.
- 마이페이지에서 프로필 수정과 리포트 기록 확인을 할 수 있으며 위 흐름과 별개로 언제든 진입 가능하다.

<br>

---

## 객체와 담당

| 객체 | 만드는 쪽 | 읽는 쪽 |
| --- | --- | --- |
| [Account](#계정-account) | BE | FE |
| [Profile](#프로필-profile) | FE | FE, AI |
| [LifeFact](#확인된-생애-사실-lifefact) | FE | FE, AI |
| [LifeFactCollectionState](#생애-정보-입력-상태-lifefactcollectionstate) | FE | FE |
| [ProfilePhoto](#프로필-사진-profilephoto) | FE | FE |
| [ImageAnalysisCandidate](#이미지-분석-후보-imageanalysiscandidate) | AI | FE |
| [CardGenerationRequest](#카드-생성-요청-cardgenerationrequest) | FE | AI |
| [ConversationCard](#대화-카드-결과-conversationcard) | AI | FE |
| [VisitSession](#면회-회차-visitsession) | FE | FE, AI |
| [VisitPhoto](#면회-사진-visitphoto) | FE | FE |
| [SpeechAnalysisJob](#비동기-음성-분석-작업-speechanalysisjob) | BE | FE, BE |
| [SpeechAnalysisResult](#stt와-화자-처리-결과-speechanalysisresult) | AI | BE, AI |
| [CaregiverEvaluation](#보호자-평가-caregiverevaluation) | FE | AI |
| [VisitReport](#리포트-초안-visitreport) | AI | FE |
| [ChangeProposal](#변경-제안-changeproposal) | AI | FE |

- 서버 중심 데이터 관리의 저장 구조와 전달 방식은 BE가 제안하고 FE, AI와 PM이 함께 확인한다. 객체별 저장 항목, 단말 보관 여부와 보관 기간은 아직 확정하지 않았다. 위 표는 현행 목 계약에서 값을 만드는 쪽과 읽는 쪽을 나타내며, 서버 저장 권한이나 API 계약을 확정한 표가 아니다.
- `Account`는 백엔드가 구글 ID 토큰을 검증하고 필수 동의가 완료될 때 서버에서 만든다. FE는 로그인과 동의 화면을 제공하고 결과를 읽는다.
- `selectionStatus`와 `reviewStatus`처럼 사용자가 확인해서 바꾸는 필드는 AI가 만든 객체라도 FE가 갱신한다.

<br>

---

## 계정 (Account)
```json
{
  "schemaVersion": 1,
  "accountId": "account_demo_001",
  "authProvider": "google",
  "displayName": "보호자",
  "email": null,
  "consent": {
    "consentVersion": "2026-09-06",
    "serviceData": {
      "granted": true,
      "grantedAt": "2026-08-21T11:40:00+09:00"
    },
    "sensitiveData": {
      "granted": true,
      "grantedAt": "2026-08-21T11:40:10+09:00"
    },
    "serviceImprovement": {
      "granted": false,
      "grantedAt": null
    },
    "pushNotification": {
      "granted": true,
      "grantedAt": "2026-08-21T11:40:15+09:00"
    }
  },
  "createdAt": "2026-08-21T11:40:00+09:00"
}
```

- 인증은 구글 소셜 로그인을 사용하며 백엔드가 ID 토큰을 직접 검증하는 방향에 PM이 동의했다. 개인정보 저장 항목 등 [ADR-007](decisions/ADR-007-google-social-login.md)의 검토안은 별도로 남아 있다. 아이디와 비밀번호는 받지 않으며, 계정은 구글 인증 뒤 필수 동의가 완료될 때 동의 이력과 함께 만들어진다.
- `authProvider`의 값은 현재 `google` 하나다. 다른 제공자를 더하는 것은 계약 변경으로 본다.
- `displayName`과 `email`의 영구 저장 범위는 검토 중이다. PM은 이메일과 구글 계정 이름을 저장하지 않는 안을 제안했고 BE와 FE가 구현 영향을 확인한다([ADR-007](decisions/ADR-007-google-social-login.md)). 현재 서버의 기본 설정에서는 사용자 입력 표시 이름이 없으면 `보호자`를 사용하고 `email`은 `null`로 반환한다. `displayName`에는 실명이 들어올 수 있으므로 사용자가 수정할 수 있어야 한다.
- `email`은 문자열 또는 `null`이다. 서버가 값을 저장하지 않거나 제공하지 않는 경우 `null`로 보내며, FE는 이를 임의의 주소나 빈 문자열로 채우지 않는다. 누락된 `email`도 FE에서 없는 값으로 읽는다. nullable 응답을 지원하는 변경이며 이메일 미저장 정책을 확정한 것은 아니다.
- `serviceData`(개인정보 수집 동의)와 `sensitiveData`(민감정보 수집 동의)는 필수 동의 사항이며 거부하면 가입을 진행하지 않는다.
- 나머지 둘(`serviceImprovement` 데이터를 서비스 개선에 활용, `pushNotification` 알림 수신)은 선택 동의이며 거부해도 가입과 핵심 기능을 차단하지 않는다.
- `pushNotification`을 거부한 계정에는 푸시 알림을 보내지 않는다. 리포트 도착은 `VisitReport.reportStatus`가 `ready`가 될 때 홈 화면에 표시되므로, 알림을 거부해도 리포트를 받아볼 수 있다.
- 앱은 구글에서 받은 ID 토큰을 백엔드로 보내고, 백엔드가 구글 공개키로 검증한 뒤 기존 계정을 찾거나 필수 동의 완료 시 계정을 만든다. 제공자 식별자(구글 `sub`), 비밀번호와 인증 토큰은 이 계정 객체에 포함하지 않는다.
- PR 50의 약관 서버 관리, 앱 재실행 시 세션 복원과 만료 후 자동 재인증은 후속 구현 요청이다. 이 계정 계약 변경만으로 해당 기능이 완료되지는 않는다.

**없어도 되는 값** — `email`, 선택 동의 항목의 `grantedAt`

<br>

---

## 프로필 (Profile)

```json
{
  "schemaVersion": 1,
  "profileId": "profile_demo_001",
  "localOnly": {
    "name": "김○○",
    "gender": "female",
    "birthDate": "1943-03-12"
  },
  "ageRange": "80s",
  "condition": {
    "stage": "mildCognitiveImpairment",
    "symptomNote": "같은 이야기를 반복하실 때가 있어요"
  },
  "lifeFactIds": ["fact_demo_001"],
  "photoIds": ["profile_photo_demo_001"],
  "createdAt": "2026-08-21T12:00:00+09:00",
  "updatedAt": "2026-08-21T12:00:00+09:00"
}
```

- 현행 계약의 `localOnly`는 단말에만 두며 외부 AI 요청과 서버 임시 처리 요청에 포함하지 않는다. 서버 중심 관리에 필요한 필드별 범위가 합의되고 계약이 변경되기 전에는 이 제한을 유지한다.
- `ageRange`는 `birthDate`에서 계산한다.
- `condition.stage` 값은 `mildCognitiveImpairment`, `mildDementia`, `unknown`이다.

**없어도 되는 값** — `condition.symptomNote`

<br>

---

## 확인된 생애 사실 (LifeFact)

```json
{
  "schemaVersion": 1,
  "factId": "fact_demo_001",
  "profileId": "profile_demo_001",
  "category": "occupation",
  "text": "재봉 일을 오래 하셨어요. 동인천에서 수선집을 하셨는데 한복을 주로 만드셨고 단골도 많았대요.",
  "sourceType": "caregiverVoiceInput",
  "sourceSessionId": null,
  "createdAt": "2026-08-21T12:10:00+09:00",
  "updatedAt": "2026-08-21T12:10:00+09:00"
}
```

- `category` 값은 `occupation`, `hometown`, `hobby`, `family`이다.
- `sourceType` 값은 `caregiverVoiceInput`, `caregiverTextInput`, `visitConfirmed`이다.
- `sourceType`이 `visitConfirmed`인 사실을 생성할 때는 유효한 출처 회차의 `sourceSessionId`가 필요하다. 프로필 입력 화면에서 만든 사실은 `null`로 둔다.
- 출처 면회가 삭제되면 보호자가 승인한 사실은 유지하고 해당 `sourceSessionId`만 `null`로 해제한다. 회차 삭제 후에도 면회에서 확인한 사실이라는 `sourceType`을 다른 입력 방식으로 바꾸지 않는다. 생성 시 출처 검증과 삭제 후 null 허용을 구분하며, 무조건적인 NOT NULL 제약으로 출처 회차 삭제를 막지 않는다.
- 이 규칙은 [2026-09-19 PM 결정](../pm/README.md#2026-09-19-pm-결정)에 따른 면회 기록 삭제 범위다. 계정 탈퇴와 프로필 삭제 범위를 정하거나, 삭제 행동을 부정적 감정 및 비선호로 해석하지 않는다. DB 삭제 동작과 연결이 없는 사실의 화면 표시는 후속 검증이 필요하다.
- 마이페이지에서 내용을 고치면 `updatedAt`을 갱신한다.

**없어도 되는 값** — 프로필에서 직접 입력했거나 출처 면회가 삭제된 사실의 `sourceSessionId`

<br>

---

## 생애 정보 입력 상태 (LifeFactCollectionState)

```json
{
  "schemaVersion": 1,
  "profileId": "profile_demo_001",
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

- `status` 값은 `pending`, `collected`, `skipped`, `manualFallback`이다.
- 음성 인식이 2회 실패하면 `manualFallback`으로 전환한다.
- 건너뛴 항목은 생애 사실을 만들지 않는다.

<br>

---

## 프로필 사진 (ProfilePhoto)

세부 정보 입력 화면에서 첨부한 사진이며 프로필의 갤러리에 저장한다. 사진 첨부는 선택이며 1장으로 제한한다.

```json
{
  "schemaVersion": 1,
  "photoId": "profile_photo_demo_001",
  "profileId": "profile_demo_001",
  "localUri": "local://gallery/profile_photo_demo_001",
  "acceptedTags": ["한복"],
  "createdAt": "2026-08-21T12:20:00+09:00"
}
```

- 이 객체는 사진 원본의 단말 보관 정보를 표현하며 원본 업로드 요청이 아니다. 동의 범위의 서버 임시 처리는 ADR-006을 따르고, 전송과 만료 및 삭제 상태를 전달할 별도 계약은 아직 정하지 않았다.
- `acceptedTags`는 사용자가 수락한 태그이며 갤러리에서 사진과 함께 표시한다.

**없어도 되는 값** — `acceptedTags`

<br>

---

## 이미지 분석 후보 (ImageAnalysisCandidate)

```json
{
  "schemaVersion": 1,
  "photoId": "profile_photo_demo_001",
  "profileId": "profile_demo_001",
  "analysisStatus": "completed",
  "candidates": [
    {
      "candidateId": "candidate_demo_001",
      "text": "한복",
      "reviewStatus": "accepted"
    },
    {
      "candidateId": "candidate_demo_002",
      "text": "결혼식",
      "reviewStatus": "pending"
    },
    {
      "candidateId": "candidate_demo_003",
      "text": "바닷가",
      "reviewStatus": "pending"
    }
  ],
  "error": null
}
```

- `analysisStatus` 값은 `pending`, `processing`, `completed`, `failed`이다.
  - 분석에 실패해도 프로필 입력을 계속 진행할 수 있어야 한다.
- `candidates`는 AI가 신뢰도 높은 순으로 정렬해 상위 6개만 반환하며, 배열 순서가 곧 추천 순위다.
- `reviewStatus` 값은 `pending`, `accepted`, `rejected`이다. `ChangeProposal.changes[].reviewStatus`와 값 이름은 겹치지만 같은 상태 타입이 아니며, 후보는 되돌릴 대상이 없어 `reverted`를 갖지 않는다.
  - `accepted`가 된 후보만 `ProfilePhoto.acceptedTags`에 저장하며, 확인하지 않고 넘어간 `pending`도 저장하지 않는다.
- 태그는 단어 그대로 저장한다. 태그의 의미를 카드 생성에서 어떻게 사용할지는 AI 영역에서 정한다.
- 사진 메타데이터는 이 객체의 확정값이 아니라 AI 분석에 제공할 수 있는 보조 입력이다. 누락되거나 원래 사건과 다른 값일 수 있으므로 메타데이터만으로 후보, 생애 사실과 스토리를 확정하지 않는다.
- AI 태그와 문맥 정보도 보호자가 확인하기 전에는 후보로만 취급한다. 메타데이터를 보조 입력으로 제한하는 측정 근거는 [사진 메타데이터 추출 보고서](../../local_ai/docs/image_tagging/metadata-extraction-report.md)에 기록한다.

**없어도 되는 값** — `candidates`, `error`

<br>

---

## 카드 생성 요청 (CardGenerationRequest)

> **상태: 결정 대기.** 카드 생성과 추천은 핵심 기능으로 별도 설계한다. [PM 제품 기준](../pm/README.md#카드-미사용과-추천-제외)을 지키며 AI가 로직을 설계하고 PM, FE와 BE가 제품 및 연동 범위를 함께 확인한다. 아래는 FE가 화면에서 수집할 수 있는 값의 목록이며 형식 제안이 아니다.

```json
{
  "schemaVersion": 1,
  "requestId": "request_demo_001",
  "profileId": "profile_demo_001",
  "context": {
    "ageRange": "80s",
    "conditionStage": "mildCognitiveImpairment",
    "confirmedLifeFacts": [
      {
        "factId": "fact_demo_001",
        "category": "occupation",
        "text": "재봉 일을 오래 하셨어요. 동인천에서 수선집을 하셨는데 한복을 주로 만드셨고 단골도 많았대요."
      }
    ],
    "topicPriorities": []
  },
  "constraints": {
    "avoidRecentMemoryCheck": true,
    "avoidMedicalInterpretation": true
  }
}
```

- `topicPriorities`는 지난 회차 변경 제안에서 승인된 주제 우선순위이며 첫 회차에는 빈 배열이다.

<br>

---

## 대화 카드 결과 (ConversationCard)

```json
{
  "schemaVersion": 1,
  "requestId": "request_demo_001",
  "generationStatus": "completed",
  "cards": [
    {
      "cardId": "card_demo_001",
      "topicKey": "sewing",
      "topicTitle": "재봉 일",
      "topicDescription": "젊은 시절 하시던 일과 그때의 하루를 여쭤보는 주제예요.",
      "primaryQuestion": "어떤 옷을 주로 만드셨어요?",
      "followUpQuestions": [
        "일할 때 자주 쓰던 도구가 있었어요?",
        "함께 일하던 분들은 어떤 분들이었어요?",
        "가장 기억에 남는 옷은 무엇이었어요?"
      ],
      "evidenceRefs": ["fact_demo_001"],
      "selectionStatus": "unselected"
    }
  ],
  "error": null
}
```

- `generationStatus` 값은 `pending`, `processing`, `completed`, `failed`이다.
- `topicKey`는 주제를 회차 간에 잇는 식별자이며, 같은 주제는 회차가 달라도 같은 값을 쓴다.
- `topicDescription`은 이 카드가 어떤 주제인지 보호자에게 알려주는 설명이다. 어르신에게 그대로 여쭙는 문장은 `primaryQuestion`이며 둘은 역할이 다르다.
- `selectionStatus` 값은 `unselected`와 `selected`이며 선택하지 않은 카드도 삭제하지 않는다.
- `followUpQuestions`는 카드마다 3개를 기본으로 한다.
  - 한 회차에 12장을 만들며 선택 화면에서 9장을 보여주고 나머지 3장은 면회 중 보충용으로 남긴다.
  - 배열의 앞 9장이 선택 화면 대상이고 뒤 3장이 면회 중 보충용이다.
- 면회 중 보충 화면에서 남은 3장을 추천하며, 사용자가 고른 카드만 `selectionStatus`를 `selected`로 바꾸고 `VisitSession.selectedCardIds`에 추가한다.

**없어도 되는 값** — `evidenceRefs`, `error`

<br>

---

## 면회 회차 (VisitSession)

```json
{
  "schemaVersion": 1,
  "sessionId": "session_demo_001",
  "profileId": "profile_demo_001",
  "selectedCardIds": ["card_demo_001"],
  "sessionStatus": "processing",
  "photoId": "visit_photo_demo_001",
  "consent": {
    "consentVersion": "2026-09-06",
    "serviceData": {
      "granted": true,
      "grantedAt": "2026-08-21T13:55:00+09:00"
    },
    "sensitiveData": {
      "granted": true,
      "grantedAt": "2026-08-21T13:55:10+09:00"
    },
    "careRecipientConfirmation": {
      "confirmed": true,
      "confirmedAt": "2026-08-21T13:59:30+09:00"
    }
  },
  "recordingAuthorization": {
    "granted": true,
    "grantedAt": "2026-08-21T13:59:30+09:00"
  },
  "participantCount": 2,
  "startedAt": "2026-08-21T14:00:00+09:00",
  "endedAt": "2026-08-21T14:20:00+09:00"
}
```

- `sessionStatus` 값은 `ready`, `recording`, `paused`, `ended`, `processing`, `completed`, `failed`이다.
  - 녹음 정지는 면회 종료를 뜻하며 `ended`가 된다.
- `serviceData`, `sensitiveData`와 `careRecipientConfirmation`이 유효하지 않으면 녹음과 원본 업로드를 시작하지 않는다.
- `careRecipientConfirmation`은 피보호자 본인의 동의만 담는다.
- `participantCount`는 녹음을 끝낼 때 보호자가 확인한 1~8의 인원수다. STT 요청의
  `speakerCount`로 이름만 바꾸어 전달하며 앱이나 서버가 추정하지 않는다.
- 세션은 대화 카드를 선택한 시점에 `ready` 상태로 만든다. 동의 확인과 녹음 승인, 시작 시각은 녹음을 시작할 때 채운다.

**없어도 되는 값** — `photoId`, `endedAt`, `startedAt`, `participantCount`, `recordingAuthorization`, `consent.careRecipientConfirmation`

<br>

---

## 면회 사진 (VisitPhoto)

```json
{
  "schemaVersion": 1,
  "photoId": "visit_photo_demo_001",
  "sessionId": "session_demo_001",
  "localUri": "local://visit/visit_photo_demo_001",
  "capturedAt": "2026-08-21T13:58:00+09:00",
  "skipped": false
}
```

- 촬영하지 않으면 `skipped`를 `true`로 두고 `localUri`는 `null`로 둔다.
- 사진 원본은 단말에 둔다.

**없어도 되는 값** — `localUri`, `capturedAt`

<br>

---

## 비동기 음성 분석 작업 (SpeechAnalysisJob)

> **상태: ADR-008 제안 및 BE 구현 검증 중.** FE, AI, PM 공동 확인 전에는 실제 사용자
> 자료 전송 승인을 뜻하지 않는다.

앱은 WAV와 `participantCount`를 multipart 요청으로 제출한다. BE가 원본을 S3에
임시 저장하고 작업을 영속화한 뒤 다음 `202 Accepted` 응답을 반환한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "sessionId": "4ad84021-e2db-4a04-8995-b148f3cdb853",
  "status": "queued"
}
```

`GET /api/v1/speech-analyses/{analysisId}`는 같은 계정이 소유한 작업에 한해 다음 상태를
반환한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "sessionId": "4ad84021-e2db-4a04-8995-b148f3cdb853",
  "status": "sttCompleted",
  "errorCode": null
}
```

- 공개 상태는 `queued`, `transcribing`, `sttCompleted`, `generatingReport`,
  `completed`, `failed`다.
- `sttCompleted`는 AI 응답 검증과 원본 삭제까지 끝났지만 리포트는 아직 준비되지 않은 상태다.
- `completed`는 STT뿐 아니라 리포트 저장까지 끝난 상태다.
- 실패 시 `errorCode`만 제공하며 AI 오류 본문, 전사문, S3 URL과 객체 키를 제공하지 않는다.
- 한 면회에는 음성 분석 작업 하나만 두어 반복 제출로 중복 처리하지 않는다.
- 자세한 상태 전이, 삭제와 재시도 경계는 [ADR-008](decisions/ADR-008-stt-pipeline.md)을 따른다.

<br>

---

## STT와 화자 처리 결과 (SpeechAnalysisResult)

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

리포트보다 먼저 만들어지며 리포트 생성의 입력이 된다.

```json
{
  "schemaVersion": 1,
  "reviewId": "review_demo_001",
  "sessionId": "session_demo_001",
  "conversationSatisfaction": 4,
  "careRecipientReaction": "pleased",
  "cardReviews": [
    {
      "cardId": "card_demo_001",
      "wasUsed": true,
      "caregiverReaction": "positive"
    },
    {
      "cardId": "card_demo_010",
      "wasUsed": false,
      "caregiverReaction": null
    }
  ],
  "freeNote": null,
  "createdAt": "2026-08-21T14:25:00+09:00"
}
```

- `conversationSatisfaction`은 1 이상 5 이하의 정수다.
- `careRecipientReaction` 값은 `pleased`, `calm`, `angry`, `lowEnergy`, `unknown`이다.
- `caregiverReaction` 값은 `positive`, `neutral`, `negative`이다.
- `cardReviews`는 **미사용과 미응답을 구분한다.** 어느 쪽도 그 사실만으로 비선호를 추정하거나 추천 순위를 낮추거나 추천 대상에서 제외하지 않는다.

| 보호자가 한 일 | `cardReviews` | 추천에 반영할 기준 |
| --- | --- | --- |
| 카드를 쓰고 평가했다 | `wasUsed`가 `true`이고 `caregiverReaction`을 담는다 | 명시된 평가는 보존하되 가중치와 반영 방식은 별도 추천 로직에서 정한다 |
| 쓰지 않았다고 답했다(미사용) | `wasUsed`가 `false`이고 `caregiverReaction`은 `null`이다 | 미사용만으로 비선호를 추정하거나 추천을 낮추거나 제외하지 않는다 |
| 답하지 않고 넘어갔다(미응답) | 그 카드를 **담지 않는다** | 응답이 없으므로 비선호를 추정하거나 추천을 낮추거나 제외하지 않는다 |

- 미응답을 미사용으로 읽지 않는다. 미사용도 시간 부족이나 나중에 이야기하려는 선택일 수 있어 사용자의 의도를 대신 판단하지 않는다.
- 추천 대상 제외는 사용자가 `앞으로 추천하지 않기`처럼 명시적으로 선택했을 때 적용한다. 이는 과거 카드와 면회 기록 삭제가 아니다. 해당 선택의 저장 필드 및 API, 제외 대상 범위와 해제 방식은 아직 정하지 않았으며 `wasUsed=false`로 대신 표현하지 않는다.
- 리포트의 `cardSummaries`에는 세 경우가 모두 올 수 있다. 화면은 미사용과 미응답을 분석 결과 대신 그 사실로 표시한다.

**없어도 되는 값** — `freeNote`, `wasUsed`가 `false`일 때의 `caregiverReaction`

<br>

---

## 리포트 초안 (VisitReport)

```json
{
  "schemaVersion": 1,
  "reportId": "report_demo_001",
  "sessionId": "session_demo_001",
  "reviewId": "review_demo_001",
  "reportStatus": "ready",
  "title": "재봉 일 이야기를 나눈 날",
  "visitDate": "2026-08-21",
  "mood": "good",
  "photoId": "visit_photo_demo_001",
  "summaryText": "오늘은 재봉 일을 하시던 시절 이야기를 나눴어요. 동인천 수선집에서 한복을 만드시던 때를 떠올리시며 오래 말씀해주셨고, 함께 일하던 분들 이야기가 나올 때는 기분이 좋아 보이셨어요. 오늘은 이야기가 잘 풀린 날이었어요.",
  "cardSummaries": [
    {
      "cardId": "card_demo_001",
      "topicTitle": "재봉 일",
      "summary": "한복을 주로 만드셨고 함께 일하던 분들 이야기를 하셨어요."
    }
  ]
}
```

- `reportStatus` 값은 `generating`, `ready`, `reviewed`, `acknowledged`이다.
  - `ready`가 되면 홈 화면에서 리포트 도착 알림을 표시하고, 변경 제안까지 수락하면 `acknowledged`로 바꾼다.
- `summaryText`는 일기 형식의 본문이다.
  - 보호자 평가에서 입력받은 값을 모두 재료로 사용하며, 입력하지 않은 값은 빼고 작성한다.
- `mood`는 보호자의 감정이며 별도로 입력받지 않고 `conversationSatisfaction`에서 계산한다.
  - 값은 `hard`, `normal`, `good`이며 1~2는 `hard`, 3은 `normal`, 4~5는 `good`이다.
- 리포트는 보호자 평가와 대화 내용을 정리해 보여주며 의료적 해석과 대화 품질 점수를 만들지 않는다.

**없어도 되는 값** — `photoId`

<br>

---

## 변경 제안 (ChangeProposal)

> **상태: 결정 대기.** 주제 관리 방식은 AI 영역에서 확정한다. 아래는 변경 사항 확인 화면에 필요한 값의 목록이며 산출 방식 제안이 아니다.

```json
{
  "schemaVersion": 1,
  "proposalId": "proposal_demo_001",
  "profileId": "profile_demo_001",
  "reportId": "report_demo_001",
  "proposalStatus": "pendingReview",
  "changes": [
    {
      "changeId": "change_demo_001",
      "changeType": "topicPriority",
      "topicKey": "oldSongs",
      "topicTitle": "노래 이야기",
      "direction": "up",
      "reason": "노래 이야기에 반응이 좋으셨어요.",
      "reviewStatus": "pending"
    },
    {
      "changeId": "change_demo_002",
      "changeType": "lifeFactAdd",
      "text": "한복을 주로 만드셨어요.",
      "reason": "이번 면회에서 확인되었어요.",
      "reviewStatus": "accepted"
    }
  ],
  "createdAt": "2026-08-21T14:26:00+09:00"
}
```

- `proposalStatus` 값은 `pendingReview`, `reviewed`이다.
- `changeType` 값은 `topicPriority`와 `lifeFactAdd`이다. 기존 생애 사실의 수정은 제안하지 않으며 사용자가 마이페이지에서 직접 수정한다.
  - `topicPriority`는 `topicKey`, `topicTitle`, `direction`을 갖고 `text`를 갖지 않는다.
  - `lifeFactAdd`는 `text`를 갖고 나머지 셋을 갖지 않는다.
  - `changeId`, `changeType`, `reason`, `reviewStatus`는 두 타입 모두 갖는다.
- `topicPriority`는 다음 회차에 이 주제를 더 자주 다룰지 덜 다룰지에 대한 제안이며 주제 단위로 적용한다. `direction` 값은 `up`과 `down`이다.
- 미사용 및 미응답만으로 `direction: down`을 제안하지 않는다. 추천 제외 의사와 우선순위 조정은 구분하며, 명시적 제외를 이 필드에 임의로 추가하지 않는다. 세부 추천 로직과 제외 계약은 후속 설계한다.
- 각 변경의 `reviewStatus` 값은 `pending`, `accepted`, `rejected`, `reverted`이다. 제안은 승인 전까지 프로필에 반영하지 않으며 승인 후에도 되돌릴 수 있다.
- 변경 사항 확인 화면에서 사용자가 제외하지 않고 최종 승인한 항목은 `accepted`, 제외한 항목은 `rejected`로 저장하며, 반영하면 `proposalStatus`를 `reviewed`로 바꾼다.

<br>

---

## 변경 절차

[객체 목록](#객체와-담당)의 이름과 enum은 연동 전에 FE, AI, BE가 함께 확인한다.

- 필드 추가와 enum 값 추가도 계약 변경으로 본다. 한 영역이 단독으로 변경하지 않는다.
- 계약을 변경하면 `mock/`의 합성 데이터를 같은 PR에서 함께 갱신한다.
- 하위 호환성을 깨는 변경은 관련 README와 ADR을 함께 갱신한다.

<br>

---

## 결정 대기 항목

아래 항목은 아직 정해지지 않았다. 확정 전까지 구현으로 먼저 정하지 않는다.

| 항목 | 무엇이 미정인가 | 확인 주체 |
| --- | --- | --- |
| 계정과 로그인 | 구글 로그인 API는 PR #47에 반영됐다. ADR-007과 공통 Account는 `authProvider`, nullable 이메일을 설명한다. 저장 항목과 DB 연결, 앱 로그인 유지는 후속 검토 및 구현이다. | PM, BE, FE |
| 서버 중심 데이터 관리 | 데이터별 서버 저장 항목, 단말 보관 여부, 접근 권한, 보관 기간과 삭제 구현을 정해야 한다. 원본 임시 처리의 최대 24시간 제한은 유지한다. | BE 제안, FE, AI, PM 공동 확인 |
| 피보호자 대리 동의 | 현재 계약은 피보호자 본인의 동의만 담는다. 병세가 진행되어 본인이 동의하기 어려운 경우(ex. 음성 녹음 동의 등) 누가 어떤 근거로 대신 동의할 수 있는지 정해야 한다. | PM, 법률 문서 |
| 카드 생성과 추천 로직 | 핵심 기능으로 별도 설계한다. 입력 문맥, 기억 검색, 이미지 후보 활용과 평가 반영 방식을 정한 뒤 `CardGenerationRequest`의 형식을 확정한다. 미사용 및 미응답만으로 비선호를 추정하지 않는 원칙은 확정이다. | AI 설계, PM, FE, BE 공동 확인 |
| 주제 관리와 명시적 추천 제외 | `topicKey`, 주제별 가중치, 명시적 제외의 대상 범위, 해제 방식, 화면과 저장 필드 및 API를 정해야 한다. 추천 제외와 과거 기록 삭제는 별개다. | AI, PM, FE, BE |
| 비동기 STT 운영 계약 | ADR-008의 API와 상태 초안은 구현 검증 중이다. 자동 재시도, 취소, 리포트 생성 계약과 전사문 장애 복구 저장 여부는 공동 확인이 필요하다. | BE 제안, FE, AI, PM 공동 확인 |
