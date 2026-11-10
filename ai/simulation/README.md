# 시뮬레이션

카드 생성을 합성 데이터로 회차마다 이어서 돌려 본다. 명령은 모두 `ai/`에서 실행한다. 기록은 `simulation/runs/`에 남고 커밋하지 않는다.

모델 설정은 환경 변수에서 읽는다(`llm_env.py`). `ML_API_KEY`는 꼭 있어야 한다. 모델 주소는 `common/llm.py`의 `ENDPOINTS`에서 찾는다.

## 페르소나 시뮬레이션

합성 어르신·보호자 페르소나로 앱 흐름(프로필 입력 → 카드 받기 → 고르기 → 면회 대화 → 소감 → 리포트·변경 제안 → 보호자 확인 → 반영)을 회차마다 이어서 돌린다. 어르신과 보호자는 각자 LLM 에이전트이고 한 턴씩 주고받는다. 카드와 결정은 PR #84 테이블에 쓴다. 면회 리포트와 변경 제안은 `report_generation`, `proposal_generation`을 #106 내부 API(8-3) 형식으로 부른다. 화자 라벨은 `SPEAKER_00` 형식이다.

```bash
export TOPIC_REC_DATABASE_URL=postgresql://postgres:dev@127.0.0.1:55432/saerok_test
uv run python -m simulation.web       # 작업대 http://127.0.0.1:8780 (페르소나·프롬프트 편집, 실시간 진행, DB 보기, 기록)
uv run python -m simulation.run --persona simulation/personas/milyang-engineer.json --visits 5 --seed 11
```

- 페르소나는 `simulation/personas/`에 있다. 어르신의 숨은 생애사, 앨범의 실제 내용, 보호자의 속마음은 시뮬레이션 역할만 보고 추천 시스템은 보지 못한다.
- `*-probe.json`은 시험판이다. `caregiver.visit_intents`로 정한 회차의 10턴째에 보호자가 그 이야기를 꺼내게 해서, 싫다는 반응이 나왔을 때 시스템이 어떻게 처리하는지 본다. 자연 발생률을 볼 때는 쓰지 않는다.
- 실행이 끝나면 평가자가 주제를 숨은 생애와 대조해 크기를 잰다(`simulation/topic_size.py`). 시스템에는 영향이 없다.
- 결과는 `simulation/runs/persona-<추천 버전>-v<카드 생성 버전>-<페르소나>-<시드>-<시각>.json`과 `.events.jsonl`에 남는다. 회차마다 DB 스냅숏(카드 저장 직후, 변경 반영 직후)이 들어 있다.
- 페르소나·시드가 다르면 같은 DB에서 동시에 돌려도 서로 지우지 않는다.
- DB는 `backend/database/init.sql`로 만든다. 테이블을 모두 지우고 다시 만드니 시뮬레이션 전용 DB(`saerok_test`)에만 쓴다. 스키마가 바뀌면 다시 적용한다.
  `docker exec -i topic-rec-pg psql -U postgres -d saerok_test -v ON_ERROR_STOP=1 -q < ../backend/database/init.sql`

### 카드 생성 버전 고르기

작업대의 "프롬프트 버전"(CLI `--prompt-version`)으로 카드 생성 버전(`card_generation/_versions`)을 고른다. 정하지 않으면 최신 버전이다. 운영 backend 기본 버전(`SAEROK_CARD_GENERATION_PROMPT_VERSION`, 기본 2)과 다를 수 있다. 결과 파일 이름에 `-v<버전>`이 붙고, 버전이 다른 실행은 같은 페르소나·시드여도 DB에서 서로 지우지 않는다. 프롬프트 탭에는 버전마다 카드 생성 프롬프트가 `[v3]`처럼 따로 보인다.

### 초기 정보 없이 시작

`--blank-profile`(작업대의 "초기 정보 없이 시작", 페르소나의 `"onboarding": {"blank": true}`)을 켜면 보호자가 기본 정보만 넣고 생애 질문 네 칸(하시던 일, 고향, 취미, 가족)과 사진을 모두 건너뛴다. 결과 파일 이름에 `-blank`가 붙고, 같은 페르소나·시드의 보통 실행과 서로 지우지 않는다.

### 카드 생성 단계 기록

회차마다 카드 생성의 단계별 입력과 출력이 결과 JSON의 `visits[].recommend.steps`에 남는다. 단계만 따로 보는 화면은 `simulation/steps_view.py`다. 작업대 기록 목록의 "카드 생성 단계" 링크(`/runs/<기록 이름>/steps`)로 열거나 `uv run python -m simulation.steps_view <결과.json>`으로 `.steps.html`을 만든다. 회차마다 context → ① → ② → ③ → ④ → 면회 뒤를 입력(왼쪽)과 출력(오른쪽)으로 나눠 보여 주고, 회차가 둘 이상이면 "회차 비교" 탭이 생긴다. 기록 화면(`simulation.viewer`)의 회차 탭에도 같은 내용의 간단한 패널이 있다. `simulation/backends/steps.py`가 `card_generation.generate`가 부르는 함수를 같은 동작의 감싼 함수로 바꿔 끼워 모은다. `card_generation` 코드와 운영 `generation_log`는 바뀌지 않는다.

| 단계 | 입력 | 출력 |
| --- | --- | --- |
| context | backend 역할(`backends/context.py`)이 DB에서 조립한 것 | |
| ① 조사 | 에이전트 요청, 도구 호출과 도구 결과 원문 | 거부된 제출, 낸 순서대로의 후보 |
| ② 연결 판정 | 판정 LLM에 보낸 기존 주제와 후보 | 판정 LLM 출력, 남은 후보, 빠진 후보 |
| ③ 선정 | 기존 주제 점수와 추천하지 않기, 선정 규칙 | 고른 12장과 탈락한 후보 |
| ④ 문안 | 카드 12장의 제목, angle, 근거 글, 주제 | 설명, 첫 질문, 꼬리 질문, 첫 검사에서 걸린 것 |

다시 찾기가 있으면 ①②는 회차마다 여러 번 남는다. 도구 결과와 판정 입력은 모델이 보는 번호표(t1, f3, p2)를, 후보와 선정 결과는 UUID를 쓴다. 추천이 실패하면 그때까지의 기록이 `failed_recommend`에 남는다.

`backends/context.py`는 backend `app/services/card_sets.py`의 `build_context`를 동기 방식으로 옮긴 것이다. 보호자 사진 설명 우선(#205), 추천하지 않기 주제의 근거 이야기와 사진 제외, 근거가 모두 사라진 주제 제외(#291)까지 같다. backend 규칙이 바뀌면 같이 고친다.
