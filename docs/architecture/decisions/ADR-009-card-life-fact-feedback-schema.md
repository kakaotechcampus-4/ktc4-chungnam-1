# ADR-009: 대화 카드 생성과 면회 결과의 Life Fact 누적 스키마

상태: proposed
담당: BE, AI, FE, PM
제안일: 2026-09-25
관계: [공통 데이터 계약](../data-contracts.md)의 `CardGenerationRequest`,
`ConversationCard`, `LifeFact`, `ChangeProposal`을 구체화한다.

## 배경

기존 스키마는 확정된 생애 사실과 생성된 대화 카드를 저장하지만 다음 연결이
불충분하다.

- 카드 생성 요청에 어떤 Life Fact가 입력됐는지 기록하지 않는다.
- `lifeFactAdd` 변경 제안에는 `life_facts.category`를 만들 정보가 없다.
- 승인된 `topicPriority`를 다음 카드 생성에 사용할 저장소가 없다.
- 미사용 카드는 `caregiverReaction = null`이어야 하지만 DB는 이를 허용하지 않는다.

AI 출력은 확정 사실이 아니다. 면회 결과에서 발견한 생애 정보는 변경 제안으로
보관하고 보호자가 승인한 항목만 `life_facts`에 반영한다. 원본 음성과 전사문은 이
스키마에 추가로 보존하지 않는다.

## 결정

### 전체 관계

```text
profiles
 ├─ life_facts
 │   ├─ card_generation_fact_inputs ── card_generation_requests
 │   └─ card_evidence_refs ─────────── conversation_cards
 ├─ profile_topic_preferences
 └─ visit_sessions
     └─ visit_reports
         └─ change_proposals
             └─ proposal_changes
                 └─ applied_fact_id ── life_facts
```

`change_proposals`는 리포트에서 나온 변경 묶음이고 `proposal_changes`는 검토 가능한
개별 항목이다. 두 테이블 모두 기존처럼 유지하며, `proposal_changes.applied_fact_id`가
승인 후 생성된 Life Fact를 가리킨다. 제안 시점에는 아직 확정 사실이 아니므로 이
값은 `null`이다.

### `life_facts`

`life_facts`는 보호자가 확인한 생애 사실의 원본 저장소다. 벡터 검색을 도입해도
텍스트, 카테고리, 출처와 승인 결과를 벡터 DB만에 저장하지 않는다.

| 열 | 역할 |
| --- | --- |
| `fact_id` | 확정 사실 식별자 |
| `profile_id` | 사실이 속한 프로필 |
| `category` | `occupation`, `hometown`, `hobby`, `family` |
| `text` | 보호자가 확인한 사실 본문 |
| `source_type` | 직접 입력 또는 면회 확인 출처 |
| `source_session_id` | 면회에서 확인된 경우의 출처 회차 |

면회에서 생성한 사실은 `source_type = 'visitConfirmed'`로 저장한다. 출처 회차가
삭제되면 기존 정책대로 `source_session_id`만 `null`로 만들고 승인된 사실은
유지한다. 생성 시 유효한 회차가 필요한지는 서비스 계층에서 검사한다.

### `proposal_changes` 변경

`lifeFactAdd`가 실제 Life Fact로 변환될 수 있도록 다음 열과 제약을 사용한다.

| 열 | nullable | 역할 |
| --- | --- | --- |
| `life_fact_category` | 조건부 | `lifeFactAdd`가 생성할 Life Fact 카테고리 |
| `applied_fact_id` | 예 | 승인 후 생성된 `life_facts.fact_id` |

- `topicPriority`는 `life_fact_category`를 가질 수 없다.
- `lifeFactAdd`는 유효한 `life_fact_category`를 반드시 가진다.
- `topicPriority`, `pending` 및 `rejected` 상태는 `applied_fact_id`를 가질 수 없다.
- `accepted` 상태의 `lifeFactAdd`는 `applied_fact_id`를 반드시 가진다.
- `reverted`는 되돌리기 정책이 확정될 때까지 연결 유지와 연결 해제를 모두 허용한다.
- 하나의 Life Fact를 둘 이상의 변경 항목이 자신이 만든 결과라고 가리킬 수 없도록
  `applied_fact_id IS NOT NULL`인 행에 부분 UNIQUE 인덱스를 둔다.
- 기존 Life Fact 수정 제안은 이번 범위에 넣지 않는다. 따라서 `target_fact_id`는
  추가하지 않는다.

승인 처리는 다음 단일 트랜잭션으로 수행한다.

```text
BEGIN
  1. proposal/change/report/session/profile 소속과 접근 권한 확인
  2. review_status = pending인지 잠금 후 확인
  3. life_facts INSERT
  4. proposal_changes를 accepted로 바꾸고 applied_fact_id 설정
  5. 모든 항목 검토가 끝났으면 change_proposals를 reviewed로 변경
COMMIT
```

트랜잭션 실패 시 승인 상태와 Life Fact가 모두 이전 상태로 돌아가야 한다. 동일
`change_id` 재요청에서는 이미 연결된 `applied_fact_id`를 반환해 중복 사실 생성을
막는다. `reverted`의 구체적인 삭제·보관 정책은 확정 전까지 자동 삭제로 구현하지
않는다.

### `profile_topic_preferences`

승인된 `topicPriority`를 다음 카드 생성에 반영하기 위한 프로필별 저장소다.

