# 카드 생성

다음 면회에 쓸 대화 카드 12장을 만든다. backend 카드 생성 worker가 DB에서 모은 context를 넘기면 `card_generation.generate_cards()`가 카드 12장과 새로 만들 주제를 돌려준다. 이 모듈은 DB를 읽지도 쓰지도 않는다. 에이전트 도구는 넘겨받은 context를 조회한다(`memory/store.py`).

```
__init__.py      backend가 import하는 이름: generate_cards, GenerationRequest, GenerationResult, CardGenerationError
generate.py      진입점 generate_cards와 단계 잇기(① → ② → 다시 찾기 → ③ → ④)
contract.py      backend와 주고받는 요청·결과·실패 형식
_steps/          generate.py만 부르는 내부 단계
  research/      ① 조사: agent(조사 에이전트), candidates(후보 형식과 제출 검증), tools(도구 6개와 결과 형식),
                 store(context 조회, 번호표, 선호 점수)
  match.py       ② 연결 판정
  select.py      ③ 12장 추첨
  write.py       ④ 문안
_versions/       판(promptVersion)마다 프롬프트와 정해 둔 값. v1/prompts에 에이전트, 연결 판정, 같은 이야기 기준, 문안
tests/           unit(PostgreSQL 단위 테스트), eval(실제 모델을 부르는 평가)
```

밑줄로 시작하는 폴더와 이름은 패키지 안에서만 쓰는 것(PEP 8). 밖에서는 `card_generation`이 내보내는 이름만 씀.

## 어떻게 돌아가나

1. 에이전트가 도구로 프로필, 쌓아온 이야기, 사진, 지난 주제를 살펴보고 카드 후보를 16~24개 낸다.
2. 후보마다 기존 주제 중 같은 이야기가 있는지 LLM으로 한 번에 판정한다. 같은 이야기가 있으면 그 주제에 연결하고, 기존 주제가 없는 후보끼리도 같은 이야기면 새 주제 하나로 묶는다. 판정에는 에이전트가 적은 연결을 보여 주지 않는다. 그 의견에 끌려가지 않게 하려는 것이다. 추천하지 않기 주제에 걸린 후보는 여기서 빠진다.
3. 코드가 선호 점수를 보고 12장을 고른다. 빠진 후보에는 왜 빠졌는지 남긴다.
4. 고른 12장에만 질문 문장을 쓴다.
5. 기억력을 시험하는 질문이나 의료 표현이 섞였는지 코드로 검사한다.
6. 새 주제는 제목, 설명, 근거를 결과에 담아 돌려준다. 저장은 backend가 한다.

주제(topic)와 카드(card)는 다르다. 주제는 "탄광에서 일하던 시절" 같은 이야기 하나이고, 보호자의 선호는 주제에 쌓인다. 카드는 이번 면회에서 그 이야기의 어느 장면을 어떤 질문으로 여쭐지를 담는다. 같은 주제로 면회마다 다른 카드가 나갈 수 있다.

"같은 이야기"가 무엇인지는 `_versions/v1/prompts/same_story.md` 한 곳에 적어 두고, 에이전트와 연결 판정이 같은 글을 쓴다. 주제를 얼마나 크게 잡을지는 이 글이 정한다. 예전에는 에이전트에게 "한 주제에 후보 하나"를 시켰더니, 같은 이야기의 두 번째 장면을 새 주제로 만들어 버려서 이야기 하나가 주제 여러 개로 쪼개졌다. 지금은 한 주제에 후보를 3개까지 내게 하고, 한 장만 고르는 건 선정 코드가 한다.

## 선호 점수

보호자가 면회 뒤에 주제마다 "더 자주(more)", "덜 자주(less)", "추천하지 않기(exclude)"를 고른다. 이걸 점수 하나로 바꾼다.

```
score = Σ (more면 +1, less면 -1) × 0.7^(그 결정 뒤로 지난 면회 수)
```

최근 결정일수록 크게 치고, 면회가 지날수록 옅어진다. 평균이 아니라 합으로 계산하는 이유는 more를 한 번 누른 주제와 다섯 번 누른 주제를 구분하기 위해서다. 날짜 대신 면회 횟수로 줄이는 건 보호자마다 면회 간격이 달라서다.

보호자가 "추천하지 않기(exclude)"를 고른 주제는 점수와 상관없이 후보에서 빠진다. 나머지 주제는 묶음으로 나누지 않고 점수 그대로 쓴다. 선정에서 점수를 확률로 바꿔 뽑으니 점수가 낮은 주제도 뽑힐 수 있다(아래 "선정"). less를 한 번 누른 주제의 점수는 면회마다 -1 → -0.7 → -0.49로 0에 가까워진다.

