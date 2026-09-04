# 공통 데이터 계약

- 상태: v0.1, FE, AI와 BE가 함께 사용하는 기준
- 아래 예시는 모두 합성 데이터다. 구현 과정에서 변경할 수 있지만 필드와 enum 변경은 세 영역이 공동 검토한다.

<br>

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

    회원가입 → 로그인
    → 기본 정보 입력 → 세부 정보 입력 → 사진 첨부 → 사진 분석 결과 확인
    → 대화 카드 선택 → 면회 사진 촬영
    → 녹음 → 면회 중 대화 카드 → 대화 카드 보충
    → 보호자 평가
    → 리포트 → 변경 사항 확인

- 마이페이지에서 프로필 수정과 리포트 기록 확인을 할 수 있으며 위 흐름과 별개로 언제든 진입 가능하다.

<br>

---

## 객체와 담당

| 객체 | 만드는 쪽 | 읽는 쪽 |
| --- | --- | --- |
| `Account` | FE | FE |
| `Profile` | FE | FE, AI |
| `LifeFact` | FE | FE, AI |
| `LifeFactCollectionState` | FE | FE |
| `ProfilePhoto` | FE | FE |
| `ImageAnalysisCandidate` | AI | FE |
| `CardGenerationRequest` | FE | AI |
| `ConversationCard` | AI | FE |
| `VisitSession` | FE | FE, AI |
| `VisitPhoto` | FE | FE |
| `SpeechAnalysisResult` | AI | AI |
| `CaregiverEvaluation` | FE | AI |
| `VisitReport` | AI | FE |
| `ChangeProposal` | AI | FE |

- 모든 객체의 단말 저장과 로컬 DB 구조는 BE가 소유하며, 저장과 전달 방식은 BE 계약을 따른다.
- `selectionStatus`와 `reviewStatus`처럼 사용자가 확인해서 바꾸는 필드는 AI가 만든 객체라도 FE가 갱신한다.

<br>

---

## 계정 (Account)
```json
{
  "schemaVersion": 1,
  "accountId": "account_demo_001",
  "loginId": "demo_user",
  "displayName": "보호자",
  "email": "demo@example.com",
  "consent": {
    "consentVersion": "2026-08-22",
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
      "granted": false,
      "grantedAt": null
    }
  },
  "createdAt": "2026-08-21T11:40:00+09:00"
}
```

- `serviceData`(개인정보 수집 동의)와 `sensitiveData`(민감정보 수집 동의)는 필수 동의 사항이며 거부하면 가입을 진행하지 않는다.
- 나머지 둘(데이터를 서비스 개선에 활용, 알림 수신)은 선택 동의이며 거부해도 핵심 기능을 차단하지 않는다.
- 비밀번호와 인증 토큰은 이 계약에 포함하지 않는다.

**없어도 되는 값** — 선택 동의 항목의 `grantedAt`

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

- `localOnly`는 단말에만 두며 외부 AI 요청과 서버 임시 처리 요청에 포함하지 않는다.
- `ageRange`는 `birthDate`에서 계산한다.
- `condition.stage` 값은 `mildCognitiveImpairment`, `mildDementia`, `moderateDementia`, `severeDementia`, `unknown`이다.

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
- `sourceSessionId`는 면회 중에 확인한 사실에만 값을 넣고, 프로필 입력 화면에서 만든 사실은 `null`로 둔다.
- 마이페이지에서 내용을 고치면 `updatedAt`을 갱신한다.

**없어도 되는 값** — `sourceSessionId`

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

- 사진 원본은 단말에 두며 외부 AI 요청과 서버 임시 처리 요청에 포함하지 않는다.
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
      "confidence": 0.92,
      "reviewStatus": "accepted"
    },
    {
      "candidateId": "candidate_demo_002",
      "text": "결혼식",
      "confidence": 0.78,
      "reviewStatus": "pending"
    },
    {
      "candidateId": "candidate_demo_003",
      "text": "바닷가",
      "confidence": 0.31,
      "reviewStatus": "pending"
    }
  ],
  "error": null
}
```

- `analysisStatus` 값은 `pending`, `processing`, `completed`, `failed`이다.
  - 분석에 실패해도 프로필 입력을 계속 진행할 수 있어야 한다.
- `reviewStatus` 값은 `pending`, `accepted`, `rejected`이며 `ChangeProposal.changes[].reviewStatus`와 같은 값을 쓴다.
  - `accepted`가 된 후보만 `ProfilePhoto.acceptedTags`에 저장하며, 확인하지 않고 넘어간 `pending`도 저장하지 않는다.
- 태그는 단어 그대로 저장한다. 태그의 의미를 카드 생성에서 어떻게 사용할지는 AI 영역에서 정한다.

**없어도 되는 값** — `candidates`, `error`

<br>

---

## 카드 생성 요청 (CardGenerationRequest)

> **상태: 결정 대기.** 카드 생성 로직은 AI 영역에서 확정한다. 아래는 FE가 화면에서 수집할 수 있는 값의 목록이며 형식 제안이 아니다.

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
    "consentVersion": "2026-08-22",
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
  "startedAt": "2026-08-21T14:00:00+09:00",
  "endedAt": "2026-08-21T14:20:00+09:00"
}
```

