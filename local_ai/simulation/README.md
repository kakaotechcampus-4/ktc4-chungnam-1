# 시뮬레이션

카드 생성을 합성 데이터로 회차마다 이어서 돌려 본다. 명령은 모두 `local_ai/`에서 실행한다. 기록은 `simulation/runs/`에 남고 커밋하지 않는다.

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
- 결과는 `simulation/runs/persona-<판>-<페르소나>-<시드>-<시각>.json`과 `.events.jsonl`에 남는다. 회차마다 DB 스냅숏(카드 저장 직후, 변경 반영 직후)이 들어 있다.
- 페르소나·시드가 다르면 같은 DB에서 동시에 돌려도 서로 지우지 않는다.

## 규칙 기반 시뮬레이션

`rules/`에는 이전 카드 MVP에서 만든 합성 mock 4개가 있다. 정보가 하나도 없는 첫 면회(`first-visit-sparse`), 초기 정보가 있는 첫 면회(`first-visit`), 면회 2번 뒤(`third-visit`), 면회 20번 뒤(`large-20-visits`)다. 각각 그 시점의 DB 상태 하나다.

```bash
export TOPIC_REC_DATABASE_URL=postgresql://postgres:dev@127.0.0.1:55432/saerok_test
uv run python -m simulation.rules.run_scenario third-visit    # 또는 --all
uv run python -m simulation.rules.simulate --rounds 5            # 회차 이어 가기
```

`rules/run_scenario.py`는 시나리오를 넣고 1~2단계를 돌려서, DB에 있던 것과 후보, 판정 결과를 `simulation/runs/`에 적는다.

`rules/simulate.py`는 추천, 가상 보호자의 선택과 결정, 다음 회차 추천을 반복한다. 가상 보호자는 `rules/personas/`의 숨은 취향대로 움직인다. 좋아하는 낱말이 든 카드는 고르고 가끔 "더 자주", 싫어하는 건 "덜 자주", 막는 건 "추천하지 않기"를 고른다. 회차마다 새 이야기도 하나씩 생긴다. 시스템은 이 취향을 모르니, 보호자의 결정이 다음 회차에 제대로 반영되는지(막은 이야기가 다시 나오는지, 덜 자주 고른 주제가 얼마나 쉬다 돌아오는지)를 볼 수 있다. 질문 문장 단계가 없어서 카드의 질문은 자리표시 문장이다.