0.7은 일단 정해 본 값이다. mock 데이터로 돌려 보고 PM과 정해야 한다. `_versions/v1/__init__.py`에서 바꿀 수 있다.

카드에 남긴 반응(좋았어요, 아쉬웠어요 등)은 점수에 넣지 않는다. 그날 질문이 어색했거나 컨디션이 안 좋았을 수도 있어서, 주제 자체에 대한 평가로 보기 어렵다. 대신 `get_topic`으로 지난 카드와 반응을 보여 줘서 에이전트가 다른 장면을 고르는 데 쓰게 한다.

## 도구

| 도구 | 하는 일 |
| --- | --- |
| `get_profile()` | 연령대, 초기 정보 네 칸(하시던 일, 고향, 취미, 가족)과 각 데이터 개수 |
| `list_life_facts(order, offset, limit)` | 쌓아온 이야기를 페이지 단위로. 덜 다룬 순, 최신 순, 오래된 순 |
| `get_life_facts(fact_ids)` | 번호표로 이야기 원문 보기 |
| `list_photos(offset, limit)` | 사진 설명 |
| `list_topics(offset, limit)` | 지난 주제와 점수, 추천하지 않기 여부 |
| `get_topic(topic_id)` | 주제 하나의 결정 이력, 근거, 지난 카드 |

시점은 날짜 대신 "면회 몇 번 전"(`visits_ago`, 0이 가장 최근)으로 준다. 이야기나 사진이 카드에 몇 번 쓰였는지도 같이 주는데, 실제 면회에 쓰인 카드 묶음만 센다.

사진 설명은 AI가 쓰고 보호자가 앨범에서 확인하거나 고친다고 해서 사실로 다룬다. 다만 DB에는 보호자가 확인했는지 표시하는 칸이 없다. 앨범을 한 번도 안 열었으면 AI가 쓴 설명이 그대로 쓰인다.

### 에이전트가 볼 수 없는 것

도구는 backend가 넘긴 context만 읽는다. context에는 이 프로필의 정보만 있고, 이름, 성별, 생년월일, 증상 메모, 인지 단계, 면회 평가 메모, 리포트 본문, 보호자가 아직 승인하지 않은 제안은 backend가 애초에 넣지 않는다. 나이는 "80s" 같은 연령대로만 온다. 보호자가 승인한 내용은 `life_facts`나 `topic_feedback`으로 들어와 context에 실린다.

## 에이전트가 내는 후보

`CardCandidate` 하나가 카드 한 장의 후보다. 아직 질문 문장은 없고, 어떤 이야기의 어느 장면을 무엇을 근거로 다룰지만 담는다.

- 기존 주제에 연결하면 `linked_topic_id`, 새 주제면 `new_topic_title`과 `new_topic_description`
- `card_title`: 카드 제목
- `angle`: 이번에 다룰 장면이나 사람, 물건
- `kind`: 근거가 무엇인지. personal(이야기·초기 정보), photo(사진), discover(비어 있는 초기 정보 칸을 여쭤 보기), general(연령대에 맞는 옛 추억)
- `evidence`, `discover_field`, `reason`

LangChain `create_agent`의 `response_format`으로 이 형식을 강제한다. 제출 모델에는 Pydantic 검증기를 붙여 두었다.

- 후보 16~24개, 서로 다른 주제 14개 이상, 한 주제에 3개 이하
- 근거 원소마다 값은 하나, 종류와 근거가 맞는지, 한 후보의 근거는 한 종류로만(backend가 그렇게만 받는다)
- 카드 제목과 새 주제 제목은 100자 이하
- 기존 주제·이야기·사진 ID가 이 프로필에 실제로 있는지. 프로필마다 다르므로 실행할 때 모델을 새로 만든다.

검증에 실패하면 `ToolStrategy(handle_errors=True)`가 오류 문장을 모델에 돌려주고 다시 내게 한다. 개수 제한을 JSON Schema(`minItems` 등)로 걸지 않은 건 모델 API마다 받는 키워드가 달라서다.

주제를 14개 이상 받는 이유는 카드 묶음에 주제마다 한 장만 들어가기 때문이다(`UNIQUE(set_id, topic_id)`). 12장에 판정에서 빠질 몫을 더했다.

## 선정

연결 판정을 거친 후보에서 코드가 12장을 고른다(`card_generation/_steps/select.py`). 같은 주제 후보가 여럿이면 에이전트가 먼저 낸 것을 쓰고, 이 순서로 채운다.