| 열 | 제약 및 역할 |
| --- | --- |
| `profile_id` | 프로필 FK, 복합 PK |
| `topic_key` | 회차 간 동일 주제 식별자, 복합 PK |
| `topic_title` | 보호자 표시용 제목 |
| `priority_score` | `-100..100`, 계산 방식은 추천 로직에서 결정 |
| `updated_at` | 마지막 승인 반영 시각 |

`direction = up/down`을 점수에 얼마나 반영할지는 DB가 결정하지 않는다. 서비스가
AI·PM과 합의한 규칙으로 값을 계산하고 DB는 범위만 검증한다. 미사용 또는 미응답만
으로 점수를 낮추지 않는다.

### `card_generation_fact_inputs`

카드 생성 요청에 실제로 전달한 확정 Life Fact를 기록한다.

| 열 | 역할 |
| --- | --- |
| `request_id` | 카드 생성 요청 FK |
| `fact_id` | 입력으로 사용한 확정 Life Fact FK |
| `fact_category_snapshot` | 생성 당시 카테고리 |
| `fact_text_snapshot` | 생성 당시 사실 본문 |
| `fact_updated_at_snapshot` | 생성 당시 Life Fact의 수정 시각 |

복합 PK는 같은 요청에 같은 사실을 중복 전달하지 못하게 한다. 스냅숏은 Life Fact가
나중에 수정되더라도 생성된 카드의 근거를 설명하기 위해 필요하다. 요청이나 프로필을
삭제하면 함께 삭제되며 원본 음성, 전사문과 직접 식별정보는 넣지 않는다.

`card_evidence_refs`와의 역할은 다르다.

- `card_generation_fact_inputs`: 모델에 전달한 전체 Life Fact
- `card_evidence_refs`: 특정 카드가 실제 근거로 사용한 Life Fact

### `card_reviews` 정합성

`caregiver_reaction`을 nullable로 바꾸고 다음 조합만 허용한다.

| `was_used` | `caregiver_reaction` |
| --- | --- |
| `true` | `positive`, `neutral`, `negative` 중 하나 |
| `false` | `null` |

응답하지 않은 카드는 `card_reviews` 행 자체를 만들지 않는다.

## 삭제 정책

| 부모 삭제 | 결과 |
| --- | --- |
| 프로필 삭제 | 해당 Life Fact, 주제 우선순위, 카드 요청과 하위 기록 삭제 |
| 카드 생성 요청 삭제 | 입력 스냅숏과 생성 카드 삭제 |
| Life Fact 삭제 | 입력 연결과 카드 근거 연결 삭제 |
| 출처 면회 삭제 | 승인된 Life Fact 유지, `source_session_id`만 `null` |
| 변경 제안 삭제 | 연결된 확정 Life Fact는 자동 삭제하지 않음 |

변경 제안이 리포트와 함께 삭제되면 `applied_fact_id` 연결 기록은 사라질 수 있지만
승인된 Life Fact는 유지된다. 장기 감사 이력이 필요해지면 제안 삭제 대신 보관 상태를
도입하는 방향으로 재검토한다.

## 이번 범위에서 확정하지 않는 것

- 사용자와 프로필의 다대다 공유 및 역할
- 카카오·네이버 인증 제공자
- 명시적 카드 추천 제외 저장 방식
- 카드의 여러 면회 재사용
- 벡터 모델, 차원과 임베딩 갱신 정책
- 승인된 변경의 `reverted` 처리 방식
- 회차별 동의 및 사진 저장 정책 변경

## 구현 파일

- Alembic: `backend/alembic/versions/f4c8e2a91b73_connect_card_generation_and_life_facts.py`
- 빈 개발 DB: `backend/database/init.sql`
- migration 통합 테스트: `backend/tests/test_migrations.py`

스키마 변경의 기준은 Alembic이다. `init.sql`은 동일한 최종 상태의 빈 개발 DB를
만드는 부트스트랩 파일이며 별도의 `init_modify.sql`은 두지 않는다.

기존 DB에는 카테고리가 없는 `lifeFactAdd` 행이나 연결되지 않은 `accepted` 행이
있을 수 있다. migration은 배포를 막지 않도록 두 신규 CHECK를 PostgreSQL
`NOT VALID`로 추가한다. 이 제약은 migration 이후의 INSERT/UPDATE에는 즉시
적용된다. 기존 행을 보호자가 확인 가능한 카테고리로 보정하고 승인 결과를 연결한
뒤 다음 명령에 해당하는 후속 migration으로 검증 상태를 확정한다.

```sql
ALTER TABLE proposal_changes
    VALIDATE CONSTRAINT ck_proposal_changes_life_fact_category;
ALTER TABLE proposal_changes
    VALIDATE CONSTRAINT ck_proposal_changes_applied_fact_state;
```

## 검증

- `alembic upgrade head`에서 신규 테이블, 열, CHECK와 부분 UNIQUE 인덱스를 확인한다.
- `was_used = false, caregiver_reaction = null` 삽입 성공을 확인한다.
- 유효한 카테고리를 가진 `lifeFactAdd`와 `applied_fact_id` 연결을 확인한다.
- 존재하지 않는 FK, 잘못된 카테고리와 점수 범위가 거부되는지 확인한다.
- `alembic downgrade base` 후 재업그레이드가 가능한지 확인한다.

## 재검토 조건

- Life Fact 수정 이력을 영구 보존해야 할 때
- 여러 보호자가 하나의 프로필을 공유할 때
- 카드 재사용이나 명시적 추천 제외를 구현할 때
- 임베딩 검색 저장소와 모델 버전을 확정할 때
- 리포트와 변경 제안 삭제 후에도 영구 감사 추적이 필요할 때
