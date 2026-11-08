# BE 영역

담당 리더: 김민혁. Python 3.12와 FastAPI의 상태 확인, 공통 오류 및 요청 로그, 구글 인증 API와 PostgreSQL 개발 스키마가 있으며 계정, 프로필과 생애 정보는 PostgreSQL에 저장한다. STT는 연결돼 있다. speech-worker가 [AiServerClient](app/clients/ai_server.py)로 `stt-server`를 HTTP로 부르고, 결과 전사로 같은 작업에서 리포트를 만든다([비동기 면회 음성 STT](docs/async-speech-analysis.md)). 세부 정보의 짧은 음성 전사 API(6-6, #214)도 같은 서버를 부른다([short-speech-transcription](docs/short-speech-transcription.md)). 프로필 사진 설명은 photo-worker가 ML API로 만든다(#257, [사진 분석](docs/photo-analysis.md)). 계정별 AI 사진 분석 동의(`photoAnalysis`, `consent_records.photo_analysis`)가 켜진 계정의 사진만 분석하며, photo-worker는 11/8부터 운영 서버에서 돈다. 사진 보관 동의는 따로 없다.

STT는 Tailscale 사설망으로 연결하는 개인 GPU 서버, 사진 설명과 카드 및 리포트 생성은 ML API를 활용하는 방향이다. 10월 6일 BE 논의와 [ADR-006의 후속 정정](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md#현재-적용할-방향-2026-10-11-정정)을 따른다. 생성 함수와 HTTP의 구체적인 연결은 각 담당 PR에서 맞춘다. 현재 개인 GPU의 처리 성능은 해당 환경에서 검증한 결과로 별도 기록한다.

[ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)은 계정 저장 항목 등의 공동 검토를 위해 `proposed`로 유지한다.

## 개발과 개인정보 검토 순서

2026-10-14 PM 결정에 따라 합성 데이터로 기능 구현과 연동 테스트를 먼저 진행한다. 동의 문구나 법률 검토가 남았다는 이유로 사진 업로드, 분석 worker 등 기능 전체를 보류하지 않는다. 미정 정책에 필요한 테스트 가정은 표시하고, 실제 사용자 자료를 사용하기 전에는 [동의와 처리 조건](../docs/legal/README.md#개발-우선과-실제-사용자-자료-사용-전-확인) 및 관련 구현을 검증한다. 기존 인증, 접근 권한과 삭제 처리를 해제하는 결정은 아니다.

## 실행과 테스트

저장소 루트에서 최초 설정:

```powershell
cd backend
uv python install 3.12
uv sync
uv run python --version
```

이후 명령은 `backend/`에서 실행한다. 의존성과 가상 환경은 `uv`, 테스트는 `pytest`로 관리한다. `uv sync`는 카드 생성 패키지(`../ai`)도 경로 의존성으로 함께 설치한다.

실행 스크립트로 서버를 활성화한다.

```bash
./scripts/run_backend.sh
```

기본값은 백엔드 `127.0.0.1:8000`, AI 서버 `127.0.0.1:8001`이다. 필요한 경우 실행할 때만
환경 변수를 덮어쓴다.

```bash
SAEROK_AI_SERVER_URL=http://192.0.2.10:8001 \
SAEROK_BACKEND_PORT=8080 \
./scripts/run_backend.sh
```

Android 에뮬레이터 또는 허가된 개발 단말과 합성 데이터로 연동할 때만 외부 인터페이스에 바인딩한다.

```bash
SAEROK_BACKEND_HOST=0.0.0.0 ./scripts/run_backend.sh
```

```powershell
uv run pytest
```

컨테이너 실행과 EC2 개발 서버 배포 절차는 [컨테이너 실행과 개발 서버 배포](docs/deployment.md)에 둔다. 이 EC2 서버는 develop에 병합된 코드와 합성 데이터만 쓰는 개발 서버로 만들었고 지금은 운영 서버로 쓴다. 갱신은 [승인 배포 workflow](../docs/deploy-workflows.md)로만 하고 배포 문서의 손 갱신 절차는 쓰지 않는다. 다만 workflow는 caddy를 교체하지 않으므로, [Caddyfile](Caddyfile)이 바뀐 배포는 Deploy 뒤 caddy만 따로 다시 만든다([배포 문서의 갱신](docs/deployment.md#갱신)). HTTPS는 sslip.io와 Caddy로 임시 구성하며, BE 공개 범위는 별도 검토하며, STT는 개인 GPU 서버의 Tailscale IP로 연결하고 연결에 실패하면 예비 STT로 한 번 전환한다([STT 예비 서버 전환](#stt-예비-서버-전환)). 11/8 Deploy run 42485750502로 develop `9c2b8276`을 배포했고 api, card-worker, speech-worker, photo-worker를 교체했다. 이 workflow는 STT 서버를 배포하지 않는다. 현재 구현 (2026-11-09 기준): 그 뒤 11/9 develop(`d9643466`)에 병합한 BE 수정 #275, #277, #278, #279, #280은 아직 운영에 배포하지 않았다. 이 README에서 사진 분석 완료와 카드 묶음(#275), 7-4의 카드 생성 잠금과 갱신 표시(#277), [요청 본문 크기 상한](#요청-본문-크기-상한)(#278), 전사 기한과 외부 전송(#279), 전사 저장 뒤 인계 임대와 이어받기(#280)의 설명은 develop 코드 기준이며 운영 서버는 이전 동작이다. 처음 배포할 때 손으로 할 일은 [배포 workflow의 실제 실행 기록](../docs/deploy-workflows.md#실제-실행-기록-2026-11-09-기준)에 있다.

| 확인 항목 | 위치 / 현재 범위 |
| --- | --- |
| 생존 확인 | `GET /health/live` |
| 준비 상태 | `GET /health/ready`. 3초 안에 DB 연결과 `SELECT 1` 확인. DB 설정 누락이나 연결 실패는 503 |
| API 문서 | 실행 후 `http://127.0.0.1:8000/docs` |
| API 명세 대조 | [test_api_spec_routes.py](tests/test_api_spec_routes.py)가 서버의 실제 경로와 `docs/architecture/api-spec.md`의 `METHOD /경로` 제목이 서로 빠짐없는지 확인. 상태 확인과 AI 서버의 `/internal` 경로는 제외. 필드와 설명은 비교하지 않음 |
| 오류 테스트 | [test_errors.py](tests/test_errors.py)의 404, 422, 500, 503 응답 |
| 본문 크기 상한 | 경로별 본문 상한과 업로드 경로의 본문 읽기 전 세션 확인. [요청 본문 크기 상한](#요청-본문-크기-상한), [test_request_body_limit.py](tests/test_request_body_limit.py) |
| 요청 로그 | 요청 ID로 응답과 로그를 연결. 경로 템플릿과 안전한 예외 종류 및 스택을 기록하며 요청 본문과 전사문은 제외 |

## 데이터베이스 마이그레이션 (Alembic)

PostgreSQL 스키마의 소유권은 Alembic migration에 있다. `backend/database/init.sql`은
빈 개발 DB를 한 번에 세우는 bootstrap 스크립트일 뿐이며, 스키마가 바뀌면 Alembic
migration을 먼저 바꾸고 `init.sql`을 그에 맞춘다(자세한 로컬 적용 방법은
`backend/database/로컬설정법.md` 참고).

초기 migration 교체는 공용 DB와 실제 데이터가 없는 초기 개발 단계에만 허용한다.
공용 DB를 사용하기 시작했거나 실제 데이터가 쌓인 뒤에는 이미 적용된 migration을
수정하거나 교체하지 않는다. 이후 스키마 변경은 새 migration으로 추가하고 기존
데이터를 유지한 채 적용한다. 변경을 맞추기 위해 공용 DB를 삭제하고 재생성하지 않는다.

`SAEROK_DATABASE_URL`(`.env`)에 연결 문자열을 설정한 뒤 다음으로 최신 스키마를 적용한다.

```powershell
uv run alembic upgrade head
```

새 migration을 추가할 때는 `uv run alembic revision -m "설명"`으로 뼈대를 만든 뒤
`upgrade`/`downgrade`를 직접 작성한다. `alembic revision --autogenerate`의 결과는
CHECK constraint, JSONB, partial index, FK `ON DELETE` 동작을 빠뜨릴 수 있으므로
그대로 신뢰하지 않고 반드시 검토한다.

`init.sql`과 migration이 어긋나지 않는지는 [test_migration_consistency.py](tests/test_migration_consistency.py)가
검사한다. 임시 DB 두 개에 각각 migration과 `init.sql`을 적용하고 카탈로그에서 열, 제약의 이름과
정의, 인덱스, 뷰, 함수, trigger와 확장을 읽어 비교한다. 열 순서는 비교하지 않는다. 같은 파일에서
`alembic/env.py`가 호출하는 쪽이 넘긴 주소를 유지하고, `alembic.ini`의 기본 예시 주소일 때만
`SAEROK_DATABASE_URL`을 쓰는지도 각각 검사한다. 다른 DB 테스트처럼 `SAEROK_TEST_DATABASE_URL`이
없으면 건너뛰며 공용 DB나 작업용 DB에는 연결하지 않는다.

PR #32의 500 응답 헤더와 완료 로그 보완이 develop에 반영됐다. 계정과 세션 폐기 기록은 PostgreSQL에 저장한다. DB revision, 작업 상태와 기본 STT 연결은 [읽기 전용 운영 점검](docs/runtime-check.md)으로 별도 확인한다. readiness 성공만으로 GPU와 모델 처리가 정상임을 보장하지 않는다.

## DB 연결과 저장소 작성 규칙

API를 나눠 구현할 때 모두 같은 방식으로 DB를 쓴다.

| 항목 | 규칙 |
| --- | --- |
| 쿼리 | psycopg로 SQL을 직접 쓴다. SQLAlchemy는 Alembic에만 쓴다 |
| 연결 | 비동기 연결(`psycopg.AsyncConnection`)만 쓴다. 저장소는 연결을 직접 열지 않고, [deps.py](app/api/deps.py)의 `DbConnectionDep`이 요청마다 여는 연결을 받는다. 연결은 autocommit이다 |
| 트랜잭션 | 여러 문장을 함께 반영해야 하면 서비스나 저장소 코드에서 `async with connection.transaction():`으로 묶는다. 의존성의 정리 단계에서 커밋하지 않는다. worker는 상태가 바뀔 때마다 짧게 커밋하고 AI 서버 호출 중에는 트랜잭션을 열어 두지 않는다 |
| 소유 확인 | 경로의 ID는 `UUID`로 받고 [ownership.py](app/services/ownership.py)의 `require_owned`로 확인한다. 다른 계정의 자원과 없는 자원은 같은 404를 받는다 |
| 테스트 | 저장소 SQL은 `SAEROK_TEST_DATABASE_URL`을 설정하고 임시 DB fixture(`migrated_database_url`, [conftest.py](tests/conftest.py))로 확인한다. 값이 없으면 건너뛴다. 비동기 코드는 [support.py](tests/support.py)의 `run`으로 실행한다 |

`SAEROK_DATABASE_URL`이 없으면 DB를 쓰는 API는 메모리 저장소 같은 대체 경로 없이 `DATABASE_NOT_CONFIGURED`(503)로 거절한다.

psycopg 비동기 연결은 Windows 기본 이벤트 루프(ProactorEventLoop)에서 동작하지 않는다. `scripts/run_backend.sh`는 `--reload`로 실행해 SelectorEventLoop를 쓴다. Windows에서 `--reload` 없이 직접 실행하면 `--loop asyncio:SelectorEventLoop`를 붙인다. worker는 실행 진입점이 SelectorEventLoop로 실행한다.

## worker 공통 골격

비동기 파이프라인(음성 → 리포트, 카드 생성, 사진 분석)의 worker는 [base.py](app/workers/base.py)의 `Worker`로 만든다. 파이프라인마다 대기열과 처리 함수만 준비한다.

| 구성 | 하는 일 | 준비된 것 |
| --- | --- | --- |
| 대기열 (`JobQueue`) | 임대 만료 정리, 작업 하나 임대(`claim`), 실패 기록(`fail`). 각 메서드는 짧은 트랜잭션 하나 | 음성 `SpeechAnalysisQueue`, 카드 생성 [CardGenerationQueue](app/services/card_generation_jobs.py), 사진 분석 [PhotoAnalysisQueue](app/services/photo_analysis_jobs.py) |
| 처리 함수 (`JobProcessor`) | `async def process(connection, job)`. AI 서버 호출과 응답 검증은 트랜잭션 밖에서 하고 결과 저장만 트랜잭션으로 묶는다 | 음성 `SpeechAnalysisProcessor`, 카드 생성 [CardGenerationProcessor](app/services/card_sets.py), 사진 분석 [PhotoAnalysisProcessor](app/services/photo_analysis_pipeline.py) |

- `Worker`는 한 번 돌 때 임대 만료 정리 → 작업 하나 임대 → 처리 순서로 실행한다. 처리 함수가 `AppError`를 내면 그 `error_code`로, 그 밖의 예외는 대기열의 기본 실패 코드로 작업을 실패시킨다. 예외 메시지는 로그에 남기지 않고 종류만 남긴다.
- 임대 시간 안에 끝나지 않은 작업은 다음 정리에서 `WORKER_LEASE_EXPIRED`로 실패한다. 음성의 업로드 단계에서 멈춘 작업은 접수 전 실패와 같으므로 지워서 다시 제출할 수 있게 한다. 음성 작업이 전사 저장 뒤 리포트 시작 전에 멈추면 실패시키지 않고 인계 임대가 끝난 뒤 리포트 생성을 이어받는다([AI 음성 분석 연동](#ai-음성-분석-연동)). 실패한 작업의 자동 재시도는 하지 않는다.
- 종료 신호(SIGTERM, SIGINT)를 받으면 새 작업을 가져오지 않고, 처리 중인 작업을 마친 뒤 끝난다. 대기 중이면 바로 끝나고, 같은 신호를 한 번 더 받으면 기다리지 않고 끝난다. Windows의 SelectorEventLoop는 `loop.add_signal_handler`를 지원하지 않아 `signal.signal`로 받는다. compose의 유예 시간과 근거는 [배포 문서](docs/deployment.md#worker-종료와-유예-시간)에 있다.
- 결과를 저장해 작업을 끝낼 때는 임대도 함께 지운다. `card_sets`는 `completed`로 바꿀 때 `lease_expires_at = NULL`이어야 하고(CHECK `card_sets_lease_check`), `photos`는 `processing`일 때만 임대가 있다(CHECK `photos_lease_check`).
- 카드 생성 처리 함수가 AI에 보낸 요청을 남기며 실패시키려면 `CardGenerationQueue.fail(..., generation_input=...)`을 직접 부르고 정상 반환한다.
- **`PhotoAnalysisQueue`는 계정의 현재 동의(`current_consents.photo_analysis`)가 켜진 프로필 사진만 가져온다(#257).** 동의하지 않은 계정의 사진은 `pending`으로 남고 나중에 동의하면 그때 분석한다. 처리 함수는 저장 직전에 동의를 다시 확인하고, 분석 중에 동의를 거뒀으면 결과를 버리고 `pending`으로 되돌린다. 이미 저장된 AI 설명을 철회 때 지울지와 사진 보관 동의는 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)의 남은 항목이다. 처음 기준은 합성 사진만 있는 개발 환경에서 먼저 구현하고, 실제 사용자 사진을 처리하기 전에 ADR-001의 계정별 분석 동의 조건, 분석하지 않는 사진의 상태와 철회 시 작업 중단을 구현하고 검증하며, 테스트 통과만으로 실제 사용자 사진 처리를 개방하지 않는 것이었다. 이 세 조건은 #257로 구현했다. 11/8 운영 시험은 공개 라이선스 사진으로만 했고 실제 사용자 사진은 확인하지 않았다.
- 새 worker의 실행 진입점은 [speech_analysis.py](app/workers/speech_analysis.py)처럼 `run_worker_main`으로 만든다. `--once`면 대기 작업을 최대 하나 처리하고 끝낸다.

## 담당과 다음 결정

| 범위 | BE 작업 / 함께 정할 내용 |
| --- | --- |
| 모델 실행 | AI와 입력 형식, 모델 로딩, 자원 해제, STT 및 화자 처리 파이프라인 검토 |
| 앱 연동 | [공통 데이터 계약](../docs/architecture/data-contracts.md)의 입력 검증, 응답과 상태 전달 |
| 작업 처리 | 타임아웃, 재시도 상한, 취소, 장애 복구와 수동 전환 |
| 데이터 저장 | 서버 저장 항목, 단말 보관 여부, 접근 권한, 보관 기간과 삭제 조건을 제안. PostgreSQL 스키마와 Alembic이 반영됐고 앱은 API로 서버에 저장한다. 앱과 실제 BE의 연결은 PR마다 E2E로 검사한다(#258) |
| 운영 | 현재 개인 GPU에서 STT 처리 시간·메모리와 동시 처리 조건 측정. PM과 운영 방식 확인. 모델 파일 배포와 무결성 확인 |
| 데이터 이동 | 업로드 허용 필드, 인증, 마스킹, 임시 파일과 로그의 삭제 확인 |
| 외부 서비스 | 외부 LLM 중계 필요 여부와 개인정보 처리 조건 확인 |

모델과 품질 기준은 AI와 공동 검토한다. 새 구조 결정은 입력과 출력, 저장 여부, 실패 조건, 보안 영향, 검증 방법과 재검토 조건을 ADR에 기록한다.

## 데이터 처리 기준

    앱에서 녹음 및 기능 동의 확인
    → 암호화 전송과 서버 임시 처리
    → STT 또는 VLM 결과 반환
    → 녹음 원본과 분석용 임시 사진 삭제 및 삭제 결과 확인
    → 보호자 검토
    → 승인된 사실 반영, 서버 중심 관리

이 흐름은 구현해야 할 목표다. BE가 데이터별 저장 위치, 단말 보관 여부, 기간과 접근 및 삭제 조건을 PR로 정리하고 FE, AI와 PM이 함께 확인한다. 현재 DB는 EC2의 Compose(`db` 서비스)에 두고 STT는 별도 GPU 서버(개인 GPU, ck 예비)에서 실행한다. 녹음 원본은 STT 완료 후 즉시 삭제하며 업로드 후 최대 24시간 제한을 유지한다. 등록 사진과 AI 분석용 임시 사본은 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)에서 구분한다. PR #92는 병합됐고 사진 보관과 AI 분석을 가입 시 선택 동의로 받아 계정별로 저장하는 방향은 2026-10-14 PM이 확정했다. 이 중 AI 분석 동의는 #257로 연결됐다. 사진 보관 동의, 삭제 대기열의 실제 삭제 실행과 실제 사용자 자료 처리 검증은 남아 있다. 실제 사용자 자료와 마스킹한 실제 자료는 개발 골격의 테스트에 사용하지 않는다.

직접 식별정보와 허용 목록 밖의 원본은 외부 AI로 보내지 않는다. 데이터 경로 변경 전 [법률 문서](../docs/legal/README.md), [동의 및 임시 처리 ADR](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md)과 데이터 흐름을 갱신한다. 외부 업체의 이름, 국가, 목적, 항목, 보유기간과 자체 학습 여부가 정해지기 전에는 실제 사용자 자료로 호출하지 않는다.

## 로그인 API

로그인 API는 PR #47로 develop에 반영됐다. 근거는 [ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)이다. 구글 ID 토큰 직접 검증 방향에 대한 PM 동의와 개인정보 저장 항목의 검토안은 구분한다. ADR-007은 `proposed`로 유지하며, API 구현이 저장 범위 전체의 확정을 뜻하지 않는다. 응답의 `authProvider`와 nullable `email`은 [공통 Account 계약](../docs/architecture/data-contracts.md#계정-account)에 맞춘다.

인증은 구글 소셜 로그인 한 가지를 사용하고 자체 아이디와 비밀번호는 받지 않는다. 백엔드는 구글 공개키로 ID 토큰을 직접 검증하며 Firebase Auth를 사용하지 않는다.

### 흐름

다음은 현재 흐름이다. 서버 엔드포인트는 아래 표에 있다. 앱은 세션을 기기 보안 저장소에 두고 다시 켤 때 `GET /auth/me`로 확인해 복원한다([PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)). 보관한 세션이 만료됐거나 서버가 거절하면 구글 무음 로그인으로 새 ID 토큰을 받아 `POST /auth/google`을 다시 부른다(PR #50). 쓰는 중에 세션이 만료돼도 같은 방식으로 다시 받는다(#175).

    앱 시작
    → (세션 있음) GET /auth/me → 홈
    → (세션 없음) 구글 로그인 버튼 → POST /auth/google
        → status=authenticated  → 홈
        → status=consentRequired → 동의 화면 → POST /auth/consent → 홈

    설정의 계정 약관 동의에서 선택 동의 변경 → PATCH /auth/me/consents
    설정의 로그아웃 → POST /auth/logout → 로그인 화면
    회원 탈퇴 확인의 탈퇴하기 → DELETE /auth/me (탈퇴 이유는 선택) → 로그인 화면

구글 인증에 성공한 것만으로는 계정을 만들지 않는다. 필수 동의가 모두 완료될 때 계정과 동의 이력을 함께 만든다. 필수 동의를 거부하거나 중단하면 계정이 남지 않는다.

### 엔드포인트

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `POST` | `/auth/google` | 구글 ID 토큰 검증. 계정이 있으면 세션 발급, 없으면 동의 요청 |
| `POST` | `/auth/consent` | 필수 동의 제출. 계정과 동의 이력 생성 후 세션 발급 |
| `GET` | `/auth/me` | 세션으로 현재 계정 조회 (`Authorization: Bearer <accessToken>`) |
| `PATCH` | `/auth/me/consents` | 선택 동의 변경. 직전 동의 이력을 복사해 보낸 항목만 바꾼 이력 추가 |
| `POST` | `/auth/logout` | 요청에 쓴 세션 폐기. 본문 없이 `204` |
| `DELETE` | `/auth/me` | 회원 탈퇴. 계정과 그 아래 기록을 지우고 요청에 쓴 세션 폐기. 탈퇴 이유는 선택 본문. `204` |
| `PUT` | `/auth/me/push-devices/{fid}` | 리포트 완료 푸시를 받을 기기(FCM FID) 등록. 본문 없이 `204` |
| `DELETE` | `/auth/me/push-devices/{fid}` | 기기 등록 해제. 본문 없이 `204` |

요청과 응답의 정확한 형태는 서버 실행 후 `http://127.0.0.1:8000/docs` 와 `openapi.json` 에서 확인한다. 구현 전 API를 포함한 전체 명세는 [API 명세](../docs/architecture/api-spec.md)를 따른다.

`POST /auth/google` 은 `{"idToken": "..."}` 를 받고 `status` 로 갈라지는 두 응답 가운데 하나를 준다.

사진 보관과 AI 분석을 가입 화면에서 선택 동의로 받는 2026-10-14 PM 결정은 [보관 기준과 후속 작업](#보관-기준과-후속-작업)에 기록했다. 아래 API 예시는 현재 구현이며, 두 항목 중 AI 사진 분석(`photoAnalysis`)은 #257로 선택 동의에 들어갔고 사진 보관 동의는 아직 없다.

아래 동의 목록은 현재 BE 구현의 예시다. [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)에서 알림 수신을 선택 동의로 옮겨 공통 계약과 FE의 기준에 맞췄다. 알림을 거부해도 필수 동의를 완료하면 계정이 생성된다.

```json
{
  "schemaVersion": 1,
  "status": "consentRequired",
  "registrationToken": "...",
  "expiresIn": 600,
  "consentVersion": "2026-09-06",
  "requiredConsents": ["serviceData", "sensitiveData"],
  "optionalConsents": ["serviceImprovement", "pushNotification", "photoAnalysis"]
}
```

```json
{
  "schemaVersion": 1,
  "status": "authenticated",
  "accessToken": "...",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "account": { "schemaVersion": 1, "accountId": "...", "authProvider": "google", "...": "..." }
}
```

`POST /auth/consent` 는 `registrationToken`, `consentVersion`, `consents`(네 항목은 필수 boolean, `photoAnalysis`는 선택이며 빠지면 거부로 저장)와 선택값 `displayName` 을 받고 `status=authenticated` 응답을 준다.

`POST /auth/logout` 은 요청 본문을 받지 않고 `Authorization` 헤더의 세션만 본다. `DELETE /auth/me` 는 탈퇴 이유를 선택 본문(`reasons`, `otherText`)으로 받으며, 고르지 않았으면 본문 없이 보낸다.

`PATCH /auth/me/consents` 는 선택 동의(`serviceImprovement`, `pushNotification`, `photoAnalysis`) 중 보낸 항목만 바꾼다([API 1-6](../docs/architecture/api-spec.md#1-6-patch-authmeconsents--신규)).

- 직전 동의 이력을 복사해 보낸 항목만 바꾼 이력 행을 더하며 약관 버전은 직전 이력의 값을 쓴다. 같은 계정의 동시 변경이 서로를 덮지 않도록 계정 행을 잠근 뒤 더한다.
- 값은 `true`, `false`만 받는다. 필수 동의(`serviceData`, `sensitiveData`)를 보내면 `REQUIRED_CONSENT_NOT_CHANGEABLE`(422), 본문이 비었거나 `null`을 보내면 `INVALID_REQUEST`(422)다.
- 로그아웃은 계정이 이미 없어도 세션을 폐기한다. 같은 계정의 다른 세션은 그대로 둔다.
- 탈퇴는 `users` 행을 지운다. 같은 계정의 다른 세션은 이후 `ACCOUNT_NOT_FOUND`(404)로 거절된다. 같은 구글 계정으로 다시 로그인하면 지운 계정이 되살아나지 않고 `status=consentRequired`를 받는다.
- DB의 `ON DELETE CASCADE`로 동의 이력, 프로필과 그 아래의 모든 기록이 함께 지워지고, 사진과 음성 원본의 객체 키는 trigger가 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣는다. [API 명세 1-5](../docs/architecture/api-spec.md#1-5-delete-authme--수정)의 범위다. 대기열의 S3 객체는 삭제 실행기(#204)가 지운다. 운영에서 실제 삭제를 실행했는지는 [보관 기준과 후속 작업](#보관-기준과-후속-작업)을 따른다. 대기열 등록만으로 삭제 완료를 표시하지 않는다.
- 탈퇴 이유는 계정 삭제와 같은 트랜잭션에서 `withdrawal_feedback(reasons, other_text)`에 넣고 계정 ID는 넣지 않는다. `reasons`는 1개 이상이고 중복을 받지 않으며, `otherText`는 `other`를 고른 경우에만 비우지 않고 보낸다. 조건이 맞지 않으면 `INVALID_REQUEST`(422)이며 계정을 지우지 않는다. `otherText`는 로그에 남기지 않는다.

#### 푸시 받을 기기

리포트 완료 푸시를 보낼 기기를 `push_devices(fid, user_id, registered_at)`에 둔다(#248, [API 1-7, 1-8](../docs/architecture/api-spec.md#1-계정), [서비스](app/services/push_devices.py)). 발송은 아래 "리포트 완료 푸시"에 있다.

- `fid`는 앱이 FCM에 등록하고 받은 Firebase Installation ID다. FCM HTTP v1은 기기 토큰(`token`) 대신 `fid`로 보내도록 바꿨다. 경로로 받으며 영문 대소문자, 숫자, `-`, `_`로 된 1~64자만 받는다(DB CHECK도 같다). 기기를 가리키는 값이라 로그에 남기지 않는다.
- 등록(1-7)은 알림 수신 동의가 켜진 계정만 받고, 아니면 `PUSH_NOTIFICATION_CONSENT_REQUIRED`(403)다. 동의를 바꾸는 1-6과 겹치지 않도록 계정 행을 `FOR SHARE`로 잠근 뒤 현재 동의를 읽고 저장한다. 같은 FID를 다시 보내면 `registered_at`만 새로 하고, 다른 계정의 FID면 이 계정으로 옮긴다.
- 해제(1-8)는 이 계정의 등록만 지우며 없거나 다른 계정의 FID여도 `204`다. 알림 동의가 없어도 지울 수 있다.
- 1-6에서 `pushNotification: false`를 보내면 같은 트랜잭션에서 그 계정의 등록을 모두 지운다. 탈퇴(1-5)는 `ON DELETE CASCADE`로 지운다. 로그아웃(1-4)은 서버가 어느 기기인지 모르므로 앱이 로그아웃 전에 1-8을 보낸다.
- 오래된 등록을 주기적으로 지우는 작업은 아직 없다. 발송이 `UNREGISTERED`로 실패한 등록만 지운다. FCM은 한 달 넘게 연결이 없으면 오래된 등록으로 보며, `registered_at`으로 고를 수 있다.

#### 리포트 완료 푸시

음성 worker가 리포트를 완료로 저장한 뒤 FCM HTTP v1으로 알린다([report_notifications.py](app/services/report_notifications.py), [fcm.py](app/clients/fcm.py)).

- 완료 처리(`mark_completed`)가 커밋된 다음에 보낸다. 대상은 DB에서 다시 고른다. 작업이 `completed`이고, 그 회차 계정의 현재 동의(`current_consents`)에서 알림 수신이 켜져 있고, 그 계정의 `push_devices`에 등록된 기기만이다. 임대를 잃어 리포트를 저장하지 못한 작업이나 그사이 동의를 거둔 계정에는 보내지 않는다. 대상을 읽을 때 트랜잭션을 열지 않아 발송 중 잠금을 잡지 않는다.
- 알림은 고정 문구(`새록`, `리포트가 준비되었어요`)와 `data`의 `type: reportReady`, `sessionId`, `analysisId`만 담는다. 어르신 이름과 리포트 내용은 담지 않는다. 앱은 `type`이 `reportReady`인 알림을 누르면 `sessionId`로 리포트(7-2)를 다시 읽어 연다(#247, 홈이 아닌 보기 화면에서도 바로 여는 것은 #264, `app/lib/features/push/push_messaging.dart`).
- 인증은 Firebase 서비스 계정 키로 서명한 JWT를 Google 토큰 주소에 보내 접근 토큰을 받는다(`pyjwt[crypto]`와 `httpx`, 새 의존성 없음). 접근 토큰은 만료 60초 전까지 다시 쓰고 401을 받으면 버린다.
- 응답이 404 `UNREGISTERED`면 그 계정의 그 등록을 지운다. 400 `INVALID_ARGUMENT`는 알림 본문 문제일 수도 있어 지우지 않는다. 그 밖의 실패(429, 5xx, 연결 실패, 토큰 실패)는 이번 알림만 포기하고 다시 보내지 않는다. 알림을 놓쳐도 앱은 홈에서 회차 상태(5-4)로 리포트 도착을 보여준다.
- 발송 실패는 리포트 작업을 실패로 만들지 않는다. 로그에는 HTTP 상태, FCM 오류 코드와 건수만 남기고 FID, 키와 접근 토큰은 남기지 않는다.
- 설정: `SAEROK_FCM_CREDENTIALS_PATH`(키 파일 경로, 비우면 푸시 없음), `SAEROK_FCM_TIMEOUT_SECONDS`(요청 하나의 제한 시간, 기본 10초). 경로를 넣었는데 키 파일을 읽지 못하면 음성 worker가 시작하지 않는다. `--stt-only`는 리포트를 만들지 않으므로 키를 보지 않는다. 컨테이너 배포는 [배포 문서](docs/deployment.md)의 "리포트 완료 푸시 키"를 따른다.
- 리포트 생성 실패를 알릴지는 정하지 않아 보내지 않는다(PM 확인 필요). 실제 FCM 발송은 합성 계정과 실기기로만 확인하며, 실제 사용자 계정에 쓰기 전 조건은 [법률 문서](../docs/legal/README.md#개발-우선과-실제-사용자-자료-사용-전-확인)를 따른다.

### 세션

[ADR-007의 구현 상태](../docs/architecture/decisions/ADR-007-google-social-login.md#현재-구현과-후속-작업)에 현재 서버 구현과 앱의 후속 작업을 나누어 기록했다.

- 형식: HS256 으로 서명한 JWT. 리프레시 토큰을 따로 두지 않는다. 세션마다 무작위 `jti` 를 넣고, `jti` 가 없는 세션은 `UNAUTHENTICATED` 로 거절한다.
- 수명: `SAEROK_SESSION_TTL_SECONDS`(기본 1시간).
- 폐기: 로그아웃과 탈퇴는 그 세션의 `jti` 를 만료 시각까지 `session_revocations` 테이블(`PostgresSessionRevocationStore`)에 남긴다. 폐기한 세션은 만료 전이라도 `UNAUTHENTICATED`(401)다. 테이블에는 `jti` 와 만료 시각만 두고 계정 식별자와 토큰 원문은 두지 않으며, 계정을 참조하지 않으므로 탈퇴 뒤에도 만료까지 남는다. 서버를 다시 띄우거나 여러 개 띄워도 같은 기록을 본다. 만료가 지난 행은 다음 폐기 때 지운다. 인증이 필요한 요청은 폐기 여부를 확인하려고 DB 연결을 연다. 업로드 네 경로는 본문을 읽기 전에 서명과 만료를 먼저 확인하고, 폐기 여부는 본문을 받은 뒤 같은 의존성에서 확인한다([요청 본문 크기 상한](#요청-본문-크기-상한)). 메모리 구현(`InMemorySessionRevocationStore`)은 DB 없이 인증 경로를 검사하는 테스트에만 쓴다.
- 갱신: 앱이 사용자에게 매번 로그인 버튼을 누르게 하지 않고 구글 무음 로그인으로 새 ID 토큰을 받아 `POST /auth/google`을 다시 호출한다. 앱을 다시 켤 때의 재인증은 PR #50, 쓰는 중 세션이 만료됐을 때의 재인증은 #175로 들어왔다(`app/lib/features/auth/session_restore.dart`, `session_refresher.dart`). 무음 로그인으로 받지 못하면 로그인 화면으로 보낸다. 계정이 사라졌으면 쓰는 중에는 동의 화면으로 보내고(#175), 앱을 다시 켤 때는 세션을 지우고 로그인 화면에서 다시 시작하게 한다(ADR-007). 서버가 보관하는 갱신 자격증명은 없다.
- 등록 토큰은 구글 인증과 동의 제출 사이에서만 쓰는 별도 토큰이며 `typ` 으로 세션과 구분한다. 아직 계정이 없는 상태를 이어주기 위해 제공자 식별자를 담으므로, 서명은 되어 있지만 내용은 토큰을 가진 쪽이 읽을 수 있다. 앱은 자신의 구글 `sub` 를 이미 ID 토큰으로 갖고 있어 새로 드러나는 값은 없으나, 서버 측 임시 저장으로 바꿀지는 검토 대상이다.

### 오류

모든 오류는 공통 `ErrorResponse`(`errorCode`, `message`, `requestId`, `retryable`)로 돌려준다. ID 토큰, 구글 `sub`, 이메일과 세션 값은 오류 메시지와 로그에 넣지 않는다.

| `errorCode` | HTTP | 언제 |
| --- | --- | --- |
| `INVALID_REQUEST` | 422 | 요청 형식이 계약과 다름 |
| `AUTH_NOT_CONFIGURED` | 503 | 클라이언트 ID 또는 세션 서명 키가 설정되지 않음 |
| `INVALID_ID_TOKEN` | 401 | 서명, 형식 또는 `kid` 확인 실패 |
| `ID_TOKEN_EXPIRED` | 401 | ID 토큰 만료 |
| `ID_TOKEN_AUDIENCE_MISMATCH` | 401 | `aud` 가 허용 목록에 없음 |
| `ID_TOKEN_ISSUER_MISMATCH` | 401 | `iss` 가 구글이 아님 |
| `IDENTITY_PROVIDER_UNAVAILABLE` | 503 | 구글 JWKS 조회 실패 (`retryable: true`) |
| `INVALID_REGISTRATION_TOKEN` | 401 | 등록 토큰이 유효하지 않거나 용도가 다름 |
| `REGISTRATION_TOKEN_EXPIRED` | 401 | 동의 제출까지 시간이 지남 |
| `REQUIRED_CONSENT_MISSING` | 422 | 필수 동의를 거부함. 계정을 만들지 않음 |
| `REQUIRED_CONSENT_NOT_CHANGEABLE` | 422 | 선택 동의 변경에 필수 동의를 보냄 |
| `CONSENT_VERSION_MISMATCH` | 409 | 앱이 보낸 약관 버전이 서버와 다름 |
| `UNAUTHENTICATED` | 401 | 세션이 없거나 유효하지 않음. 로그아웃이나 탈퇴로 폐기한 세션 포함 |
| `SESSION_EXPIRED` | 401 | 세션 만료. 다시 로그인 필요 |
| `ACCOUNT_NOT_FOUND` | 404 | 세션은 읽었으나 계정이 없음 |
| `DATABASE_NOT_CONFIGURED` | 503 | `SAEROK_DATABASE_URL`이 설정되지 않아 계정 저장소를 쓸 수 없음 |

JWKS 조회에 실패하면 검증을 건너뛰지 않고 503 으로 거부한다. 검증하지 못한 토큰이 통과하는 경로는 없다.

### 설정

`.env.example` 을 `.env` 로 복사해서 채운다. `.env` 는 커밋 대상이 아니다.

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_GOOGLE_CLIENT_IDS` | `aud` 로 허용할 구글 클라이언트 ID. 쉼표로 구분. 비면 로그인 거부 |
| `SAEROK_SESSION_SECRET` | 세션 JWT 서명 키. 32바이트 이상. 비면 인증 경로 전체가 503 |
| `SAEROK_SESSION_TTL_SECONDS` | 세션 수명 (기본 3600) |
| `SAEROK_REGISTRATION_TTL_SECONDS` | 등록 토큰 수명 (기본 600) |
| `SAEROK_CONSENT_VERSION` | 동의 화면이 제시하는 약관 버전 |
| `SAEROK_STORE_GOOGLE_PROFILE` | 표시 이름을 입력하지 않았을 때 구글 계정 이름을 쓸지 여부 (기본 `false`). 스키마에 이메일 컬럼이 없어 이메일은 이 값과 관계없이 저장하지 않는다 |
| `SAEROK_DATABASE_URL` | 계정 저장소 연결. 비면 계정을 쓰는 인증 경로가 503 |

안드로이드에서 붙일 때는 서버를 `--host 0.0.0.0` 으로 띄우고 에뮬레이터에서 `http://10.0.2.2:8000` 을 쓴다. 합성 데이터와 개발용 계정으로만 확인한다.

### 아직 정하지 않은 것

- **계정 저장 항목** — ADR-007의 PM 제안은 이메일과 구글 계정 이름을 저장하지 않는 방향이며 기본 설정은 `false`다. 현재 스키마의 `users`는 구글 `sub`, 표시 이름과 가입 시각만 두고 이메일 컬럼이 없다. 표시 이름이 비어 있으면 `보호자`를 쓴다. 추가 수집 필요성은 별도 검토한다. 설정 스위치가 실제 사용자 정보 수집을 승인하는 것은 아니다.
- **`Account.email`의 널 허용** — 공통 계약, Flutter `Account`와 합성 예시는 nullable 응답을 읽도록 맞췄다. 이것으로 이메일 미저장 정책이나 DB 연결까지 확정한 것은 아니다. PR #50의 `AuthAccount`를 하나의 클래스로 합치는 작업도 포함하지 않는다.
- **`aud` 로 쓸 클라이언트 ID** — `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 웹 클라이언트 ID가 된다. FE 가 쓰는 값을 확인해서 `SAEROK_GOOGLE_CLIENT_IDS` 에 넣는다. Google Cloud Console 에 패키지명 `app.saerok.android` 와 디버그 및 릴리스 SHA-1 등록이 선행되어야 한다. 쉼표 구분 설정의 읽기 보완은 PR #51로 병합됐다.
- **재동의** — 약관 버전이 올라갔을 때 기존 계정에 다시 동의를 받는 흐름은 넣지 않았다. 응답의 `account.consent.consentVersion` 으로 앱이 비교할 수는 있다.
- **약관 본문 제공** — 약관 본문, 버전과 필수 여부의 서버 관리는 PR #50에 남긴 후속 요청이다. 현재 API가 약관 본문까지 제공하는 것으로 읽지 않는다. 앱 재실행 시 세션 복원(PR #50)과 만료 후 자동 재인증(#175)은 앱에 구현됐다([세션](#세션)).
- **탈퇴와 계정 삭제** — `DELETE /auth/me`는 `users` 삭제의 `ON DELETE CASCADE`로 계정 아래의 서버 기록을 모두 지운다. [API 명세 1-5](../docs/architecture/api-spec.md#1-5-delete-authme--수정)의 범위이며, [법률 문서의 PM 검토안](../docs/legal/README.md#구글-로그인-데이터-이동에-대한-pm-검토안)이 적은 범위(인증 제공자, `sub`, 내부 계정 식별자와 동의 이력)보다 넓다. 이 범위의 법률 검토, S3 삭제 대기열의 처리, 백업과 단말 자료의 삭제 범위, 탈퇴 후 보관 기간과 재가입 허용 여부는 정해지지 않았다. 지금 코드는 재가입을 막지 않으며, 이것으로 재가입 허용을 정한 것은 아니다. ADR-007의 재검토 조건(탈퇴 시 삭제 범위, 세션 형식 변경)에 해당한다.

## 최소 지원 앱 버전

구버전 앱이 바뀐 API를 부르다 이상하게 실패하는 대신, 업데이트가 필요하다는 응답을 받게 한다. 앱은 모든 요청에 안드로이드 versionCode를 `X-App-Version-Code` 헤더로 싣는다(`app/README.md`의 "서버에 앱 버전 알리기"). 서버는 [deps.py](app/api/deps.py)의 `require_supported_app_version`에서 이 값을 설정과 비교한다. [router.py](app/api/router.py)가 `/health/*`를 뺀 모든 경로에 이 의존성을 건다. 업로드 네 경로는 본문을 읽기 전에 [body_limits.py](app/api/body_limits.py)가 같은 함수로 한 번 더 확인해, 큰 본문을 받기 전에 426을 돌려준다.

| 요청 | 결과 |
| --- | --- |
| 헤더 값이 `SAEROK_MIN_ANDROID_VERSION_CODE`보다 작음 | `426 APP_UPDATE_REQUIRED`, `retryable: false`. 인증과 DB보다 먼저 확인해 로그인 전 API(`/auth/google`, `/auth/consent`)도 같다 |
| 헤더 값이 설정 이상 | 통과 |
| 헤더가 없거나 ASCII 숫자가 아님 | 통과. 헤더를 싣기 전에 낸 앱 빌드와 점검 도구를 막지 않는다 |
| 설정이 `0`(기본값) | 검사하지 않음 |
| `/health/*` | 검사하지 않음. compose 헬스체크용 |

경로가 없는 요청(404)에는 의존성이 돌지 않는다. 앱은 `404 NOT_FOUND`도 따로 업데이트 안내의 단서로 쓴다.

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_MIN_ANDROID_VERSION_CODE` | 받을 수 있는 가장 낮은 앱 versionCode (기본 `0`, 검사 안 함) |

**올리는 순서.** 구버전 앱과 맞지 않는 서버 변경을 배포할 때는, 맞는 앱 빌드를 Play에 먼저 낸 뒤 이 값을 그 빌드의 versionCode로 올린다. 앱 쪽 헤더를 처음 싣는 빌드보다 앞선 빌드는 헤더가 없어 이 검사로 막을 수 없다.

헤더 값은 사용자를 식별하지 않는 앱 빌드 번호다. 요청 로그([logging.py](app/core/logging.py))는 헤더를 기록하지 않는다.

## 요청 본문 크기 상한

FastAPI는 앱 버전, 인증, 소유권과 파일 크기를 확인하는 의존성보다 multipart와 JSON 본문을 먼저 끝까지 읽는다. 상한이 없으면 로그인하지 않은 요청의 큰 본문도 API의 메모리와 임시 파일에 다 쓴 뒤에야 거절된다. [body_limits.py](app/api/body_limits.py)의 `RequestBodyLimit`은 FastAPI가 본문을 읽기 전에 도는 ASGI 미들웨어로, 경로별 본문 상한과 업로드 경로의 세션 확인을 맡는다. [main.py](app/main.py)에서 요청 로그보다 먼저 등록해 요청 로그 안쪽에 놓인다.

| 경로 | 본문 상한 | 넘으면 |
| --- | --- | --- |
| `POST /api/v1/profiles/{profileId}/photos`, `POST /api/v1/visit-sessions/{sessionId}/photo` | `SAEROK_MAX_IMAGE_BYTES` + 1 MiB | `413 IMAGE_TOO_LARGE` |
| `POST /api/v1/visit-sessions/{sessionId}/speech-analyses` | `SAEROK_MAX_AUDIO_BYTES` + 1 MiB | `413 AUDIO_TOO_LARGE` |
| `POST /api/v1/speech-transcriptions` | `min(SAEROK_MAX_AUDIO_BYTES, speech_transcription.MAX_BYTES)` + 1 MiB | `413 AUDIO_TOO_LARGE` |
| 그 밖의 모든 요청 | 1 MiB | `413 REQUEST_TOO_LARGE` |

- 상한은 라우트가 쓰는 설정값과 상수에서 계산한다. 더한 1 MiB는 multipart 경계와 파일이 아닌 필드의 여유다. 파일 자체의 크기 검사(`validate_image`, `validate_visit_audio`)는 그대로 라우트가 한다.
- `Content-Length`가 상한을 넘으면 본문을 읽지 않고 거절한다. 길이가 없거나(chunked) 실제로 더 보내면 받은 양을 세다가 상한을 넘는 조각에서 끊는다. 이때 만들던 multipart 임시 파일은 Starlette가 닫는다.
- 업로드 네 경로는 본문을 읽기 전에 앱 버전(`require_supported_app_version`, 426)과 세션 토큰의 형식, 서명과 만료(`read_signed_session`, 401)를 확인한다. `get_current_session`과 같은 함수다. 폐기 여부, 계정, 소유권과 동의는 본문을 받은 뒤 기존 의존성이 확인한다. 그래서 폐기한 세션은 본문 상한까지는 받은 뒤 401이 된다.
- 상한을 넘거나 본문 전 확인에서 거절한 업로드는 본문을 끝까지 받지 않고 응답한다. 앞단(Caddy)은 읽지 않은 본문이 많으면 응답 뒤 연결을 닫을 수 있어, 아직 본문을 보내던 클라이언트는 413이나 401 본문 대신 연결 오류를 받을 수 있다. 앱은 올리기 전에 파일 크기를 확인한다.
- 업로드 경로의 413은 라우트의 파일 검사와 같은 오류 코드와 문구를 쓴다. JSON 요청이 상한을 넘으면 `413 REQUEST_TOO_LARGE`다([API 명세의 본문 크기와 확인 순서](../docs/architecture/api-spec.md#본문-크기와-확인-순서)).
- 본문을 읽기 전에 거절한 요청은 경로를 찾기 전이라 요청 로그의 `route`가 `unmatched`로 남는다. 요청 ID와 상태 코드는 그대로 남는다.
- 테스트가 `dependency_overrides`로 `get_current_session`이나 `get_current_account`를 바꿔 끼운 앱은 라우트도 토큰을 보지 않으므로, 미들웨어도 토큰 확인을 건너뛴다. 설정(`get_settings`)의 덮어쓰기도 따른다. 운영 앱은 덮어쓰기를 쓰지 않는다.
- 기본 설정에서 면회 음성 경로는 로그인한 계정이 요청마다 513 MiB까지 보낼 수 있다. 음성 상한을 낮추거나 받는 동안 검증하는 것은 별도 결정이다.

HTTPS 앞단 [Caddyfile](Caddyfile)은 `request_body`의 `max_size 514MiB`로 가장 큰 경로별 상한보다 조금 큰 바깥 상한을 둔다. 정상 설정에서는 경로별 상한(최대 513 MiB)이 더 작아 API가 먼저 공통 형식의 `413`이나 `401`을 돌려준다. Caddy 상한은 API 상한을 잘못 키웠을 때의 바깥 방어선이며, 그때 Caddy가 돌려주는 `413`에는 공통 오류 본문이 없다. `SAEROK_MAX_AUDIO_BYTES`를 513 MiB보다 크게 올리면 Caddyfile도 함께 올린다. Caddyfile 변경을 서버에 적용하는 절차는 [배포 문서](docs/deployment.md#갱신)에 있다.

## 프로필과 생애 정보 API

[API 명세 2절](../docs/architecture/api-spec.md#2-프로필)의 2-1~2-4, 2-6~2-9이다. 온보딩의 `마치기`는 세부 정보를 2-4로 저장한 뒤 작업 B의 4-1로 첫 카드 생성을 요청한다. 별도의 2-5 API는 사용하지 않는다. 라우트는 [profiles.py](app/api/routes/profiles.py)와 [life_facts.py](app/api/routes/life_facts.py), 저장은 [services/profiles.py](app/services/profiles.py)와 [services/life_facts.py](app/services/life_facts.py)에 있다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `GET` | `/api/v1/profiles` | 현재 계정의 프로필 목록. 만든 순서이며 입력 중인 프로필도 담는다 |
| `POST` | `/api/v1/profiles` | 기본 정보로 프로필 생성. `201`, `setupStatus`는 `inProgress` |
| `GET` | `/api/v1/profiles/{profileId}` | 프로필, 생애 정보와 프로필 사진 |
| `PATCH` | `/api/v1/profiles/{profileId}` | 기본 정보와 세부 정보 네 항목 중 보낸 필드만 수정 |
| `DELETE` | `/api/v1/profiles/{profileId}` | 프로필 하나와 그 아래 기록 삭제. `204` |
| `POST` | `/api/v1/profiles/{profileId}/life-facts` | 일대기에서 생애 정보 추가. `201` |
| `PATCH` | `/api/v1/life-facts/{factId}` | 생애 정보 중 보낸 필드만 수정 |
| `DELETE` | `/api/v1/life-facts/{factId}` | 일대기에서 생애 정보 삭제. `204` |

- `setupStatus`는 저장하지 않고 `card_sets` 행이 있는지로 계산한다.
- 계정당 프로필은 입력 중인 것을 포함해 3개까지다. DB 제약이 없으므로 같은 트랜잭션에서 계정 행을 `FOR UPDATE`로 잠근 뒤 세어, 동시 요청에도 넘지 않는다. 넘으면 `PROFILE_LIMIT_EXCEEDED`(409)다.
- 2-4의 세부 정보 네 항목은 `null`을 보내면 지운다. 이름, 성별, 생년월일과 `condition`은 `null`로 지울 수 없다. `condition`을 보낼 때 `stage`는 항상 보내며, `symptomNote`를 빼면 저장된 메모를 그대로 두고 `null`을 보낼 때만 지운다. 본문이 비어 있으면 바꾸지 않고 현재 프로필을 돌려준다.
- 빈 문자열과 공백만 있는 값은 이름, 세부 정보와 생애 정보의 제목과 내용에서 `INVALID_REQUEST`(422)다. DB CHECK도 막지만 요청 검증이 먼저 거절한다.
- 다른 계정의 자원과 없는 자원은 같은 `PROFILE_NOT_FOUND` 또는 `LIFE_FACT_NOT_FOUND`(404)다.
- 프로필 삭제는 `ON DELETE CASCADE`로 생애 정보, 사진, 주제와 대화 카드, 면회 기록을 함께 지우고, 사진과 음성의 객체 키는 trigger가 S3 삭제 대기열에 넣는다. 카드와 주제가 함께 있는 프로필의 삭제와 탈퇴는 테스트로 확인했다. 대기열을 처리해 S3 원본을 지우는 실행기는 #204로 들어왔고, 운영 실행 상태는 [보관 기준과 후속 작업](#보관-기준과-후속-작업)을 따른다. 처리 중인 작업이 있는 프로필의 삭제는 미정이다([API 명세 미정 사항](../docs/architecture/api-spec.md#미정-사항) 8).
- 응답의 `photos`는 프로필 사진(`session_id IS NULL`)을 올린 순서대로 담고, 사진마다 `storage.create_download`로 `imageUrl`을 만든다. 사진이 없으면 사진 저장소를 부르지 않으므로 버킷 설정 없이도 응답한다. 업로드는 아래 [사진 저장 (S3)](#사진-저장-s3)의 3-1이다.
- AI 분석 동의 확인과 분석 중 철회 처리는 #257로 구현했다. 실제 사용자 사진을 받기 전에는 사진 보관 동의 확인과 철회 뒤 기존 결과 처리를 정하고 검증한다(후속 3). 자동 테스트는 합성 사진과 메모리 저장소를 쓴다. 실제 S3 업로드와 조회는 11/8 운영 안정성 시험에서 공개 라이선스 사진 43장으로 확인했다([stability-test-20261108](docs/stability-test-20261108.md)).
- `create_life_fact(connection, *, profile_id, title, content, source_proposal_id=None, story_category="other", image_number=None)`는 7-4(작업 C)도 쓴다. 트랜잭션을 열지 않으므로 부르는 쪽의 트랜잭션에 묶이고, 소유 확인은 부르는 쪽이 한다. 7-4는 분류와 그림 번호를 보내지 않으므로 `other`와 서버가 고른 1~5 번호로 만든다.
- 생애 정보는 일대기의 분류(`storyCategory`: `family`, `hobby`, `work`, `hometown`, `friend`, `travel`, `other`)와 기본 그림 번호(`imageNumber`, 1~5)를 가진다. 2-6은 둘 다 필수이고 2-7은 보낸 것만 바꾼다. 그림 파일은 앱에 있고 서버는 번호만 저장한다. 필드 이름, 7-4의 분류와 삭제 뒤 카드 처리는 미정이며 [작업 D 문서](docs/work-split/D-life-story.md)에 모았다.
- 2-9는 생애 정보 행만 지운다. 다음 카드 생성(4-1)의 입력에서 빠지고, 이미 만든 카드와 주제는 남는다. 주제와 지난 카드의 근거에 남은 지운 이야기의 `factId`는 저장된 값은 두고 4-1 입력을 만들 때만 뺀다(`card_sets._without_missing_evidence`).
- 보호자가 제외(`exclude`)한 주제의 근거 이야기와 사진도 4-1 입력에서 뺀다(`card_sets._excluded_evidence`). 제외는 주제 하나에 걸리므로, 근거가 입력에 남으면 같은 이야기로 이름만 다른 새 주제가 다시 만들어진다. 세부 정보 네 칸은 칸 전체가 빠지면 다른 주제까지 사라지므로 남긴다. 저장된 이야기와 사진은 그대로이며 일대기에도 그대로 보인다.

## AI 음성 분석 연동

비동기 처리 경계와 상태는 [ADR-008](../docs/architecture/decisions/ADR-008-stt-pipeline.md)의
제안 및 [공통 데이터 계약](../docs/architecture/data-contracts.md)을 따른다. 앱은 다음 multipart
API로 WAV와 보호자가 확인한 참여자 수를 제출한다.

구현 파일, 환경 설정과 합성 WAV를 사용한 전체 테스트 절차는
[비동기 면회 음성 STT 구현 및 테스트 가이드](docs/async-speech-analysis.md)에 정리했다.

```http
POST /api/v1/visit-sessions/{sessionId}/speech-analyses
Authorization: Bearer <accessToken>
Content-Type: multipart/form-data

audio=<WAV/PCM 16-bit/16kHz/mono>
participantCount=2
```

BE는 인증, 필수 동의, 회차 소유권과 보호자 평가 제출 여부를 확인하고 파일 형식과
크기를 검증한다. 평가 전이면 `EVALUATION_REQUIRED`(409)다. S3 업로드와 작업 DB 저장이 끝나면 `202 Accepted`와 `analysisId`를
반환한다. STT 완료를 뜻하지 않는다.

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "sessionId": "4ad84021-e2db-4a04-8995-b148f3cdb853",
  "status": "queued"
}
```

상태 조회는 인증된 `GET /api/v1/speech-analyses/{analysisId}`다. 다른 계정의 작업은
존재 여부를 드러내지 않고 404로 처리한다. 상태는 `queued`, `transcribing`,
`sttCompleted`, `generatingReport`, `completed`, `failed`이며 `failed`일 때 안전한
`errorCode`만 반환한다. `sttCompleted`는 AI 응답 검증과 전사문 임시 저장이 끝났다는
뜻이며 리포트 완료나 원본 삭제 완료를 뜻하지 않는다. 삭제 여부는 `audio_deleted_at`과
삭제 대기열로 따로 확인한다.

worker는 PostgreSQL에서 `queued` 작업을 행 잠금으로 하나씩 가져오고 S3 Presigned GET
URL을 만들어 AI 서버의 기존 동기 `POST /internal/v1/speech-analyses`를 호출한다.
`participantCount`는 `speakerCount`로 전달한다. STT 응답 뒤 전사를 저장하고 S3 원본
삭제를 즉시 시도한다. 삭제 요청은 먼저 DB에 남기며 S3 삭제만 실패해도 리포트 생성은
계속한다. 리포트 생성과 저장까지 성공해야 작업을 `completed`로 바꾼다.

화자 라벨이 누락되거나 라벨 수가 입력 인원보다 적어도 리포트와 변경 제안 모델을
호출한다. 빈 전사는 `EMPTY_TRANSCRIPT`로 거절한다. 프롬프트의 출처 구분과 보호자의
이야기 승인 절차는 유지한다([화자 처리](docs/speaker-fact-boundary.md)).

현재 코드에는 작업 저장소, S3 어댑터, 제출 및 조회 API와 독립 worker 실행 진입점이
있다. worker는 STT 뒤 같은 작업에서 리포트 생성기(8-3, [평가와 리포트 API](#평가와-리포트-api))로
리포트와 변경 제안을 저장한 뒤에만 `completed`로 바꾼다. 전사문은 리포트 생성
입력으로 작업에 임시 저장한다. 최초 STT 저장부터 24시간이 만료 시각이며, 실패해도
남은 기한 동안 전사를 재사용한다(2026-11-03 PM 승인). 재시도로 기한을
늘리지 않는다. 성공 시 전사를 지우고, 만료분은 worker 정리 때 삭제하며 작업을
`failed`(`TRANSCRIPT_EXPIRED`)로 바꾼다. worker 중단이나 긴 처리 중에는 정리가 늦어질
수 있으므로 기한 삭제 감시가 필요하다([보관 대조](docs/speech-recovery.md#실패-전사와-기기-녹음의-보관-대조)).
리포트 생성(전사문의 외부 ML 전송)은 남은 전사 기한이 생성 단계 임대 시간 이상일 때만
시작하고, 그보다 적게 남은 `sttCompleted` 작업은 시작하지 않고 같은 코드로 끝낸다
([외부 ML 전송과 기한](docs/speech-recovery.md#외부-ml-전송과-기한)). worker는 위의 공통 골격으로 동작하며,
임대 시간 안에 끝나지 않은 작업은 `WORKER_LEASE_EXPIRED`로 실패시킨다. 전사를 저장할 때
리포트까지 이어 갈 worker는 인계 임대(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`)를 함께 기록한다.
그 안에 리포트 생성을 시작하지 못하고 멈춘 작업은 임대가 끝난 뒤 다음 worker가 같은 작업 ID와
저장된 전사로 이어받는다. STT를 반복하지 않고, 원본 삭제 기록이 없으면 삭제 요청만 대기열에
남긴다. 이미 이어받은 작업이면 늦게 돌아온 worker는 리포트 생성을 시작하지 못한다. 이어받을 때도
남은 전사 기한이 생성 단계 임대 시간 이상이어야 한다([분석 복구](docs/speech-recovery.md)). 실패한
작업의 자동 재시도와 취소는 없으며 실패를 숨겨 재실행하지 않는다. 리포트 생성의 시간 제한과 늦은 결과
처리는 [평가와 리포트 API](#평가와-리포트-api)에 정리한다.

API 서버와 별도 터미널에서 worker를 실행한다.

```bash
bash ./scripts/run_speech_worker.sh
```

대기 작업 하나만 처리하고 종료하는 통합 확인은 다음과 같다.

```bash
bash ./scripts/run_speech_worker.sh --once
```

기본 worker는 리포트 생성에 `SAEROK_ML_API_KEY`가 필요하며, 없으면 시작하지 않는다(키
없이 전체 처리가 되는 것처럼 실행하지 않는다). 키 없이 STT만 확인할 때는
`--stt-only`(development/test 환경에서만)를 쓴다. 리포트 생성기를 만들지 않고 작업은
`sttCompleted`에서 멈추며 `completed`가 되지 않는다. 인계 임대를 두지 않으므로 나중에 기본
worker를 실행해도 이 작업을 리포트 생성에 넘기지 않는다.

```bash
bash ./scripts/run_speech_worker.sh --stt-only --once
```

### 음성 분석 설정

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_AI_SERVER_URL` | 내부 AI 서버 주소, 기본 `http://127.0.0.1:8001` |
| `SAEROK_AI_SERVER_TIMEOUT_SECONDS` | worker가 AI 동기 응답을 기다리는 제한, 기본 600초 |
| `SAEROK_AI_SERVER_BACKUP_URL` | 선택한 예비 STT 주소. 기본은 비어 있어 기존 단일 서버 동작을 유지 |
| `SAEROK_AI_SERVER_FAILOVER_CONNECT_TIMEOUT_SECONDS` | 예비 주소를 설정한 경우 서버별 연결 제한. 기본 5초, 0초 초과 30초 이하 |
| `SAEROK_SPEECH_AUDIO_S3_BUCKET` | 비공개 음성 임시 저장 버킷. DB와 함께 설정해야 업로드 API 활성화 |
| `SAEROK_SPEECH_AUDIO_S3_REGION` | S3 리전, 기본 `ap-northeast-2` |
| `SAEROK_SPEECH_AUDIO_S3_PREFIX` | 개인정보를 넣지 않는 객체 키 접두사 |
| `SAEROK_SPEECH_AUDIO_S3_ENCRYPTION` | 서버 측 암호화 `AES256` 또는 `aws:kms` |
| `SAEROK_SPEECH_AUDIO_PRESIGNED_TTL_SECONDS` | AI 다운로드 URL 수명, 기본 900초 |
| `SAEROK_SPEECH_AUDIO_RETENTION_SECONDS` | 원본 최종 삭제 기한, 기본 86100초. STT가 24시간을 넘는 기한을 거절하므로 서버 시계 차이를 감안해 86100초보다 길게 줘도 86100초로 쓴다(86400초까지 받음) |
| `SAEROK_MAX_AUDIO_BYTES` | BE와 AI가 함께 맞출 업로드 크기 상한. 면회 음성 경로의 본문 상한은 이 값 + 1 MiB다([요청 본문 크기 상한](#요청-본문-크기-상한)) |
| `SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS` | worker 작업 임대 시간, 기본 900초. 전사 단계, 전사 저장 뒤 리포트 시작까지의 인계, 리포트 생성 단계에서 각각 새로 잡음. 인계 임대가 끝난 `sttCompleted` 작업은 다른 worker가 리포트 생성을 이어받음. 리포트 생성은 남은 전사 기한이 이 값 이상일 때만 시작 |
| `SAEROK_SPEECH_WORKER_POLL_SECONDS` | 대기 작업이 없을 때 조회 간격, 기본 2초 |
| `SAEROK_REPORT_GENERATION_MODEL` | 리포트 생성(8-3) 모델, 기본 `gpt-6-luna`. `ai/common/llm.py`의 `ENDPOINTS`에 있는 이름이어야 하며 아니면 worker가 시작하지 않음(`--stt-only`는 제외) |
| `SAEROK_REPORT_GENERATION_TIME_LIMIT_SECONDS` | 리포트 생성 전체 제한 시간, 기본 600초(제안값, PM 확인 필요). 임대 시간보다 60초 이상 짧아야 하며 아니면 worker가 시작하지 않음 |
| `SAEROK_ML_API_KEY` | 리포트 생성에 쓰는 ML API 키(카드 생성과 같음). 비어 있으면 worker가 시작하지 않음(`--stt-only`는 제외) |

S3 Lifecycle의 일 단위 만료는 UTC 날짜 계산과 비동기 삭제 때문에 업로드 후 24시간 이내
삭제를 보장하지 않는다. `data_expires_at`에 따른 기한 삭제와 삭제 대기열 실행을 별도로
운영하고, Lifecycle은 보조 규칙으로 적용한다. 정상 경로에서는 STT 직후 삭제를 시도한다.
대기열 등록만으로 삭제 완료를 표시하지 않는다. 이 변경만으로 대기열 실행기가 배포되지는
않는다. [삭제 실패와 분석 결과 분리](docs/audio-deletion-isolation.md)를 참고한다.
녹음, 전사문, 원래 파일명, Presigned URL과 객체 키를 요청 로그와 오류 응답에 남기지 않는다.

### STT 예비 서버 전환

기본 서버의 연결 실패(`ConnectError`, `ConnectTimeout`)에만 예비 서버를 한 번 호출한다.
응답 대기나 전송 도중 오류, HTTP 오류와 잘못된 응답은 이미 처리 중일 수 있어 재전송하지 않는다.
두 시도는 기존 전체 STT 제한 시간을 공유하고 같은 작업 ID, 입력과 삭제 기한을 사용한다.
다음 작업은 다시 기본 서버부터 시작한다. 종료된 실패 작업을 다시 여는 기능은 아니다.

현재 문영 GPU의 Tailscale 경로를 기본으로 두고 ck SSH 예비 경로를 함께 쓴다. 운영 기록에 따르면
11/5 운영 배포(#187의 배포 기록)부터 운영 api와 speech-worker에 예비 주소가 설정돼 있고, 11/8에는 기본 경로에 연결되지 않아 예비로 처리했다.
주소를 설정하는 것만으로 SSH 터널이나 GPU 서버가 실행되지는 않는다. STT 서버 코드는 승인 배포 workflow로 배포되지 않는다.
전사 기본값 변경(#276, VAD 켬, 앞 문장 조건 끔)은 11/9 ck 예비 서버에만 손으로 적용했고 기본 GPU 서버는 아직 갱신하지 않았다(운영 기록).
[연결 제한, 검증과 운영 반영 조건](docs/stt-backup.md)을 확인한다.
기본 GPU와 ck 예비 경로의 상태 확인, 재시작과 증상별 대응은 [STT 운영 절차](docs/stt-operations.md)를 따른다.

## 사진 저장 (S3)

PR #92의 사진 검증과 S3 저장, 조회 URL 생성 및 삭제 어댑터를 프로필 사진과 면회 사진 API가 사용한다.

### 면회 사진

면회 사진(5-2) `POST /api/v1/visit-sessions/{sessionId}/photo`는 이 순서로 구현했다. 라우트는 [visit_sessions.py](app/api/routes/visit_sessions.py), 저장은 [services/visit_photos.py](app/services/visit_photos.py)에 있다.

- `multipart/form-data`의 `image` 한 장을 받아 `201`과 `VisitPhoto`를 돌려준다. 회차당 한 장(`uq_photos_session`)이며, 다시 올리면 기존 행을 지우고 새 행을 넣는다. 지운 행의 객체 키는 trigger가 S3 삭제 대기열에 넣는다.
- 평가 전 회차만 받는다(`INVALID_SESSION_STATE`, 409). 큰 파일을 S3에 올린 뒤에야 거절하지 않도록 올리기 전에 한 번 확인하고, 행을 넣을 때 회차 행을 `FOR UPDATE`로 잠근 뒤 다시 확인한다. S3 업로드 동안에는 잠그지 않는다.
- 행을 넣지 못하면(그 사이 평가 저장이나 프로필 삭제, DB 오류) 올린 객체를 `storage.delete`로 지운다. 지우지도 못하면 객체 키를 `storage_deletion_request_queue`에 직접 넣는다.
- 이미지 분석을 하지 않는다. `analysis_status`는 기본값 `pending`으로 남지만 사진 분석 대기열은 `session_id IS NULL`인 행만 가져간다.

### 프로필 사진

프로필 사진 API(3-1, 3-2)의 라우트는 [profile_photos.py](app/api/routes/profile_photos.py), 저장은 [services/profile_photos.py](app/services/profile_photos.py)에 있다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `POST` | `/api/v1/profiles/{profileId}/photos` | `multipart/form-data`의 `image` 한 장을 S3에 올리고 `analysisStatus = pending`인 행을 만든다. `201` |
| `GET` | `/api/v1/profile-photos/{photoId}` | 프로필 사진 하나와 새 `imageUrl`. 분석이 끝날 때까지 앱이 폴링한다 |
| `PATCH` | `/api/v1/profile-photos/{photoId}/description` | 보호자가 고친 설명 저장. 빈 설명과 다른 계정의 사진은 거절한다 |

설명 수정은 `user_description`과 `description_updated_at`에 저장한다. AI 원문은 기존 `description`에 유지한다. 조회와 다음 카드 생성에는 보호자가 고친 설명을 우선 사용하며 `descriptionSource`로 출처를 구분한다. 실제 내용이 바뀌면 기존 카드 묶음을 갱신 대상으로 표시하되 즉시 생성하지 않는다. 카드 생성 중에는 409로 거절하고 입력 내용을 유지한다. 별도 사진 확인 단계를 추가하지 않는다.

이 API 배포 전 migration `c62e19a4b308` 적용이 필요하다. 부모는 정리 대기열 `not_before` migration `e84b1c6da032`(#214)이므로 #204, #214 다음에 병합한다. 새 응답 필드는 추가 필드이며, 운영의 기존 앱과 실제 호환 검사는 별도로 진행한다. 로컬 검사는 합성 사진과 임시 DB를 사용했으며 실제 사진이나 운영 DB를 변경하지 않았다.

- 프로필당 5장이다(`PHOTO_LIMIT_EXCEEDED`, 409). 면회 사진은 세지 않는다. 큰 파일을 S3에 올린 뒤에야 거절하지 않도록 올리기 전에 한 번 세고, 행을 넣을 때 프로필 행을 `FOR UPDATE`로 잠근 뒤 다시 센다. S3 업로드 동안에는 잠그지 않는다.
- 행을 넣지 못하면(상한 경합, 그 사이 프로필 삭제, DB 오류) 올린 객체를 `storage.delete`로 지운다. 지우지도 못하면 객체 키를 `storage_deletion_request_queue`에 직접 넣는다. 행이 없어 trigger가 넣어 주지 않기 때문이다.
- 넣은 `pending` 행은 AI 사진 분석에 동의한 계정의 것만 사진 분석 worker(8-4)가 가져간다. 실행과 설정은 [사진 분석](docs/photo-analysis.md)을 따른다. 운영 서버에서는 11/8부터 photo-worker가 돌고, 11/8 운영 시험에서 공개 사진 43장을 두 번씩 분석해 86건 모두 완료했다. 실제 사용자 사진의 설명 품질은 확인하지 않았다.
- 분석이 끝나 설명이 생겨도 이미 받은 카드 묶음은 갱신 대상으로 바꾸지 않고 다음 카드부터 쓴다. 카드를 만드는 중에 분석이 끝난 사진도 입력에 없던 새 재료로 보고, 입력에 쓴 사진이 생성 중에 지워졌거나 설명이 바뀐 경우만 생성 결과에 `stale_at`을 남긴다(#275, `card_sets.save_result`). 설명 수정(3-3)과 사진 삭제(3-4)는 그대로 갱신 대상으로 표시한다. 현재 구현 (2026-11-09 기준): #275는 develop에만 있다. 운영 서버(`9c2b8276`)는 보호자가 고친 설명이 없는 사진의 분석이 끝나면 아직 안 쓴 완료 묶음에 `stale_at`을 남겨, 온보딩 `마치기`로 받은 첫 카드가 `needsRefresh: true`가 될 수 있다.
- 면회 사진과 다른 계정의 사진은 3-2에서 없는 사진과 같은 `PROFILE_PHOTO_NOT_FOUND`(404)다.

### 공통 처리 순서

아래는 3-1의 처리 순서이며 5-2도 같은 순서를 따른다. 자동 테스트는 합성 사진과 메모리 저장소로 검증한다. 실제 S3 업로드와 조회는 11/8 운영 안정성 시험의 프로필 사진으로 확인했다.

프로필 사진(3-1)과 면회 사진(5-2)은 같은 어댑터로 저장한다. 라우트는 `ImageStorageDep`으로
[image_storage.py](app/services/image_storage.py)의 저장소를 받고, 업로드 전에
[image_validation.py](app/services/image_validation.py)의 `validate_image`로 검사한다.

    본문을 읽기 전 앱 버전, 세션 서명과 본문 상한     # body_limits.py. 426, 401, 413 IMAGE_TOO_LARGE
    → 본문을 받은 뒤 세션 폐기, 계정과 소유권 확인
    → validate_image(파일, max_size_bytes=설정값)     # 413 IMAGE_TOO_LARGE, 422 INVALID_IMAGE_FORMAT
    → storage.object_key(photo_id=..., image=...)     # photos/{photoId}.jpg, 개인정보 없음
    → storage.upload(object_key=..., file=..., image=...)
    → photos 행 저장 (실패하면 storage.delete로 올린 객체를 지운다)
    → 응답의 imageUrl, imageUrlExpiresAt은 storage.create_download(object_key=...)

- 형식은 앱이 보낸 Content-Type이 아니라 파일 시그니처로 판단하며 JPEG와 PNG만 받는다.
- S3 오류는 `IMAGE_STORAGE_UNAVAILABLE`(503, 재시도 가능)이다. 객체 키와 S3 오류 본문은 응답과 로그에 넣지 않는다.
- 버킷이 설정되지 않았으면 사진이 필요한 순간에만 `IMAGE_STORAGE_NOT_CONFIGURED`(503)로 거절한다. 사진이 없는 프로필 조회는 그대로 동작한다.
- AI 서버에 넘기는 8-4의 `downloadUrl`도 같은 `create_download`로 만든다.
- 사진 메타데이터는 AI 분석과 주제 추천 입력에서 제외한다. 사진 파일 자체에서 EXIF를 제거하는 처리와 저장 정책은 별도 사항이며, 이 미결 항목을 메타데이터 입력 재허용으로 해석하지 않는다.
- DB에서 지운 사진의 객체 키는 trigger가 `storage_deletion_request_queue`에 넣는다. 대기열을 처리해 S3 객체를 지우는 실행기는 #204로 들어왔다([storage-deletion](docs/storage-deletion.md)). 운영에서 실제 삭제를 실행했는지는 아래 [보관 기준과 후속 작업](#보관-기준과-후속-작업)을 따른다.

### 보관 기준과 후속 작업

PR #92의 문서는 병합됐다. 2026-10-14 PM이 정한 사진 보관과 AI 분석의 가입 시 선택 동의 및 계정별 저장 방식은 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따른다.

- 사진 서버 보관과 AI 분석을 가입 화면의 별도 선택 동의로 받는다. 기존 `consent_records`에 두 항목을 추가하고 `current_consents`에서 최신 상태를 조회하도록 확장한다. 유효한 동의는 반복 요청하지 않으며 미동의, 철회 또는 기록 없는 계정이 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 이용할 수 있다.
- BE는 업로드 전에 보관 동의를, AI 작업 생성 전에 분석 동의를 각각 검사한다. 보관만 동의한 사진은 분석하지 않는다. 두 동의의 계정별 저장 방향은 확정됐지만 필드명, migration, 가입 및 동의 변경 API와 FE 연결, 철회 후 중단 및 삭제는 후속 구현이다.
  - 현재 구현 (2026-11-09 기준): AI 분석 동의는 #257로 `consent_records.photo_analysis`, 가입(1-2)과 동의 변경(1-6) API의 `photoAnalysis`, 대기열과 저장 직전의 동의 확인까지 구현했다. 앱은 가입 화면의 선택 항목(#257), 미동의 계정의 직접 설명 칸(#261), 업로드 전 동의 시트(#272), 설정의 계정 약관 동의 화면(#271)으로 연결했다. 사진 보관 동의 필드와 업로드 전 보관 동의 검사, 분석 동의 철회 때 이미 저장된 AI 설명의 처리는 남아 있다.
- 현재 3-1 코드에는 사진 보관 동의 검사가 없고, 업로드한 사진은 모두 `pending`으로 저장한다. 분석 동의가 없는 계정의 사진은 worker가 가져가지 않아 `pending`으로 남는다. 보관 동의 검사가 없는 것은 보관 동의를 없애기로 한 결정이 아니다. 실제 사용자 사진을 받기 전에는 보관 동의 검사를 구현하고 검증한다.
- 등록 사진은 앨범, 일대기와 면회 기록 표시를 위한 보관 동의를 확인한 뒤 저장한다. 해당 사진 삭제, 보관 동의 철회, 프로필 삭제, 탈퇴 또는 보관 목적 종료 시 지체 없이 삭제한다.
- 현재 5-2 코드에도 사진 보관 동의 검사가 없다. 가입 시 계정별 동의를 받는 정책은 위 ADR-001로 확정했으며, 실제 사용자 사진을 받기 전 동의 조회와 미동의 차단 구현 및 검증이 남아 있다. 테스트 자료로 개발을 먼저 진행하는 기준은 유지한다.
- AI 분석은 별도 동의를 확인한다. 분석용 임시 사본은 처리 완료 후 즉시 삭제하고 해당 작업의 최초 임시 사본 생성부터 최대 24시간을 넘기지 않는다. 재시도로 기한을 연장하지 않는다.
- 분석 동의만 철회하면 분석을 중단하고 임시 사본을 삭제한다. 별도로 동의받은 보관 목적이 유지되는 등록 사진까지 자동 삭제하는 의미는 아니다.
- 사진 API의 보관 동의 확인, 보관 동의 철회 뒤 삭제 경로는 FE, BE와 AI가 계약에 반영할 후속 작업이다. 분석 동의 쪽은 위 현재 구현처럼 분석하지 않는 사진을 `pending`으로 두고 철회 때 진행 중인 결과를 버린다.
- S3 삭제 대기열 실행과 삭제 결과 확인은 #204로 들어왔다([storage-deletion](docs/storage-deletion.md)). 코드는 운영 이미지에 들어 있다. 운영 기록에 따르면 11/6에 조회 모드로 대상만 확인했고(사진 대상은 버킷 버전 관리 때문에 실행기가 삭제를 보류한다), 실제 삭제는 PM 결정으로 보류했으며 주기 실행을 설치한 기록은 없다. photo-worker는 별도 임시 사본을 만들지 않고 S3 원본의 짧은 수명 조회 주소를 ML API에 넘긴다(#257). ML API 쪽 사본의 보관 조건은 확인하지 않았다. 실제 사용자 사진을 받기 전에 동의 화면부터 원본 삭제까지 검증한다. 어댑터 제공, DB 행 삭제 또는 대기열 등록만으로 삭제 완료를 표시하지 않는다.

### 사진 저장 설정

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_IMAGE_S3_BUCKET` | 등록 사진용 비공개 버킷. 녹음 임시 객체용 Lifecycle을 적용하지 않고 ADR-001의 사진 보관 및 삭제 조건을 따른다. 별도 삭제 처리가 없으면 안 된다는 뜻이며 무기한 보관 설정이 아니다 |
| `SAEROK_IMAGE_S3_REGION` | S3 리전, 기본 `ap-northeast-2` |
| `SAEROK_IMAGE_S3_PREFIX` | 개인정보를 넣지 않는 객체 키 접두사, 기본 `photos` |
| `SAEROK_IMAGE_S3_ENCRYPTION` | 서버 측 암호화 `AES256` 또는 `aws:kms` |
| `SAEROK_IMAGE_PRESIGNED_TTL_SECONDS` | 조회와 AI 다운로드 URL 수명, 기본 900초 |
| `SAEROK_MAX_IMAGE_BYTES` | 사진 크기 상한, 기본 20MB. 사진 업로드 경로의 본문 상한은 이 값 + 1 MiB다([요청 본문 크기 상한](#요청-본문-크기-상한)) |

## 평가와 리포트 API

[API 명세 5~8절](../docs/architecture/api-spec.md) 중 작업 C가 맡은 보호자 평가, 회차 목록,
리포트와 변경 제안이다. 회차 생성(5-1)과 보충 카드(5-3)는 작업 B, 생애 정보와 프로필은
작업 A가 맡는다. 라우트는 `app/api/routes/evaluations.py`, `app/api/routes/reports.py`,
서비스는 `app/services/` 아래 `session_status.py`, `evaluations.py`, `reports.py`,
`proposals.py`, `visit_report_generator.py`에 있다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `GET` | `/api/v1/profiles/{profileId}/visit-sessions` | 5-4 회차 목록. 최근 회차부터, `limit` 기본 20, 최대 100 |
| `POST` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 6-1 보호자 평가 저장. `201` |
| `GET` | `/api/v1/visit-sessions/{sessionId}/evaluation` | 6-4 보호자 평가 조회 |
| `GET` | `/api/v1/profiles/{profileId}/reports` | 7-1 리포트 기록. 리포트가 저장된 회차만, 면회 사진 포함 |
| `GET` | `/api/v1/visit-sessions/{sessionId}/report` | 7-2 리포트 |
| `GET` | `/api/v1/visit-sessions/{sessionId}/proposals` | 7-3 변경 제안 |
| `POST` | `/api/v1/visit-sessions/{sessionId}/proposals/review` | 7-4 변경 제안 확인 |

- `sessionStatus`는 저장하지 않고 `load_visit_session`(`app/services/session_status.py`)이
  평가, 음성 분석 작업과 리포트로 계산한다. `participantCount`, `analysisId`는 가장 최근
  작업의 값이다.
- 6-1은 평가 전 회차에만 저장한다(`EVALUATION_ALREADY_SUBMITTED`(409)). 회차 행을
  `FOR UPDATE`로 잠가 동시 제출을 한 번만 받는다. 카드 평가는 `review_reaction`에 쓰고
  쓰지 않은 카드는 `notUsed`, 답하지 않은 카드는 `null`이다.
- `mood`는 만족도로 계산하고(1~2 `hard`, 3 `normal`, 4~5 `good`), `visitDate`는
  `started_at`의 한국 시간 날짜다. 7-1과 7-2는 면회 사진이 있을 때만 사진 저장소에서 조회
  URL을 만든다. URL을 만들지 못하면 7-2는 503이지만, 7-1은 썸네일 때문에 목록이 열리지 않으면
  안 되므로 그 항목만 `photo: null`로 담고 `report_list_photo_url_failed` 경고 로그를 요청마다
  한 번 남긴다(실패 수와 `errorCode`만).
- 7-4는 프로필 행과 회차 행을 차례로 잠근 한 트랜잭션에서 모든 제안을 `settled`로 바꾸고,
  승인한 생애 정보 제안은 요청의 `title`, `content`로 생애 정보를, 승인한 주제 제안은 요청의
  `action`으로 `topic_feedback`을 만든다. 제안 값은 바꾸지 않는다. 제안이 없는 회차에 빈
  요청을 보내면 아무것도 바꾸지 않고 `200`이다(명세 미정 사항 2).
- 주제 제안 승인이 하나라도 있는 7-4는 다음 카드 생성(4-1)에서 주제를 고르는 기준을 바꾸므로
  2-4, 2-7, 2-9와 같이 `card_sets.mark_stale`을 부른다. 카드를 만드는 중이면
  `CARD_GENERATION_IN_PROGRESS`(409)로 거절하고 아무것도 저장하지 않으며, 아니면 아직 면회에 안
  쓴 완료 묶음에 `stale_at`을 남긴다. 생애 정보만 승인한 확인은 이야기 추가(2-6)와 같아서, 모두
  거절한 확인과 함께 부르지 않는다. 리포트 저장(8-3)과 서로 기다리지 않게 프로필을 잠그기
  전에 리포트가 있는지 먼저 본다.
- 리포트 생성기(8-3)는 요청 조립(이름, 성별, 생년월일 제외) → 생성 함수 호출(트랜잭션 밖,
  별도 스레드) → 응답 검증 → 리포트, 카드 요약, 변경 제안 저장과 작업 `completed`(한
  트랜잭션) 순서다. 검증에 걸리면 아무것도 저장하지 않고 작업을 `INVALID_AI_RESPONSE`로
  실패시킨다.
- 생성 함수는 AI 서버의 HTTP API가 아니라 `ai/`의 `report_generation.generate_report`와
  `proposal_generation.generate_proposals`를 차례로 부르고 `common.visit_report.combine`으로
  합친다(`app/workers/speech_analysis.py`의 `report_generator`). 요청과 응답 JSON은 8-3과 같다.
  함수 호출이어도 그 안에서 전사문을 포함한 요청을 외부 ML API(엘리스)로 보낸다.
  생성 함수의 실패 코드는 기존 작업 실패 코드로 바꾼다: `LLM_UNAVAILABLE` →
  `AI_SERVER_UNAVAILABLE`, `GENERATION_FAILED`와 `INVALID_REQUEST` → `AI_SERVER_ERROR`.
- 생성 오류 구분(#143): 모델 호출의 연결 실패와 시간 초과는 `AI_SERVER_UNAVAILABLE`(재시도
  가능), 그 밖의 호출 실패(예: 400 응답)와 잘린 응답, JSON 처리 오류, 응답 형식 불일치는
  `AI_SERVER_ERROR`다. 둘 다 아무것도 저장하지 않는다. 카드 요약, 이야기 후보와 주제 조정이
  모두 0건인 응답은 실패가 아니라 정상 완료다(리포트 저장, 작업 `completed`). 잘린 응답만 따로
  나누는 실패 코드는 없다. 실제 출력 한도에 닿았을 때 SDK가 던지는 예외 종류는 실측하지
  않았고, 테스트는 모델 호출 자리(`invoke_structured`)에 그런 예외를 넣어 확인한다.
  모델이나 SDK가 남긴 오류 메시지는 작업 실패에 담지 않는다.
- 출력 한도(`max_tokens`)는 BE가 넘기지 않고 `ai/common/llm.py`의 `ChatConfig` 기본값 16000을 쓴다.
  BE의 전체 시간 제한과 늦은 결과 저장 방지는 출력 한도와 관계없이 적용된다.
- 11/3 로컬 전환본은 카드와 리포트의 기본 모델을 `gpt-6-luna`로 맞췄다. 운영 적용은 별도다. 현재 구현 (2026-11-09 기준): 이 기본값은 11/5 운영 배포부터 들어갔고, 운영 기록(#187의 11/5 운영 배포 기록)에는 그날 운영 서버에서 `gpt-6-luna`로 카드 12장을 만든 기록이 있다.
  기존 `.env`의 `SAEROK_CARD_GENERATION_MODEL`, `SAEROK_REPORT_GENERATION_MODEL`에
  이전 모델이 명시돼 있으면 그 값이 우선한다. 적용할 때 두 값을 함께 확인한다.
  이미 접수한 카드 작업의 모델은 DB에 저장된 값을 유지하므로 이전 모델 주소도 남긴다.
- 전체 시간 제한: 요청 조립부터 검증까지 `SAEROK_REPORT_GENERATION_TIME_LIMIT_SECONDS`(기본
  600초)를 넘으면 작업을 `AI_SERVER_TIMEOUT`으로 실패시킨다. 생성 함수의 호출당 timeout(300초)은
  응답 대기 제한이라 스트리밍이 이어지면 전체 시간이 늘어나므로, BE가 전체 마감을 따로 둔다.
  `generatingReport`로 바꿀 때 임대(기본 900초)를 새로 잡고, 제한 시간은 임대보다 60초 이상
  짧아야 한다(저장과 완료 처리 여유). 생성 함수는 daemon 스레드에서 돌고 worker는 마감까지만
  기다린다. 동기 함수라 스레드를 멈출 수는 없으므로, 리포트와 변경 제안 호출 직전마다 마감을
  확인해 마감 뒤 새 외부 호출을 하지 않는다. worker가 시간 초과를 확정하면 마감에 취소를
  표시하므로, 스레드가 읽는 시계가 해상도 차이(Windows)로 아직 마감 전이어도 다음 호출 전에
  멈춘다. 이미 시작한 호출 하나는 끝날 때까지 남을 수 있고, 시간 초과 확정 전에 마감 확인을
  통과한 변경 제안 호출도 시작될 수 있다(결과는 버리고 저장하지 않는다).
- 전사 기한과 외부 전송: `generatingReport`로 바꿀 때(최초 생성, 6-5 재요청, 인계 임대가 끝난 작업의 이어받기 모두) 남은 전사
  기한이 새 임대 시간 이상이어야 한다. 아니면 생성을 시작하지 않고 worker 정리에서 전사를
  지우며 `TRANSCRIPT_EXPIRED`로 끝낸다. 임대가 제한 시간보다 60초 이상 길므로 생성 중 새 외부
  호출은 전사 기한 전에만 시작된다. 변경 제안 호출(전사문의 두 번째 외부 전송) 직전에는 마감과
  함께 DB의 작업 행을 다시 읽는다. 행이 없거나(계정, 프로필, 회차 삭제의 연쇄 삭제)
  `generatingReport`가 아니거나 임대가 끝났으면 `WORKER_LEASE_EXPIRED`, 전사가 지워졌거나 기한이
  지났으면 `TRANSCRIPT_EXPIRED`로 멈추고 보내지 않는다. 이 확인은 생성 스레드가 worker 연결로
  이벤트 루프에서 실행하며, `speech_analysis` 로거에 작업 ID와 멈춘 이유만 info로 남긴다.
- 늦은 결과 저장 방지: 마감 뒤 도착한 결과는 아무도 읽지 않고, 생성 함수는 DB를 쓰지 않는다.
  결과가 와도 저장 직전에 마감을 다시 확인한다. 저장 트랜잭션은 먼저 작업 행을
  `FOR UPDATE`로 잠그고 `generatingReport`이며 `lease_expires_at > now()`일 때만 저장한다.
  아니면(임대가 끝났거나 다른 worker가 실패 처리함) 아무것도 저장하지 않고
  `WORKER_LEASE_EXPIRED`다. 리포트 저장과 작업 `completed`(전사문 삭제)는 같은 트랜잭션이라,
  잠금을 잡은 동안 임대 만료 정리는 기다렸다가 끝난 작업을 건너뛴다.
- 작업 상태는 끝나면(`completed`, `failed`) 다시 바꾸지 않는다. `completed`는
  `generatingReport`에서만 바뀌고, 먼저 남은 실패 코드는 늦게 끝난 처리가 덮지 않는다.
  자동 재시도는 없다. 실패한 리포트는 남은 전사의 보관 기한 안에서 6-5로 수동 재요청한다.
  전사가 없거나 만료됐으면 기기 녹음을 6-2로 다시 제출한다. 이전 실패 작업은 그대로 두고
  새 작업 ID를 만든다. 상세 검사와 제한은 [분석 복구](docs/speech-recovery.md)를 따른다.
- 8-3 응답 검증의 보수적인 임시 정책(AI 담당자와 합의 필요): `reaction`이 `notUsed`이거나
  `null`인 카드에 `less`, `exclude`를 제안하면 응답 전체를 실패로 본다. PM 결정(2026-09-19)은
  그 사실"만으로" 제안하지 않는 것인데, 백엔드는 제안의 근거를 판별할 수 없기 때문이다.

| `errorCode` | HTTP | 설명 |
| --- | --- | --- |
| `VISIT_SESSION_NOT_FOUND` | 404 | 회차가 없거나 다른 계정의 회차 |
| `EVALUATION_NOT_FOUND` | 404 | 6-4. 평가 전 |
| `REPORT_NOT_FOUND` | 404 | 7-2 ~ 7-4. 리포트 저장 전 |
| `EVALUATION_ALREADY_SUBMITTED` | 409 | 6-1. 이미 평가함 |
| `PROPOSAL_ALREADY_REVIEWED` | 409 | 7-4. 이미 확인한 회차 |
| `CARD_GENERATION_IN_PROGRESS` | 409 | 7-4. 주제 제안 승인이 있는 확인인데 카드를 만드는 중. 카드 생성이 끝난 뒤 다시 보낸다 |
| `INVALID_CARD_REVIEW` | 422 | 6-1. 선택 카드가 아니거나, 중복이거나, `wasUsed`와 `caregiverReaction`의 짝이 틀림 |
| `INVALID_PROPOSAL_REVIEW` | 422 | 7-4. `pending` 제안이 빠졌거나 다른 회차의 제안이거나 중복 |
| `IMAGE_STORAGE_UNAVAILABLE`, `IMAGE_STORAGE_NOT_CONFIGURED` | 503 | 7-2. 면회 사진의 조회 URL을 만들지 못함 |

프로필의 짧은 음성 입력은 면회 작업을 만들지 않고 6-6으로 처리한다.
[짧은 음성 전사](docs/short-speech-transcription.md)에 요청 형식, 임시 파일 삭제와 남은 처리 시간 측정을 정리했다.

worker가 작업 실패로 남기는 코드: `INVALID_AI_RESPONSE`, `AI_SERVER_TIMEOUT`,
`AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `REPORT_ALREADY_GENERATED`(이미 리포트가 있는 회차),
`EVALUATION_REQUIRED`(평가 없는 회차. 6-2가 막으므로 정상 흐름에서는 생기지 않음),
`WORKER_LEASE_EXPIRED`(임대가 끝났거나 변경 제안 호출 전에 작업이 끝남),
`TRANSCRIPT_EXPIRED`(전사 기한이 지났거나 남은 기한이 임대 시간보다 짧아 생성을 시작하거나
이어 갈 수 없음).

### 다른 작업과 병합한 뒤 정리할 것

- 작업 B(PR #99)의 `load_visit_session`: `VisitSession`은 B의 모델(`app/schemas/visit_session.py`)
  하나로 합쳤다. B의 5-1, 5-3은 아직 상태를 `evaluationPending`으로 고정한 임시
  `load_visit_session`(`app/services/visit_sessions.py`)을 쓴다. 작업 B와 확인한 뒤
  `session_status.load_visit_session`을 쓰게 한다.