- `sessionStatus` 값은 `ready`, `recording`, `paused`, `ended`, `processing`, `completed`, `failed`이다.
  - 녹음 정지는 면회 종료를 뜻하며 `ended`가 된다.
- `serviceData`, `sensitiveData`와 `careRecipientConfirmation`이 유효하지 않으면 녹음과 원본 업로드를 시작하지 않는다.
- `careRecipientConfirmation`은 피보호자 본인의 동의만 담는다.
- 세션은 대화 카드를 선택한 시점에 `ready` 상태로 만든다. 동의 확인과 녹음 승인, 시작 시각은 녹음을 시작할 때 채운다.

**없어도 되는 값** — `photoId`, `endedAt`, `startedAt`, `recordingAuthorization`, `consent.careRecipientConfirmation`

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

## STT와 화자 처리 결과 (SpeechAnalysisResult)

> **상태: 결정 대기.** STT와 화자 처리 결과 형식은 AI 영역에서 확정한다.

- 전사문은 화면에 표시하지 않으며 리포트 생성의 입력으로만 사용한다.

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
    }
  ],
  "freeNote": null,
  "createdAt": "2026-08-21T14:25:00+09:00"
}
```

- `conversationSatisfaction`은 1 이상 5 이하의 정수다.
- `careRecipientReaction` 값은 `pleased`, `calm`, `angry`, `lowEnergy`, `unknown`이다.
- `caregiverReaction` 값은 `positive`, `neutral`, `negative`이다.

**없어도 되는 값** — `freeNote`

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
  "mood": "normal",
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
  - 값은 `hard`, `normal`, `good`이며 1이면 `hard`, 2~4는 `normal`, 5면 `good`이다.
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
- 각 변경의 `reviewStatus` 값은 `pending`, `accepted`, `rejected`, `reverted`이다. 제안은 승인 전까지 프로필에 반영하지 않으며 승인 후에도 되돌릴 수 있다.

<br>

---

## 변경 절차

다음 객체의 이름과 enum은 첫 구현 전에 FE, AI와 BE가 함께 확인한다.

1. `Account`
2. `Profile`
3. `LifeFact`
4. `LifeFactCollectionState`
5. `ProfilePhoto`
6. `ImageAnalysisCandidate`
7. `CardGenerationRequest`
8. `ConversationCard`
9. `VisitSession`
10. `VisitPhoto`
11. `SpeechAnalysisResult`
12. `CaregiverEvaluation`
13. `VisitReport`
14. `ChangeProposal`

- 필드 추가와 enum 값 추가도 계약 변경으로 본다. 한 영역이 단독으로 변경하지 않는다.
- 계약을 변경하면 `mock/`의 합성 데이터를 같은 PR에서 함께 갱신한다.
- 하위 호환성을 깨는 변경은 관련 README와 ADR을 함께 갱신한다.

<br>

---

## 결정 대기 항목

아래 항목은 아직 정해지지 않았다. 확정 전까지 구현으로 먼저 정하지 않는다.

| 항목 | 무엇이 미정인가 | 확인 주체 |
| --- | --- | --- |
| 계정과 로그인 | 계정 기능을 넣을지, 넣는다면 서버를 사용할지 정해지지 않았다. | PM, BE |
| 피보호자 대리 동의 | 현재 계약은 피보호자 본인의 동의만 담는다. 병세가 진행되어 본인이 동의하기 어려운 경우(ex. 음성 녹음 동의 등) 누가 어떤 근거로 대신 동의할 수 있는지 정해야 한다. | PM, 법률 문서 |
| 카드 생성 로직 | 프로필의 어떤 값을 모델에 넣을지, 수락한 이미지 태그를 어떻게 사용할지가 함께 걸려 있다. `CardGenerationRequest`의 형식은 이 결정 이후에 확정한다. | AI |
| 주제 관리 방식 | 다음 회차에 어떤 주제를 더 자주 다룰지 계산하는 방법과, `topicKey`를 어떻게 생성할지가 함께 걸려 있다. 키가 매번 달라지면 회차별 반응 이력이 쌓이지 않는다. | AI |
| STT와 화자 처리 결과 형식 | 전사 결과를 어떤 형태로 넘길지, 신뢰도가 낮을 때 어떤 상태로 표시할지 정해지지 않았다. | AI |