- 새 이야기: 먼저 5장을 에이전트가 낸 순서로 잡아 둔다
- 기존 주제: 남은 자리를 추천하지 않기가 아닌 기존 주제에서 뽑는다. 점수를 `softmax(score / temperature)`로 확률로 바꿔 한 장씩 비복원 추출한다. 점수가 높을수록 잘 뽑히지만, 낮아도 기회가 있다
- 남은 자리: 기존 주제가 모자라면 남은 새 이야기로 채운다

점수 순으로 잘라 고르면 같은 context에서 늘 같은 카드가 나오고, 몇 등 밖의 주제는 계속 안 나온다. 그래서 확률로 뽑는다. temperature 1.0이면 점수가 1 높은 주제가 약 2.7배 잘 뽑힌다. 낮추면 점수 높은 주제로 쏠리고 높이면 고르게 뽑힌다. 추첨 seed는 결과 `log.selectionSeed`에 남아서 같은 추첨을 다시 볼 수 있다.

카드 위치는 기존 주제와 새 이야기를 번갈아 놓는다. 1~9번이 고르는 카드, 10~12번이 보충용이라 어느 한쪽이 보충 칸에 몰리지 않게 하려는 것이다.

확률은 에이전트가 후보로 낸 기존 주제 안에서만 작동한다. 그래서 에이전트에게 기존 주제를 미리 거르지 말고 넉넉히 내라고 한다.

장수와 temperature는 일단 정해 본 값이고 `_versions/v1/__init__.py`에서 바꾼다. 12장을 못 채우면 일부만 내지 않고 실패로 돌려준다.

## 테스트

```bash
cd local_ai
uv sync

docker run -d --name topic-rec-pg -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=saerok_test \
  -p 127.0.0.1:55432:5432 postgres:16
docker exec topic-rec-pg createdb -U postgres saerok_unit
TOPIC_REC_TEST_DATABASE_URL=postgresql://postgres:dev@127.0.0.1:55432/saerok_unit uv run pytest
```

테스트는 `backend/database/init.sql`(PR #84 스키마)을 적용하고 `card_generation/tests/unit/seed.py`의 합성 데이터를 넣는다. `init.sql`은 테이블을 전부 지우고 다시 만들기 때문에 테스트용 DB에서만 돌린다. 시뮬레이션(`saerok_test`)과 같은 DB를 쓰면 돌고 있는 시뮬레이션의 데이터가 지워지므로 테스트는 `saerok_unit`을 따로 쓴다. `TOPIC_REC_TEST_DATABASE_URL`이 없으면 DB 테스트는 건너뛴다.

## 평가

`tests/eval/` 아래 평가 두 개는 실제 모델을 부르고, 결과를 `card_generation/tests/eval/runs/`에 남긴다. 정답은 모두 AI가 만든 합성 자료라 사람이 검수해야 한다.

```bash
uv run python -m card_generation.tests.eval.same_story_eval --label now        # 추천하지 않기 판정(후보 77개)
uv run python -m card_generation.tests.eval.granularity_eval --label now       # 주제 크기(묶음과 쪼갬)
```

`--same-story`, `--match`로 다른 판의 프롬프트를 넣어 비교할 수 있다.

## 아직 못 정한 것

- 점수 감쇠(0.7), 새 이야기 최소 장수(5장), 추첨 temperature(1.0)
- 추천하지 않기의 범위. 그 장면만 막을지, 같은 물건이나 사람이 나오는 이야기까지 막을지
- 보편 주제와 빈 칸 묻기 주제를 어떤 크기로 묶을지
- 주제 구조를 그대로 둘지, 요소 구조로 바꿀지. 바꾸면 DB와 면회 뒤 화면이 함께 바뀐다
- 초기 정보 칸만 근거로 한 카드의 `evidence_source`. #99 migration이 `profile`을 추가했지만 develop의 `init.sql`에는 아직 없어서, 시뮬레이션은 이런 근거를 `none`으로 저장한다.
- 이야기가 수백 개로 늘었을 때 찾는 방법. 지금은 목록을 덜 다룬 순으로 넘겨 본다.
- 웹 검색. 엘리스 ML API는 OpenAI 내장 웹 검색을 막아 두어서, 쓰려면 검색 API를 따로 붙여야 한다. 일단 보류했다.
- 이야기 원문을 엘리스로 보내도 되는 조건. 실제 사용자 데이터로 돌리기 전에 정해야 한다.
