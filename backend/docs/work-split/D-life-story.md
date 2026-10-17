# 작업 D: 일대기

> 담당 화면: **일대기 (`/album` 아래 경로)**
>
> 정본은 [API 명세](../../../docs/architecture/api-spec.md)다. 이 문서는 [PR #125](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/125)에서 목 데이터로 만든 일대기 화면을 서버에 연결하기 위한 분담 문서다. 미정이 아닌 부분(2-3, 2-6, 2-7의 분류와 그림 번호, 2-9 삭제)은 임시 필드 이름으로 구현해 API 명세와 [공통 데이터 계약](../../../docs/architecture/data-contracts.md#확인된-생애-사실-lifefact)에 반영했다. 미정 사항이 결정되면 API 명세를 먼저 고치고 이 문서를 맞춘다. API 명세의 미정 사항 11~13이 아래 D1~D6을 가리킨다.

> [!IMPORTANT]
> **논의가 필요하거나 미정인 사항**
>
> 아래 항목은 확정되지 않았다. 이 문서의 계약과 구현 메모는 **임시 안**을 전제로 쓴 것이며, 결정이 바뀌면 해당 절을 고친다. 근거는 PR #125 본문과 리뷰 댓글(2026-10-15~16)이다.
>
> | # | 항목 | 이 문서의 임시 안 | PR 의견 | 확인할 곳 |
> | --- | --- | --- | --- | --- |
> | D1 | 이야기 분류의 **필드 이름** | `storyCategory`. 값은 `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other` | 분류 저장과 7개 유지는 decmoon05, Sogeum100g 모두 찬성. 이름 `storyCategory`는 PR 본문의 FE 제안이며 확정 전이다. 옛 FE 모델과 미병합 ADR-009가 `category`를 세부 정보 네 항목의 뜻으로 써서 피했다 | FE, BE |
> | D2 | 기본 그림 번호의 **필드 이름**과 면회 승인 이야기의 번호 | `imageNumber`(1~5). 2-6에서는 필수, 7-4로 만드는 이야기는 서버가 1~5 중 하나를 고름 | 번호 저장은 decmoon05, Sogeum100g 모두 찬성. 필드 이름과 서버가 고를지는 정하지 않았다 | FE, BE |
> | D3 | **이야기 삭제 때 대화 카드와 주제 처리** | 생애 정보 행만 지운다. 다음 카드 생성부터 빠지고, 이미 만든 카드와 주제는 기록으로 남긴다. 카드 생성 입력에서 지운 이야기를 가리키는 근거 항목은 뺀다 | decmoon05: 삭제한 이야기는 추천에 쓰지 않고 그 이야기만 근거로 한 주제 카드도 지우는 방향. 여러 이야기를 근거로 한 카드는 확인 요청. 결정 전 | PM, BE(작업 B), AI |
> | D4 | **삭제한 이야기의 내용이 다른 저장소에 남는 문제** | 임시 안 없음. 지금 구조에서는 `card_sets.generation_log.input`에 카드 생성 당시의 이야기 제목과 내용이 그대로 남고, 카드 문구에도 반영돼 있을 수 있다 | PR에서 다루지 않음 | PM(개인정보), BE |
> | D5 | **면회 제안을 승인해 만드는 이야기(7-4)의 분류** | 결정 전까지 7-4 요청은 바꾸지 않는다. 승인된 이야기는 `other`(기타)로 만들고 보호자가 일대기에서 옮긴다 | MoonYoung02: 대화에서 주제를 뽑아 7개 분류로 매핑(`topic_id` 저장 필요, 생성 데이터로 시험 필요). decmoon05: AI가 이야기 후보 응답에 분류를 함께 주고 보호자가 확인·수정. Sogeum100g: 보호자가 직접 고르는 편이 간단하고 정확. **의견이 갈림** | PM, AI, FE, BE(작업 C) |
> | D6 | 삭제한 이야기의 **변경 제안 상태** | 임시 안 없음. 지금 7-3은 제안에서 만든 생애 정보가 있으면 `accepted`, 없으면 `rejected`로 계산하므로, 승인한 이야기를 지우면 그 제안이 `rejected`로 보인다 | PR에서 다루지 않음 | BE(작업 C), FE |
> | D7 | **정렬** | 출시 범위는 담은 날짜(`createdAt`)순. 정렬은 앱이 하며 API에 정렬 인자를 두지 않는다 | MoonYoung02, decmoon05: 출시는 날짜순, 생애 시기순은 출시 후. Sogeum100g: 생애 시기순 필요, `최신순`, `입력순` 필터도 제안 | PM, AI, FE |
> | D8 | **이야기에 사용자 사진 붙이기** | 이 문서의 범위에서 뺀다. 출시 후 후보로 [사진 연결 메모](#출시-후-후보-사진-연결)만 남긴다 | decmoon05: 등록한 프로필 사진을 골라 연결하고 없으면 새로 올리는 방식, 일정에 영향이 있으면 출시 후. Sogeum100g: 필요 | PM, FE, BE(작업 A) |
> | D9 | 기존 `life_facts` 행의 기본값 | migration에서 `story_category = 'other'`, `image_number = 1`로 채운다. 개발 DB의 합성 자료만 있다는 전제다 | PR에서 다루지 않음 | BE |
> | D10 | 카드 생성 입력(4-1 `context.lifeFacts`)에 분류를 넣을지 | 넣지 않는다. 내부 형식은 바꾸지 않는다 | PR에서 다루지 않음 | AI, BE(작업 B) |
>
> 이 밖에 담당자가 정해지지 않았다. 작업 D를 맡을 BE 담당은 PM이 정한다.

## 배경

PR #125(2026-10-15 develop 병합)는 일대기 화면을 목 데이터로 만들었다. 서버 연결과 실기기 확인은 남아 있다.

- 화면: 표지(`/album`), 첫 장(`/album/book`), 분류별 목차(`/album/category/:category`), 이야기 한 편(`.../story/:storyId`), 추가(`/album/new`), 수정(`/album/edit/:storyId`)
- 이야기는 두 종류다.
  - **세부 정보 이야기**: 프로필의 세부 정보 네 항목(`occupation`, `hometown`, `hobby`, `family`)에서 앱이 만든다. 분류는 고정(하시던 일→일, 고향, 취미, 가족)이고, 지우지 않으며, 연필은 프로필 세부 정보 수정(2-4)을 연다. 날짜가 없어 목차 맨 앞에 둔다.
  - **담은 이야기**: `life_facts`의 행이다. 보호자가 일대기에서 직접 담거나(2-6), 면회 변경 제안을 승인해서(7-4) 생긴다. 분류, 제목, 내용, 기본 그림 번호를 가지며 고치고 지울 수 있다.
- 기본 그림은 분류마다 5장, 모두 35장이며 앱 `assets`에 들어 있다(`assets/images/life-story-<분류>-<1~5>.webp`). **서버는 그림 파일을 저장하지 않고 번호만 저장한다.**
- 지금 앱은 분류, 그림 번호, 삭제 API가 없어 추가, 수정, 삭제한 이야기를 **앱이 켜져 있는 동안만** 기억한다(`lifeStoryEditsProvider`).

FE 코드: [life_story.dart](../../../app/lib/features/life_story/life_story.dart)(표시용 모델 `LifeStory`, 분류 enum), [life_story_providers.dart](../../../app/lib/features/life_story/life_story_providers.dart)(목 이야기와 편집 내용 합치기), [life_story_edit_screen.dart](../../../app/lib/features/life_story/life_story_edit_screen.dart)(추가와 수정), [life_story_story_screen.dart](../../../app/lib/features/life_story/life_story_story_screen.dart)(수정과 삭제 버튼)

### 이 문서가 다루는 것과 다루지 않는 것

| 다룸 | 다루지 않음 |
| --- | --- |
| `life_facts`의 분류와 그림 번호 저장 | 생애 시기 저장과 시기순 정렬(D7, 출시 후) |
| 2-3, 2-6, 2-7의 필드 추가 | 이야기 사진 업로드와 연결(D8) |
| 이야기 삭제 API(2-9 신규) | 면회 제안의 AI 분류(D5 결정 뒤 작업 C, AI가 진행) |
| 삭제가 카드 생성 입력에 주는 영향 정리 | 세부 정보 이야기의 그림 번호 저장. 앱이 어르신 ID와 항목 이름으로 계산한다(`detailImageNumber`) |

## 시작하기

- 브랜치: develop에서 `feature/backend-app-life-story`
- DB 사용 규칙: [backend/README.md의 DB 연결과 저장소 작성 규칙](../../README.md#db-연결과-저장소-작성-규칙)
- 쓰는 공통 기반
  - DB와 인증: `DbConnectionDep`(요청별 연결), `CurrentAccountDep`(현재 계정), `require_owned`(소유 확인, `app/services/ownership.py`의 `PROFILE`, `LIFE_FACT`)
  - 기존 구현: 라우트 [routes/life_facts.py](../../app/api/routes/life_facts.py), 저장 [services/life_facts.py](../../app/services/life_facts.py), 스키마 [schemas/profiles.py](../../app/schemas/profiles.py)의 `LifeFactCreateRequest`, `LifeFactUpdateRequest`, `LifeFactResponse`, 테스트 [test_life_facts.py](../../tests/test_life_facts.py)
  - 테스트: 임시 DB fixture `migrated_database_url`, 비동기 실행 `tests/support.run`
- 스키마 변경은 Alembic migration으로 하고 [init.sql](../../database/init.sql)을 같은 최종 상태로 맞춘다.
- 공통 요청, 응답, 오류 형식: [API 명세 공통](../../../docs/architecture/api-spec.md#공통)

## 담당 API

2-6과 2-7은 작업 A가 만든 것을 이어받아 필드를 더한다.

| # | 메서드 | 경로 | 지금 상태 | 이 작업 |
| --- | --- | --- | --- | --- |
| 2-3 | `GET` | `/api/v1/profiles/{profileId}` | 구현됨(미병합) | `lifeFacts[]` 항목에 `storyCategory`, `imageNumber` 추가 |
| 2-6 | `POST` | `/api/v1/profiles/{profileId}/life-facts` | 구현됨(미병합) | 요청과 응답에 `storyCategory`, `imageNumber` 추가 |
| 2-7 | `PATCH` | `/api/v1/life-facts/{factId}` | 구현됨(미병합) | 요청과 응답에 `storyCategory`, `imageNumber` 추가 |
| 2-9 | `DELETE` | `/api/v1/life-facts/{factId}` | 구현됨(미병합) | 행만 삭제. 카드와 주제 처리는 D3 결정을 따름 |
| 7-4 | `POST` | `/api/v1/visit-sessions/{sessionId}/proposals/review` | 구현됨(작업 C) | 요청은 그대로. 승인한 이야기의 분류와 번호는 `create_life_fact` 기본값(D5) |

번호 2-9는 2절의 다음 번호로 붙여 API 명세에 넣었다. 구현은 `feature/backend-app-life-story` 브랜치에 있으며 develop에 병합 전이다.

### 화면과 API

| 화면 | 호출 | 쓰는 값 |
| --- | --- | --- |
| 표지, 첫 장, 목차, 이야기 한 편 | 2-3 | 프로필(이름, 생년월일, 세부 정보 네 항목)과 `lifeFacts[]`. 첫 장의 `최근 추가된 이야기` 세 편은 앱이 `createdAt` 내림차순으로 고른다 |
| 이야기 추가하기 `이야기 담기` | 2-6 | `storyCategory`, `title`, `content`, `imageNumber` |
| 이야기 수정하기 `수정 완료` | 2-7 | 바꾼 필드. 앱은 네 필드를 모두 보내도 된다 |
| 이야기 한 편의 휴지통 → `지우기` | 2-9 | `factId` |
| 세부 정보 이야기의 연필 | 2-4 (기존) | 세부 정보 네 항목 |

## 테이블 쓰기 소유권

| 테이블 | 이 작업이 쓰는 것 | 다른 담당 |
| --- | --- | --- |
| `life_facts` | 열 추가(migration), 2-6, 2-7, 2-9 | 작업 C가 7-4에서 `create_life_fact`로 만든다. 작업 B가 4-1 카드 생성 입력으로 읽는다 |

읽기만 하는 것: `profiles`(소유 확인). `conversation_cards`, `profile_topics`, `card_sets`는 작업 B의 테이블이다. D3에서 카드나 주제를 지우거나 고치기로 정하면 작업 B가 함수를 제공하고 2-9가 그 함수를 같은 트랜잭션에서 부른다.

## 다른 담당과 맞출 함수

- **변경** `create_life_fact(connection, *, profile_id, title, content, source_proposal_id=None, story_category="other", image_number=None)`: 새 인자는 기본값이 있어 작업 C의 7-4 호출은 고치지 않아도 된다. `image_number`가 `None`이면 1~5 중 하나를 서버가 고른다(D2). 트랜잭션을 열지 않고 소유 확인을 하지 않는 기존 규칙은 그대로다.
- **변경** `LifeFact` dataclass와 `list_life_facts`: `story_category`, `image_number`를 더한다. 2-3 응답이 이 값을 쓴다.
- **작업 B와 맞춤** 카드 생성 입력 정리(D3 임시 안): 4-1의 `context.topics[].evidence`와 `context.pastCards[].evidence`에서 지금 `life_facts`에 없는 `factId` 항목을 뺀다. [삭제와 카드 생성](#삭제와-카드-생성)을 참고한다.

## DB 변경

`life_facts`에 두 열을 더한다.

```sql
ALTER TABLE life_facts
    ADD COLUMN story_category VARCHAR(10) NOT NULL DEFAULT 'other'
        CHECK (story_category IN
            ('family', 'hobby', 'work', 'hometown', 'friend', 'travel', 'other')),
    ADD COLUMN image_number SMALLINT NOT NULL DEFAULT 1
        CHECK (image_number BETWEEN 1 AND 5);
```

- 기존 행은 기본값으로 채워진다(D9).
- `DEFAULT`는 migration의 기존 행 채우기와 7-4 경로를 위한 것이다. 2-6은 두 값을 항상 받아 넣는다.
- 분류별 목차는 앱이 2-3 응답에서 나누므로 분류 인덱스는 두지 않는다. 기존 `idx_life_facts_profile(profile_id, created_at)`로 충분하다.
- 그림 수 5는 앱의 `lifeStoryImageCount`와 같다. 그림 수를 바꾸면 이 CHECK와 API 검증을 함께 고친다.

## API 명세와 구현 메모

### 2-3. `GET /api/v1/profiles/{profileId}` — 수정

응답 `200` — [Profile](../../../docs/architecture/api-spec.md#profile). 바뀌는 것은 `lifeFacts[]` 항목뿐이며 형식은 아래 [LifeFact](#lifefact)다.

- `lifeFacts`는 지금처럼 `created_at, fact_id` 오름차순이다. 앱의 목차 순서와 같다.
- 세부 정보 네 항목은 지금처럼 `occupation`, `hometown`, `hobby`, `family`로 오며 `lifeFacts`에 넣지 않는다. 세부 정보 이야기는 앱이 만든다.

**구현 메모**

- 일대기 전용 목록 API는 만들지 않는다. 일대기는 프로필 정보와 이야기를 함께 쓰고 프로필당 이야기 수가 많지 않아 2-3 하나로 그린다.
- 2-3은 프로필 사진의 조회 URL을 만들지 못하면 503(`IMAGE_STORAGE_UNAVAILABLE`)이라 이때 일대기도 열리지 않는다. 지금 일대기는 사진을 쓰지 않지만 계약은 바꾸지 않는다.

<br>

### 2-6. `POST /api/v1/profiles/{profileId}/life-facts` — 수정

일대기의 `이야기 추가하기`에서 호출한다.

요청

```json
{
  "storyCategory": "work",
  "title": "단골손님",
  "content": "수선집에 오래 다닌 단골손님이 많았어요.",
  "imageNumber": 3
}
```

- `storyCategory`: 필수. `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`
- `title`: 필수. 100자 이하, 비울 수 없다.
- `content`: 필수. 비울 수 없다.
- `imageNumber`: 필수. 1~5 정수. 앱이 처음에 하나를 무작위로 골라 두고 보호자가 바꿀 수 있다.

응답 `201` — [LifeFact](#lifefact)

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `PROFILE_NOT_FOUND` | |
| 422 | `INVALID_REQUEST` | 필드가 없거나, 모르는 분류이거나, `imageNumber`가 범위 밖 |

**구현 메모**

- `LifeFactCreateRequest`에 `story_category: StoryCategory`(`Literal[...]`, alias `storyCategory`)와 `image_number: int = Field(ge=1, le=5, alias="imageNumber")`를 더한다.
- 앱의 새 이야기 ID(`local-story-N`)는 응답의 `factId`로 바꾼다.

<br>

### 2-7. `PATCH /api/v1/life-facts/{factId}` — 수정

일대기의 `이야기 수정하기`에서 호출한다. 보낸 필드만 바꾼다.

요청

```json
{
  "storyCategory": "friend",
  "imageNumber": 2
}
```

- 받는 필드: `storyCategory`, `title`, `content`, `imageNumber`. 규칙은 2-6과 같다.
- 네 필드 모두 `null`로 지울 수 없다.
- 분류를 바꿔도 `imageNumber`는 보낸 값이나 저장된 값을 그대로 쓴다. 앱은 번호를 분류와 묶어 그림 파일을 고르므로 서버가 다시 고르지 않는다.
- `createdAt`은 바뀌지 않는다. 고쳐도 목차 순서는 그대로다.

응답 `200` — [LifeFact](#lifefact)

| HTTP | `errorCode` |
| --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` |
| 422 | `INVALID_REQUEST` |

**구현 메모**

- `LifeFactUpdateRequest`에 두 필드를 더하고 `_reject_null`의 대상과 `column_changes`에 넣는다.
- 지금 `update_life_fact`는 `COALESCE(%s, title)`로 두 열만 고친다. 네 열이 되므로 `column_changes()`의 키로 `SET` 절을 만드는 쪽이 낫다. 열 이름은 허용 목록에서만 고른다.
- 면회 제안에서 만든 이야기도 고칠 수 있다. 원래 제안(`life_fact_proposals`)은 바꾸지 않는다.

<br>

### 2-9. `DELETE /api/v1/life-facts/{factId}` — 신규

일대기 이야기 한 편의 휴지통에서 확인 창을 거쳐 호출한다. 본문 없음.

응답 `204`

| HTTP | `errorCode` | 언제 |
| --- | --- | --- |
| 404 | `LIFE_FACT_NOT_FOUND` | 없거나 다른 계정의 이야기. 이미 지운 이야기를 다시 지울 때도 404 |

서버 처리(D3 임시 안)

- `life_facts`의 행을 지운다. 되돌리는 기능은 없다(앱 확인 창: `지운 이야기는 되돌릴 수 없어요.`).
- 다음 카드 생성(4-1)의 `context.lifeFacts`에서 빠진다. 4-1이 요청 때 `life_facts`를 다시 읽으므로 따로 할 일은 없다.
- 이미 만든 카드(`conversation_cards`)와 주제(`profile_topics`)는 지우지 않는다. 면회와 리포트 기록이 카드에 묶여 있기 때문이다.
- 그 이야기를 출처로 한 변경 제안(`life_fact_proposals`)은 지우지 않는다. `life_facts.source_proposal_id`가 사라질 뿐이다(D6).
- 세부 정보 이야기는 `life_facts`의 행이 아니므로 이 API로 지울 수 없다. 앱도 휴지통을 두지 않는다.

**구현 메모**

- `require_owned(connection, LIFE_FACT, fact_id, account_id=...)`로 확인한 뒤 `DELETE FROM life_facts WHERE fact_id = %s RETURNING fact_id`. 돌아온 행이 없으면 같은 계정의 다른 요청이 먼저 지운 것이므로 404다.
- 서비스 함수는 `delete_life_fact(connection, fact_id, *, account_id)`로 `services/life_facts.py`에 둔다. D3에서 카드나 주제 처리를 더하기로 하면 작업 B의 함수를 같은 트랜잭션에서 부른다.
- 라우트의 `_errors`에 204 응답을 적는다(`status_code=status.HTTP_204_NO_CONTENT`, `response_class=Response`).

<br>

### 7-4. `POST /api/v1/visit-sessions/{sessionId}/proposals/review` — 요청 변경 없음

작업 C의 API다. D5가 결정될 때까지 요청과 응답을 바꾸지 않는다.

- 승인한 생애 정보 제안은 `create_life_fact`의 기본값으로 만든다. 분류는 `other`, 그림 번호는 서버가 고른다. 보호자는 일대기의 `기타`에서 찾아 2-7로 옮긴다.
- D5가 정해지면 바뀔 수 있는 곳
  - 보호자가 고름: 7-4 `lifeFacts[]`의 `accepted` 항목에 `storyCategory`(와 `imageNumber`)를 더한다. 변경 사항 확인 화면에 분류 고르기가 생긴다.
  - AI가 제안하고 보호자가 확인: 8-3 결과의 이야기 후보와 `life_fact_proposals`에 분류를 더하고 7-3 응답에 담는다. 7-4는 보호자가 확인한 값을 보낸다. 원래 제안의 분류는 바꾸지 않는다(기존 7-4 규칙과 같음).

<br>

## 삭제와 카드 생성

D3 결정 전의 임시 안이다. 지금 구조에서 이야기를 지울 때 영향을 받는 곳을 정리한다.

| 저장소 | 지운 이야기와의 관계 | 임시 안의 처리 |
| --- | --- | --- |
| `life_facts` | 지운 행 | 삭제 |
| 4-1 `context.lifeFacts` | 다음 생성 입력 | 자동으로 빠짐 |
| `profile_topics.evidence` | JSONB `{"factId": ...}`. FK 없음 | 행은 둔다. 4-1 입력을 만들 때 없는 `factId` 항목을 뺀다 |
| `conversation_cards.evidence` | JSONB `{"factId": ...}`. FK 없음 | 행은 둔다. 4-1 `pastCards` 입력을 만들 때 없는 `factId` 항목을 뺀다 |
| `card_sets.generation_log.input` | 생성 당시 입력 전체. 지운 이야기의 제목과 내용이 들어 있음 | **그대로 남는다(D4)** |
| `life_fact_proposals` | 승인한 제안이면 출처 | 둔다. 7-3에서 `rejected`로 보이게 된다(D6) |

- 입력 정리가 필요한 이유: 4-1 결과 검증(`result_problems`)은 카드와 주제의 근거 `factId`가 `context.lifeFacts`에 있어야 통과한다. 지운 이야기를 가리키는 근거가 `topics[].evidence`에 남아 있으면 AI가 그 근거를 다시 쓸 수 있고, 그 결과는 `INVALID_GENERATION_RESULT`로 실패한다.
- 카드 생성 중(`card_sets.status = 'running'`)에 이야기를 지우면 이미 만든 입력에는 그 이야기가 들어 있다. 결과는 입력 기준으로 검증하므로 저장되며, 카드 근거가 지운 `factId`를 가리킬 수 있다. 임시 안에서는 막지 않는다.
- 지운 이야기만 근거로 한 카드와 주제를 지우는 방향(decmoon05 의견)을 택하면 결정할 것
  - 면회에 쓴 카드: 리포트의 카드 요약, 주제 제안(`topic_proposals`, 카드 삭제 시 CASCADE)과 묶여 있다. 지우면 지난 리포트가 바뀐다.
  - 아직 면회에 쓰지 않은 현재 묶음: 카드 묶음은 12장(`position` 1~12)이 전제라 한 장만 뺄 수 없다. 묶음을 다시 만들지, 그 카드만 숨길지 정해야 한다.
  - 여러 이야기를 근거로 한 카드: 남은 근거가 있으면 둘지, 근거 목록에서만 뺄지
  - 주제: 지운 이야기만 근거로 한 주제를 지울지, 제외(`exclude`)처럼 다룰지

## LifeFact

2-3의 `lifeFacts[]`, 2-6과 2-7의 응답이다.

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

- `storyCategory`, `imageNumber`가 새 필드다. 나머지는 [API 명세의 LifeFact](../../../docs/architecture/api-spec.md#lifefact)와 같다.
- 출처(일대기에서 담음 또는 면회 승인)는 지금처럼 응답에 담지 않는다.

## 출시 후 후보: 사진 연결

D8 결정 전이므로 구현하지 않는다. decmoon05 의견의 방향을 택할 때 필요한 것만 적는다.

- 새 업로드 API 대신 등록한 프로필 사진(3-1)을 골라 연결한다. `life_facts.photo_id`(nullable, `photos(photo_id)` 참조, 프로필 사진만, 사진 삭제 시 `SET NULL`)를 두고 2-6, 2-7에서 받는다.
- 프로필 사진은 프로필당 5장 제한이 있다. 이야기에서 새로 올리는 사진도 이 5장에 넣을지 정해야 한다.
- 실제 사용자 사진은 사진 보관 동의를 확인한 경우에만 받는다([ADR-001](../../../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)).

## 작업 순서

1. ~~Alembic migration으로 `story_category`, `image_number`를 더하고 `init.sql`을 맞춘다.~~ 완료([b7e2c4a9d153](../../alembic/versions/b7e2c4a9d153_life_fact_story_category_and_image.py))
2. ~~`LifeFact`, `create_life_fact`, `list_life_facts`와 응답 변환(`to_life_fact_response`)에 두 값을 더한다.~~ 완료. 7-4 테스트도 그대로 통과한다.
3. ~~2-6, 2-7의 요청 검증과 저장~~ 완료
4. ~~2-9 삭제~~ 완료. 행만 지우는 임시 안이다.
5. ~~4-1 입력에서 없는 `factId` 근거를 빼는 처리~~ 완료(`card_sets._without_deleted_facts`). 작업 B의 코드이므로 작업 B 담당의 확인이 필요하다.
6. ~~API 명세 2절과 LifeFact, 공통 데이터 계약, [backend/README.md](../../README.md#프로필과-생애-정보-api)를 고친다.~~ 완료. 필드 이름은 임시로 적었다.
7. 미정 사항 D1~D10이 결정되면 해당 절과 코드를 고친다. 특히 D1, D2가 다른 이름으로 정해지면 스키마의 alias와 DB 열 이름, 테스트를 함께 바꾼다.

## 테스트

모든 자료는 합성 값이다.

- 2-6: 일곱 분류와 `imageNumber` 1, 5가 저장되고 응답에 나온다. 분류가 없거나 모르는 값, `imageNumber` 0, 6, 실수, `null`은 422다.
- 2-7: 분류만, 그림 번호만 보낸 경우 나머지 열이 그대로다. 네 필드 모두 `null`은 422다. `createdAt`이 바뀌지 않는다.
- 2-9: 지우면 204이고 2-3의 `lifeFacts`에서 빠진다. 다시 지우면 404, 다른 계정의 이야기는 404다. 프로필의 다른 이야기는 남는다.
- 2-9 뒤 4-1: 지운 이야기가 `context.lifeFacts`에 없고, 그 이야기를 가리키던 주제와 지난 카드의 근거 항목이 입력에서 빠진다.
- 7-4로 만든 이야기는 `storyCategory = other`, `imageNumber`가 1~5다.
- migration: 기존 행이 `other`, 1로 채워지고 downgrade 뒤 다시 upgrade할 수 있다.

## FE 연결 메모

FE 작업이며 참고로 적는다.

- 앱의 `LifeFact` 모델(`app/lib/data/models.dart`)은 옛 형식(`category`, `text`, `sourceType`)이다. PR #125의 후속 작업으로 새 형식(`factId`, `title`, `content`, `createdAt`)에 이 문서의 `storyCategory`, `imageNumber`를 더해 바꾼다. 목 이야기 10편도 목 데이터 원본(`assets/mock/profile.json`)으로 옮긴다.
- 화면은 `LifeStory`만 보므로 `LifeFact` → `LifeStory` 변환 한 곳만 고친다. `storyCategory`는 `LifeStoryCategory.parse`로 읽고, 모르는 값이 오면 `other`로 보일지 오류로 볼지 FE가 정한다.
- 저장 뒤에는 2-3을 다시 읽거나 응답의 LifeFact로 목록을 고친다. `lifeStoryEditsProvider`의 앱 안 기억은 서버 연결 뒤 필요 없다.
