# 합성 목 데이터

- 관리: FE, BE와 AI 리더 공동
- FE, BE와 AI가 서로 기다리지 않고 같은 형식으로 개발하기 위한 합성 데이터다.
- 필드 의미와 enum 설명은 [`../data-contracts.md`](../data-contracts.md)를 따른다.

<br>

## 파일

| 파일 | 담은 객체 |
| --- | --- |
| `account.json` | `Account` |
| `profile.json` | `Profile`, `LifeFact`, `LifeFactCollectionState`, `ProfilePhoto`, `ImageAnalysisCandidate` |
| `conversation-cards.json` | `ConversationCard` 12장 |
| `visit-session.json` | `VisitSession`, `VisitPhoto` |
| `caregiver-evaluation.json` | `CaregiverEvaluation`, `ChangeProposal` |
| `visit-report.json` | `VisitReport` |

- `SpeechAnalysisResult`는 형식이 확정되지 않아 파일을 만들지 않았다. AI 영역에서 확정한 뒤 추가한다.
- `CardGenerationRequest`도 같은 이유로 넣지 않았다.
- 각 파일은 최상위에 `schemaVersion`을 두고, 그 옆에 객체 이름을 딴 키로 내용을 감싼다. 한 파일에 객체가 여럿이면 키도 여럿이다.

<br>

## 담긴 시나리오

보호자 한 명이 첫 면회를 마치고 리포트를 확인하기 직전까지의 한 회차다.

    account_demo_001
    → profile_demo_001
    → 카드 12장 중 4장 선택
    → session_demo_001
    → review_demo_001
    → report_demo_001
    → proposal_demo_001

<br>

## 화면 분기

성공 경로만 담지 않고 화면이 갈라지는 지점을 함께 넣었다.

| 대상 | 담은 상태 |
| --- | --- |
| 생애 정보 입력 | 정상 수집, 건너뜀, 2회 실패 후 수동 입력 |
| 이미지 태그 | 수락, 거부, 미확인 |
| 신뢰도 | 0.92, 0.78, 0.31 |
| 카드 선택 | 선택 3장, 면회 중 보충 1장, 미선택 8장 |
| 카드 반응 | 좋음 2건, 나쁨 1건, 사용하지 않음 1건 |
| 변경 제안 | 우선순위 상승과 하락, 대기와 수락과 거부 |

<br>

## 파일 사이 기준값

여러 파일이 같은 값을 참조한다. 값을 바꾸면 관련 파일을 함께 고친다.

| 대상 | 값 |
| --- | --- |
| 프로필 | `profile_demo_001` |
| 면회 회차 | `session_demo_001` |
| 보호자 평가 | `review_demo_001` |
| 리포트 | `report_demo_001` |
| 선택한 카드 | `card_demo_001`, `card_demo_004`, `card_demo_007`, `card_demo_010` |

- `VisitSession.selectedCardIds`, `CaregiverEvaluation.cardReviews`, `VisitReport.cardSummaries`는 같은 카드 목록을 가리킨다.
- `VisitReport.mood`는 `CaregiverEvaluation.conversationSatisfaction`에서 계산한 값이다.

<br>

## 자료 원칙

- 모든 값은 합성 데이터이며 실제 사용자 자료가 아니다.
- 실제 이름, 시설명, 전사문과 파일 경로를 사용하지 않는다.
- 파일 경로는 `local://` 형태의 가상 경로만 사용한다.

<br>

## 변경

- 필드나 enum이 바뀌면 [`../data-contracts.md`](../data-contracts.md)와 이 폴더의 파일을 같은 PR에서 함께 갱신한다.
- 변경은 FE, BE와 AI가 공동 검토한다.