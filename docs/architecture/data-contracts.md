# 공통 데이터 계약

상태: FE, AI와 BE가 함께 사용하는 초기 기준

아래 예시는 모두 합성 데이터다. 구현 과정에서 변경할 수 있지만 필드와 enum 변경은 세 영역이 공동 검토한다.

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

실제 이름, 직접 식별정보와 로컬 파일 경로는 외부 AI 요청 객체에 포함하지 않는다. 원본 음성과 이미지를 프로젝트 서버에서 임시 처리하는 요청은 동의 상태, 만료시각과 삭제 상태를 포함해야 하며 최대 24시간을 넘기지 않는다.

## 프로필

```json
{
  "schemaVersion": 1,
  "profileId": "profile_demo_001",
  "displayLabel": "어머니",
  "basic": {
    "relationship": "mother",
    "ageRange": "80s",
    "birthRegion": "전남 순천"
  },
  "preferences": {
    "likedTopics": ["sewing", "oldSongs"],
    "blockedTopics": []
  },
  "lifeFactIds": ["fact_demo_001"],
  "createdAt": "2026-08-21T12:00:00+09:00",
  "updatedAt": "2026-08-21T12:00:00+09:00"
}
```

`displayLabel`과 로컬 사진 경로는 단말 전용이다.

## 확인된 생애 사실

```json
{
  "schemaVersion": 1,
  "factId": "fact_demo_001",
  "profileId": "profile_demo_001",
  "lifePeriod": "adulthood",
  "category": "occupation",
  "text": "재봉 일을 오래 했다",
  "sourceType": "caregiverInput",
  "sourceSessionId": null,
  "verificationStatus": "caregiverConfirmed"
}
```

확인되지 않은 모델 추정은 생애 사실로 저장하지 않는다.

## 카드 생성 요청

카드 수와 선택 방식은 아직 제품 결정 전이므로 계약에서 고정하지 않는다.

```json
{
  "schemaVersion": 1,
  "requestId": "request_demo_001",
  "profileId": "profile_demo_001",
  "context": {
    "subjectLabel": "보호자의 어머니",
    "confirmedLifeFacts": [
      {
        "factId": "fact_demo_001",
        "lifePeriod": "adulthood",
        "text": "재봉 일을 오래 했다"
      }
    ],
    "recentTopicObservations": []
  },
  "constraints": {
    "avoidRecentMemoryCheck": true,
    "avoidMedicalInterpretation": true
  }
}
```

## 대화 카드 결과

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
      "opening": "예전에 재봉 일을 오래 하셨다고 들었어요.",
      "primaryQuestion": "어떤 옷을 주로 만드셨어요?",
      "followUpQuestions": ["일할 때 자주 쓰던 도구가 있었어요?"],
      "evidenceRefs": ["fact_demo_001"],
      "riskFlags": [],
      "selectionStatus": "suggested"
    }
  ],
  "error": null
}
```

카드 배열의 개수와 최종 선택 주체는 PM 결정 후 별도 필드로 확정한다.

## 면회 회차

```json
{
  "schemaVersion": 1,
  "sessionId": "session_demo_001",
  "profileId": "profile_demo_001",
  "selectedCardIds": ["card_demo_001"],
  "sessionStatus": "processing",
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
      "actorType": "self",
      "authorityBasis": "self",
      "confirmedAt": "2026-08-21T13:59:30+09:00"
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
  "recordingAuthorization": {
    "granted": true,
    "grantedAt": "2026-08-21T13:59:30+09:00"
  },
  "startedAt": "2026-08-21T14:00:00+09:00",
  "endedAt": "2026-08-21T14:20:00+09:00"
}
```

`serviceData`, `sensitiveData`와 `careRecipientConfirmation`이 유효하지 않으면 녹음과 원본 업로드를 시작하지 않는다. `serviceImprovement`와 `pushNotification`은 선택 값이며 거부해도 핵심 기능을 차단하지 않는다.

## STT와 화자 처리 결과

```json
{
  "schemaVersion": 1,
  "sessionId": "session_demo_001",
  "analysisStatus": "completed",
  "engine": {
    "name": "local-stt-runtime",
    "model": null,
    "version": null
  },
  "segments": [
    {
      "segmentId": "segment_demo_001",
      "startMs": 120000,
      "endMs": 126000,
      "speakerLabel": "caregiver",
      "text": "예전에 어떤 옷을 주로 만드셨어요?",
      "confidence": 0.91,
      "resultStage": "final",
      "reviewStatus": "notRequired",
      "excludedReason": null
    }
  ],
  "warnings": [],
  "error": null
}
```

권장 화자 값은 `caregiver`, `careRecipient`, `other`, `unknown`이다. 신뢰도가 부족하면 구간을 확정하거나 지표를 계산하지 않는다.

## 리포트 초안

```json
{
  "schemaVersion": 1,
  "reportId": "report_demo_001",
  "sessionId": "session_demo_001",
  "reportStatus": "pendingReview",
  "metrics": {
    "careRecipientSpeechMs": {
      "status": "calculated",
      "value": 252000,
      "unavailableReason": null
    },
    "averageResponseLatencyMs": {
      "status": "unavailable",
      "value": null,
      "unavailableReason": "LOW_SPEAKER_CONFIDENCE"
    }
  },
  "storyCandidates": [],
  "medicalInterpretation": null
}
```

지표 상태는 `calculated`, `unavailable`, `excluded` 중 하나를 사용한다.

## 보호자 평가

```json
{
  "schemaVersion": 1,
  "reviewId": "review_demo_001",
  "reportId": "report_demo_001",
  "sessionId": "session_demo_001",
  "reportAgreement": "partiallyAgree",
  "cardReviews": [
    {
      "cardId": "card_demo_001",
      "wasUsed": true,
      "caregiverReaction": "positive"
    }
  ],
  "approvedStoryCandidateIds": [],
  "rejectedStoryCandidateIds": []
}
```

## 이야기 블록

```json
{
  "schemaVersion": 1,
  "storyBlockId": "story_demo_001",
  "profileId": "profile_demo_001",
  "lifePeriod": "adulthood",
  "title": "재봉 일을 하던 시절",
  "summary": "한복을 주로 만들었다.",
  "sourceSessionIds": ["session_demo_001"],
  "verificationStatus": "caregiverConfirmed",
  "mediaLocalUris": []
}
```

스토리북에는 보호자가 확인한 이야기 블록만 기본 반영한다.

## 변경 제안

```json
{
  "schemaVersion": 1,
  "proposalId": "proposal_demo_001",
  "profileId": "profile_demo_001",
  "sessionId": "session_demo_001",
  "proposalStatus": "pendingReview",
  "changes": [],
  "createdAt": "2026-08-21T14:26:00+09:00"
}
```

제안은 앱 사용자의 승인 전까지 프로필과 스토리북에 반영하지 않는다.

## 변경 절차

다음 객체의 이름과 enum은 첫 구현 전에 FE, AI와 BE가 함께 확인한다.

1. `CardGenerationRequest`
2. `ConversationCard`
3. `VisitSession`
4. `SpeechAnalysisResult`
5. `VisitReport`
6. `CaregiverEvaluation`
7. `LifeStoryBlock`

하위 호환성을 깨는 변경은 관련 README와 ADR을 함께 갱신한다.
