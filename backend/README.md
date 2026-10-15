# BE 영역

담당 리더: 김민혁. Python 3.12와 FastAPI의 상태 확인, 공통 오류 및 요청 로그, 구글 인증 API와 PostgreSQL 개발 스키마가 있으며 계정, 프로필과 생애 정보는 PostgreSQL에 저장한다. 실제 STT와 VLM은 아직 연결되지 않았다.

STT는 GPU 서버, 사진 설명과 카드 및 리포트 생성은 ML API를 활용하는 방향이다. 10월 6일 BE 논의와 [ADR-006의 후속 정정](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md#현재-적용할-방향-2026-10-11-정정)을 따른다. 생성 함수와 HTTP의 구체적인 연결은 각 담당 PR에서 맞춘다. RTX 3060 Ti는 개발용이며 시연 장비 사양은 실험 후 정한다. 실제 사용자 자료의 외부 전송 조건은 별도 확인한다.

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

이후 명령은 `backend/`에서 실행한다. 의존성과 가상 환경은 `uv`, 테스트는 `pytest`로 관리한다.

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

컨테이너 실행과 EC2 개발 서버 배포 절차는 [컨테이너 실행과 개발 서버 배포](docs/deployment.md)에 둔다. 개발 서버는 develop에 병합된 코드와 합성 데이터만 쓴다. HTTPS는 sslip.io와 Caddy로 임시 구성하며, 공개 범위와 AI 서버 연결은 정하지 않았다.

| 확인 항목 | 위치 / 현재 범위 |
| --- | --- |
| 생존 확인 | `GET /health/live` |
| 준비 상태 | `GET /health/ready`. 외부 의존성이 없는 골격의 상태만 확인 |
| API 문서 | 실행 후 `http://127.0.0.1:8000/docs` |
| 오류 테스트 | [test_errors.py](tests/test_errors.py)의 404, 422, 500, 503 응답 |
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

PR #32의 500 응답 헤더와 완료 로그 보완이 develop에 반영됐다. 모델과 저장소가 연결되면 readiness에도 실제 의존성 점검을 추가한다. 계정은 PostgreSQL에 저장하지만 세션 폐기 목록은 아직 프로세스 메모리 구현이다.

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
| 처리 함수 (`JobProcessor`) | `async def process(connection, job)`. AI 서버 호출과 응답 검증은 트랜잭션 밖에서 하고 결과 저장만 트랜잭션으로 묶는다 | 음성 `SpeechAnalysisProcessor`. 카드 생성과 사진 분석은 각 담당이 만든다 |

- `Worker`는 한 번 돌 때 임대 만료 정리 → 작업 하나 임대 → 처리 순서로 실행한다. 처리 함수가 `AppError`를 내면 그 `error_code`로, 그 밖의 예외는 대기열의 기본 실패 코드로 작업을 실패시킨다. 예외 메시지는 로그에 남기지 않고 종류만 남긴다.
- 임대 시간 안에 끝나지 않은 작업은 다음 정리에서 `WORKER_LEASE_EXPIRED`로 실패한다. 음성의 업로드 단계에서 멈춘 작업은 접수 전 실패와 같으므로 지워서 다시 제출할 수 있게 한다. 자동 재시도는 하지 않는다.
- 결과를 저장해 작업을 끝낼 때는 임대도 함께 지운다. `card_sets`는 `completed`로 바꿀 때 `lease_expires_at = NULL`이어야 하고(CHECK `card_sets_lease_check`), `photos`는 `processing`일 때만 임대가 있다(CHECK `photos_lease_check`).
- 카드 생성 처리 함수가 AI에 보낸 요청을 남기며 실패시키려면 `CardGenerationQueue.fail(..., generation_input=...)`을 직접 부르고 정상 반환한다.
- **`PhotoAnalysisQueue`와 worker 연결은 합성 사진만 있는 개발 환경에서 먼저 구현하고 검증한다.** 지금은 `pending`인 프로필 사진을 모두 가져온다. 실제 사용자 사진을 처리하기 전에는 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)에 따라 유효한 계정별 분석 동의 조건, 분석하지 않는 사진의 상태와 철회 시 작업 중단을 구현하고 검증해야 한다. 테스트 통과만으로 실제 사용자 사진을 처리하도록 개방하지 않는다.
- 새 worker의 실행 진입점은 [speech_analysis.py](app/workers/speech_analysis.py)처럼 `run_worker_main`으로 만든다. `--once`면 대기 작업을 최대 하나 처리하고 끝낸다.

## 담당과 다음 결정

| 범위 | BE 작업 / 함께 정할 내용 |
| --- | --- |
| 모델 실행 | AI와 입력 형식, 모델 로딩, 자원 해제, STT 및 화자 처리 파이프라인 검토 |
| 앱 연동 | [공통 데이터 계약](../docs/architecture/data-contracts.md)의 입력 검증, 응답과 상태 전달 |
| 작업 처리 | 타임아웃, 재시도 상한, 취소, 장애 복구와 수동 전환 |
| 데이터 저장 | 서버 저장 항목, 단말 보관 여부, 접근 권한, 보관 기간과 삭제 조건을 제안. PostgreSQL 개발 스키마와 Alembic은 반영됐으며 앱의 실제 저장 연결은 후속 작업 |
| 운영 | 개발용 RTX 3060 Ti에서 AI와 처리 조건을 측정하고 PM과 시연 장비 및 운영 방식 결정. 모델 파일 배포와 무결성 확인 |
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

이 흐름은 구현해야 할 목표다. BE가 데이터별 저장 위치, 단말 보관 여부, 기간과 접근 및 삭제 조건을 PR로 정리하고 FE, AI와 PM이 함께 확인한다. DB와 GPU를 같은 장비에 배치할지도 미정이다. 녹음 원본은 STT 완료 후 즉시 삭제하며 업로드 후 최대 24시간 제한을 유지한다. 등록 사진과 AI 분석용 임시 사본은 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#등록-사진과-분석용-임시-사본의-구분)에서 구분한다. PR #92는 병합됐고 사진 보관과 AI 분석을 가입 시 선택 동의로 받아 계정별로 저장하는 방향은 2026-10-14 PM이 확정했지만, 동의 및 삭제 연결과 실제 사용자 자료 처리 검증은 남아 있다. 실제 사용자 자료와 마스킹한 실제 자료는 개발 골격의 테스트에 사용하지 않는다.

직접 식별정보와 허용 목록 밖의 원본은 외부 AI로 보내지 않는다. 데이터 경로 변경 전 [법률 문서](../docs/legal/README.md), [동의 및 임시 처리 ADR](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md)과 데이터 흐름을 갱신한다. 외부 업체의 이름, 국가, 목적, 항목, 보유기간과 자체 학습 여부가 정해지기 전에는 실제 사용자 자료로 호출하지 않는다.

## 로그인 API

로그인 API는 PR #47로 develop에 반영됐다. 근거는 [ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)이다. 구글 ID 토큰 직접 검증 방향에 대한 PM 동의와 개인정보 저장 항목의 검토안은 구분한다. ADR-007은 `proposed`로 유지하며, API 구현이 저장 범위 전체의 확정을 뜻하지 않는다. 응답의 `authProvider`와 nullable `email`은 [공통 Account 계약](../docs/architecture/data-contracts.md#계정-account)에 맞춘다.

인증은 구글 소셜 로그인 한 가지를 사용하고 자체 아이디와 비밀번호는 받지 않는다. 백엔드는 구글 공개키로 ID 토큰을 직접 검증하며 Firebase Auth를 사용하지 않는다.

### 흐름

다음은 목표 흐름이다. 서버 엔드포인트는 아래 표에 있고, 앱의 세션 보관과 재실행 시 복원은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)의 후속 보완 항목이다.

    앱 시작
    → (세션 있음) GET /auth/me → 홈
    → (세션 없음) 구글 로그인 버튼 → POST /auth/google
        → status=authenticated  → 홈
        → status=consentRequired → 동의 화면 → POST /auth/consent → 홈

    프로필 설정의 선택 동의 변경 → PATCH /auth/me/consents
    프로필 설정의 로그아웃 → POST /auth/logout → 로그인 화면
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

요청과 응답의 정확한 형태는 서버 실행 후 `http://127.0.0.1:8000/docs` 와 `openapi.json` 에서 확인한다. 구현 전 API를 포함한 전체 명세는 [API 명세](../docs/architecture/api-spec.md)를 따른다.

`POST /auth/google` 은 `{"idToken": "..."}` 를 받고 `status` 로 갈라지는 두 응답 가운데 하나를 준다.

사진 보관과 AI 분석을 가입 화면에서 선택 동의로 받는 2026-10-14 PM 결정은 [보관 기준과 후속 작업](#보관-기준과-후속-작업)에 기록했다. 아래 네 항목의 API 예시는 현재 구현이며 새 두 항목은 아직 포함하지 않는다.

아래 동의 목록은 현재 BE 구현의 예시다. [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)에서 알림 수신을 선택 동의로 옮겨 공통 계약과 FE의 기준에 맞췄다. 알림을 거부해도 필수 동의를 완료하면 계정이 생성된다.

```json
{
  "schemaVersion": 1,
  "status": "consentRequired",
  "registrationToken": "...",
  "expiresIn": 600,
  "consentVersion": "2026-09-06",
  "requiredConsents": ["serviceData", "sensitiveData"],
  "optionalConsents": ["serviceImprovement", "pushNotification"]
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

`POST /auth/consent` 는 `registrationToken`, `consentVersion`, `consents`(네 항목 모두 boolean)와 선택값 `displayName` 을 받고 `status=authenticated` 응답을 준다.

`POST /auth/logout` 은 요청 본문을 받지 않고 `Authorization` 헤더의 세션만 본다. `DELETE /auth/me` 는 탈퇴 이유를 선택 본문(`reasons`, `otherText`)으로 받으며, 고르지 않았으면 본문 없이 보낸다.

`PATCH /auth/me/consents` 는 선택 동의(`serviceImprovement`, `pushNotification`) 중 보낸 항목만 바꾼다([API 1-6](../docs/architecture/api-spec.md#1-6-patch-authmeconsents--신규)).

- 직전 동의 이력을 복사해 보낸 항목만 바꾼 이력 행을 더하며 약관 버전은 직전 이력의 값을 쓴다. 같은 계정의 동시 변경이 서로를 덮지 않도록 계정 행을 잠근 뒤 더한다.
- 값은 `true`, `false`만 받는다. 필수 동의(`serviceData`, `sensitiveData`)를 보내면 `REQUIRED_CONSENT_NOT_CHANGEABLE`(422), 본문이 비었거나 `null`을 보내면 `INVALID_REQUEST`(422)다.
- 로그아웃은 계정이 이미 없어도 세션을 폐기한다. 같은 계정의 다른 세션은 그대로 둔다.
- 탈퇴는 `users` 행을 지운다. 같은 계정의 다른 세션은 이후 `ACCOUNT_NOT_FOUND`(404)로 거절된다. 같은 구글 계정으로 다시 로그인하면 지운 계정이 되살아나지 않고 `status=consentRequired`를 받는다.
- DB의 `ON DELETE CASCADE`로 동의 이력, 프로필과 그 아래의 모든 기록이 함께 지워지고, 사진과 음성 원본의 객체 키는 trigger가 S3 삭제 대기열(`storage_deletion_request_queue`)에 넣는다. [API 명세 1-5](../docs/architecture/api-spec.md#1-5-delete-authme--수정)의 범위다. 대기열의 S3 객체를 실제로 지우는 처리는 아직 없다(아래 "아직 정하지 않은 것").
- 탈퇴 이유는 계정 삭제와 같은 트랜잭션에서 `withdrawal_feedback(reasons, other_text)`에 넣고 계정 ID는 넣지 않는다. `reasons`는 1개 이상이고 중복을 받지 않으며, `otherText`는 `other`를 고른 경우에만 비우지 않고 보낸다. 조건이 맞지 않으면 `INVALID_REQUEST`(422)이며 계정을 지우지 않는다. `otherText`는 로그에 남기지 않는다.

### 세션

[ADR-007의 구현 상태](../docs/architecture/decisions/ADR-007-google-social-login.md#현재-구현과-후속-작업)에 현재 서버 구현과 앱의 후속 작업을 나누어 기록했다.

- 형식: HS256 으로 서명한 JWT. 리프레시 토큰을 따로 두지 않는다. 세션마다 무작위 `jti` 를 넣고, `jti` 가 없는 세션은 `UNAUTHENTICATED` 로 거절한다.
- 수명: `SAEROK_SESSION_TTL_SECONDS`(기본 1시간).
- 폐기: 로그아웃과 탈퇴는 그 세션의 `jti` 를 만료 시각까지 폐기 목록(`InMemorySessionRevocationStore`)에 올린다. 폐기한 세션은 만료 전이라도 `UNAUTHENTICATED`(401)다. 목록에는 `jti` 와 만료 시각만 두고 계정 식별자와 토큰 원문은 두지 않는다. 프로세스 메모리에만 있어 서버를 다시 시작하면 비고, 그 전에 폐기한 세션은 만료까지 다시 통과한다. 서버를 여러 개 띄우면 서로의 목록을 보지 못한다.
- 갱신 방향: 앱이 사용자에게 매번 로그인 버튼을 누르게 하지 않고 새 구글 ID 토큰을 받아 `POST /auth/google`을 다시 호출하도록 연결한다. 앱의 자동 재인증은 PR #50 후속 작업이며 아직 완료되지 않았다. 서버가 보관하는 갱신 자격증명은 없다.
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
- **`aud` 로 쓸 클라이언트 ID** — `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 웹 클라이언트 ID가 된다. FE 가 쓰는 값을 확인해서 `SAEROK_GOOGLE_CLIENT_IDS` 에 넣는다. Google Cloud Console 에 패키지명 `com.saelog.app` 과 디버그 및 릴리스 SHA-1 등록이 선행되어야 한다. 쉼표 구분 설정의 읽기 보완은 PR #51에서 다룬다.
- **세션 폐기 목록 저장소** — 계정은 PostgreSQL로 옮겼지만 폐기 목록은 프로세스 메모리에 남아 있다. DB로 옮기려면 스키마에 테이블을 더하는 새 migration이 필요하며, 영향이 만료 시각(기본 1시간)까지로 작아 보류했다.
- **재동의** — 약관 버전이 올라갔을 때 기존 계정에 다시 동의를 받는 흐름은 넣지 않았다. 응답의 `account.consent.consentVersion` 으로 앱이 비교할 수는 있다.
- **약관 본문 제공과 로그인 유지** — 약관 본문, 버전과 필수 여부의 서버 관리, 앱 재실행 시 세션 복원과 만료 후 자동 재인증은 PR #50에 남긴 후속 요청이다. 현재 API가 약관 본문까지 제공하거나 앱이 로그인 상태를 복원하는 것으로 읽지 않는다.
- **탈퇴와 계정 삭제** — `DELETE /auth/me`는 `users` 삭제의 `ON DELETE CASCADE`로 계정 아래의 서버 기록을 모두 지운다. [API 명세 1-5](../docs/architecture/api-spec.md#1-5-delete-authme--수정)의 범위이며, [법률 문서의 PM 검토안](../docs/legal/README.md#구글-로그인-데이터-이동에-대한-pm-검토안)이 적은 범위(인증 제공자, `sub`, 내부 계정 식별자와 동의 이력)보다 넓다. 이 범위의 법률 검토, S3 삭제 대기열의 처리, 백업과 단말 자료의 삭제 범위, 탈퇴 후 보관 기간과 재가입 허용 여부는 정해지지 않았다. 지금 코드는 재가입을 막지 않으며, 이것으로 재가입 허용을 정한 것은 아니다. ADR-007의 재검토 조건(탈퇴 시 삭제 범위, 세션 형식 변경)에 해당한다.

## 프로필과 생애 정보 API

[API 명세 2절](../docs/architecture/api-spec.md#2-프로필)의 2-1~2-4, 2-6~2-8이다. 온보딩의 `마치기`는 세부 정보를 2-4로 저장한 뒤 작업 B의 4-1로 첫 카드 생성을 요청한다. 별도의 2-5 API는 사용하지 않는다. 라우트는 [profiles.py](app/api/routes/profiles.py)와 [life_facts.py](app/api/routes/life_facts.py), 저장은 [services/profiles.py](app/services/profiles.py)와 [services/life_facts.py](app/services/life_facts.py)에 있다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `GET` | `/api/v1/profiles` | 현재 계정의 프로필 목록. 만든 순서이며 입력 중인 프로필도 담는다 |
| `POST` | `/api/v1/profiles` | 기본 정보로 프로필 생성. `201`, `setupStatus`는 `inProgress` |
| `GET` | `/api/v1/profiles/{profileId}` | 프로필, 생애 정보와 프로필 사진 |
| `PATCH` | `/api/v1/profiles/{profileId}` | 기본 정보와 세부 정보 네 항목 중 보낸 필드만 수정 |
| `DELETE` | `/api/v1/profiles/{profileId}` | 프로필 하나와 그 아래 기록 삭제. `204` |
| `POST` | `/api/v1/profiles/{profileId}/life-facts` | 일대기에서 생애 정보 추가. `201` |
| `PATCH` | `/api/v1/life-facts/{factId}` | 생애 정보 중 보낸 필드만 수정 |

- `setupStatus`는 저장하지 않고 `card_sets` 행이 있는지로 계산한다.
- 계정당 프로필은 입력 중인 것을 포함해 3개까지다. DB 제약이 없으므로 같은 트랜잭션에서 계정 행을 `FOR UPDATE`로 잠근 뒤 세어, 동시 요청에도 넘지 않는다. 넘으면 `PROFILE_LIMIT_EXCEEDED`(409)다.
- 2-4의 세부 정보 네 항목은 `null`을 보내면 지운다. 이름, 성별, 생년월일과 `condition`은 `null`로 지울 수 없다. `condition`을 보낼 때 `stage`는 항상 보내며, `symptomNote`를 빼면 저장된 메모를 그대로 두고 `null`을 보낼 때만 지운다. 본문이 비어 있으면 바꾸지 않고 현재 프로필을 돌려준다.
- 빈 문자열과 공백만 있는 값은 이름, 세부 정보와 생애 정보의 제목과 내용에서 `INVALID_REQUEST`(422)다. DB CHECK도 막지만 요청 검증이 먼저 거절한다.
- 다른 계정의 자원과 없는 자원은 같은 `PROFILE_NOT_FOUND` 또는 `LIFE_FACT_NOT_FOUND`(404)다.
- 프로필 삭제는 `ON DELETE CASCADE`로 생애 정보, 사진, 주제와 대화 카드, 면회 기록을 함께 지우고, 사진과 음성의 객체 키는 trigger가 S3 삭제 대기열에 넣는다. 카드와 주제가 함께 있는 프로필의 삭제와 탈퇴는 테스트로 확인했다. 대기열을 처리해 S3 원본을 지우는 코드는 아직 없다. 처리 중인 작업이 있는 프로필의 삭제는 미정이다([API 명세 미정 사항](../docs/architecture/api-spec.md#미정-사항) 8).
- 응답의 `photos`는 프로필 사진(`session_id IS NULL`)을 올린 순서대로 담고, 사진마다 `storage.create_download`로 `imageUrl`을 만든다. 사진이 없으면 사진 저장소를 부르지 않으므로 버킷 설정 없이도 응답한다. 업로드는 아래 [사진 저장 (S3)](#사진-저장-s3)의 3-1이다.
- 실제 사용자 사진을 받기 전에는 계정별 동의 확인과 철회 처리를 구현하고 검증한다(후속 3). 현재 업로드와 조회 테스트는 합성 사진과 메모리 저장소를 사용하며 실제 S3 업로드는 미검증이다.
- `create_life_fact(connection, *, profile_id, title, content, source_proposal_id=None)`는 7-4(작업 C)도 쓴다. 트랜잭션을 열지 않으므로 부르는 쪽의 트랜잭션에 묶이고, 소유 확인은 부르는 쪽이 한다.

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
`errorCode`만 반환한다. `sttCompleted`는 AI 응답 검증과 S3 원본 삭제까지 끝났다는
뜻이며 리포트 완료는 아니다.

worker는 PostgreSQL에서 `queued` 작업을 행 잠금으로 하나씩 가져오고 S3 Presigned GET
URL을 만들어 AI 서버의 기존 동기 `POST /internal/v1/speech-analyses`를 호출한다.
`participantCount`는 `speakerCount`로 전달한다. STT 응답 뒤 S3 원본을 즉시 삭제하고,
리포트 생성과 저장까지 성공해야 작업을 `completed`로 바꾼다.

현재 코드에는 작업 저장소, S3 어댑터, 제출 및 조회 API와 독립 worker 실행 진입점이
있다. worker는 STT 뒤 같은 작업에서 리포트 생성기(8-3, [평가와 리포트 API](#평가와-리포트-api))로
리포트와 변경 제안을 저장한 뒤에만 `completed`로 바꾼다. 전사문은 리포트 생성
입력으로 작업에 임시 저장하며, STT 완료 후 24시간 안에 리포트를 저장하지 못하면 지우고
작업을 `failed`(`TRANSCRIPT_EXPIRED`)로 바꾼다. worker는 위의 공통 골격으로 동작하며,
임대 시간 안에 끝나지 않은 작업은 `WORKER_LEASE_EXPIRED`로 실패시킨다. 자동 재시도와
취소는 아직 없으며 실패를 숨겨 재실행하지 않는다.

API 서버와 별도 터미널에서 worker를 실행한다.

```bash
bash ./scripts/run_speech_worker.sh
```

대기 작업 하나만 처리하고 종료하는 통합 확인은 다음과 같다.

```bash
bash ./scripts/run_speech_worker.sh --once
```

### 음성 분석 설정

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_AI_SERVER_URL` | 내부 AI 서버 주소, 기본 `http://127.0.0.1:8001` |
| `SAEROK_AI_SERVER_TIMEOUT_SECONDS` | worker가 AI 동기 응답을 기다리는 제한, 기본 600초 |
| `SAEROK_SPEECH_AUDIO_S3_BUCKET` | 비공개 음성 임시 저장 버킷. DB와 함께 설정해야 업로드 API 활성화 |
| `SAEROK_SPEECH_AUDIO_S3_REGION` | S3 리전, 기본 `ap-northeast-2` |
| `SAEROK_SPEECH_AUDIO_S3_PREFIX` | 개인정보를 넣지 않는 객체 키 접두사 |
| `SAEROK_SPEECH_AUDIO_S3_ENCRYPTION` | 서버 측 암호화 `AES256` 또는 `aws:kms` |
| `SAEROK_SPEECH_AUDIO_PRESIGNED_TTL_SECONDS` | AI 다운로드 URL 수명, 기본 900초 |
| `SAEROK_SPEECH_AUDIO_RETENTION_SECONDS` | 원본 최종 삭제 기한, 최대 86400초 |
| `SAEROK_MAX_AUDIO_BYTES` | BE와 AI가 함께 맞출 업로드 크기 상한 |
| `SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS` | worker 작업 임대 시간 |
| `SAEROK_SPEECH_WORKER_POLL_SECONDS` | 대기 작업이 없을 때 조회 간격, 기본 2초 |

S3 Lifecycle의 최대 24시간 삭제는 애플리케이션 설정만으로 만들어지지 않는다. 버킷
운영 설정에서 별도로 적용하고 확인해야 한다. 정상 경로에서는 Lifecycle을 기다리지 않고
STT 직후 삭제한다. 음성, 전사문, 원래 파일명, Presigned URL과 객체 키를 요청 로그와
오류 응답에 남기지 않는다.

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

- 프로필당 5장이다(`PHOTO_LIMIT_EXCEEDED`, 409). 면회 사진은 세지 않는다. 큰 파일을 S3에 올린 뒤에야 거절하지 않도록 올리기 전에 한 번 세고, 행을 넣을 때 프로필 행을 `FOR UPDATE`로 잠근 뒤 다시 센다. S3 업로드 동안에는 잠그지 않는다.
- 행을 넣지 못하면(상한 경합, 그 사이 프로필 삭제, DB 오류) 올린 객체를 `storage.delete`로 지운다. 지우지도 못하면 객체 키를 `storage_deletion_request_queue`에 직접 넣는다. 행이 없어 trigger가 넣어 주지 않기 때문이다.
- 넣은 `pending` 행은 사진 분석 worker(8-4)가 가져갈 대상이지만, worker는 아직 연결하지 않았다(위 worker 절의 `PhotoAnalysisQueue`).
- 면회 사진과 다른 계정의 사진은 3-2에서 없는 사진과 같은 `PROFILE_PHOTO_NOT_FOUND`(404)다.

### 공통 처리 순서

아래는 3-1의 처리 순서이며 5-2도 같은 순서를 따른다. 합성 사진과 메모리 저장소로 검증했으며 실제 S3 업로드와 조회는 미검증이다.

프로필 사진(3-1)과 면회 사진(5-2)은 같은 어댑터로 저장한다. 라우트는 `ImageStorageDep`으로
[image_storage.py](app/services/image_storage.py)의 저장소를 받고, 업로드 전에
[image_validation.py](app/services/image_validation.py)의 `validate_image`로 검사한다.

    validate_image(파일, max_size_bytes=설정값)       # 413 IMAGE_TOO_LARGE, 422 INVALID_IMAGE_FORMAT
    → storage.object_key(photo_id=..., image=...)     # photos/{photoId}.jpg, 개인정보 없음
    → storage.upload(object_key=..., file=..., image=...)
    → photos 행 저장 (실패하면 storage.delete로 올린 객체를 지운다)
    → 응답의 imageUrl, imageUrlExpiresAt은 storage.create_download(object_key=...)

- 형식은 앱이 보낸 Content-Type이 아니라 파일 시그니처로 판단하며 JPEG와 PNG만 받는다.
- S3 오류는 `IMAGE_STORAGE_UNAVAILABLE`(503, 재시도 가능)이다. 객체 키와 S3 오류 본문은 응답과 로그에 넣지 않는다.
- 버킷이 설정되지 않았으면 사진이 필요한 순간에만 `IMAGE_STORAGE_NOT_CONFIGURED`(503)로 거절한다. 사진이 없는 프로필 조회는 그대로 동작한다.
- AI 서버에 넘기는 8-4의 `downloadUrl`도 같은 `create_download`로 만든다.
- 사진 메타데이터는 AI 분석과 주제 추천 입력에서 제외한다. 사진 파일 자체에서 EXIF를 제거하는 처리와 저장 정책은 별도 사항이며, 이 미결 항목을 메타데이터 입력 재허용으로 해석하지 않는다.
- DB에서 지운 사진의 객체 키는 trigger가 `storage_deletion_request_queue`에 넣지만, 대기열을 처리해 S3 객체를 지우는 코드는 아직 없다.

### 보관 기준과 후속 작업

PR #92의 문서는 병합됐다. 2026-10-14 PM이 정한 사진 보관과 AI 분석의 가입 시 선택 동의 및 계정별 저장 방식은 [ADR-001](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md#사진-보관과-ai-분석-동의-시점과-저장-방식)을 따른다.

- 사진 서버 보관과 AI 분석을 가입 화면의 별도 선택 동의로 받는다. 기존 `consent_records`에 두 항목을 추가하고 `current_consents`에서 최신 상태를 조회하도록 확장한다. 유효한 동의는 반복 요청하지 않으며 미동의, 철회 또는 기록 없는 계정이 기능을 사용하려고 할 때 필요한 동의를 받는다. 거부해도 가입과 사진 없는 기본 서비스는 이용할 수 있다.
- BE는 업로드 전에 보관 동의를, AI 작업 생성 전에 분석 동의를 각각 검사한다. 보관만 동의한 사진은 분석하지 않는다. 두 동의의 계정별 저장 방향은 확정됐지만 필드명, migration, 가입 및 동의 변경 API와 FE 연결, 철회 후 중단 및 삭제는 후속 구현이다.
- 현재 3-1 코드에는 사진 보관 동의 검사가 없고, 업로드한 사진은 모두 `pending`으로 저장한다. 이는 합성 사진을 사용하는 개발 단계의 구현 상태이며, 보관 또는 분석 동의를 없애기로 한 결정이 아니다. 실제 사용자 사진을 받기 전에는 위 동의 검사와 분석 대상 구분을 구현하고 검증한다.
- 등록 사진은 앨범, 일대기와 면회 기록 표시를 위한 보관 동의를 확인한 뒤 저장한다. 해당 사진 삭제, 보관 동의 철회, 프로필 삭제, 탈퇴 또는 보관 목적 종료 시 지체 없이 삭제한다.
- 현재 5-2 코드에도 사진 보관 동의 검사가 없다. 가입 시 계정별 동의를 받는 정책은 위 ADR-001로 확정했으며, 실제 사용자 사진을 받기 전 동의 조회와 미동의 차단 구현 및 검증이 남아 있다. 테스트 자료로 개발을 먼저 진행하는 기준은 유지한다.
- AI 분석은 별도 동의를 확인한다. 분석용 임시 사본은 처리 완료 후 즉시 삭제하고 해당 작업의 최초 임시 사본 생성부터 최대 24시간을 넘기지 않는다. 재시도로 기한을 연장하지 않는다.
- 분석 동의만 철회하면 분석을 중단하고 임시 사본을 삭제한다. 별도로 동의받은 보관 목적이 유지되는 등록 사진까지 자동 삭제하는 의미는 아니다.
- 사진 API의 동의 확인, 분석하지 않는 등록 사진의 상태, 철회 및 삭제 경로는 FE, BE와 AI가 계약에 반영할 후속 작업이다. 현재 API 명세의 모든 프로필 사진 자동 분석이 이 구분을 이미 구현한 것은 아니다.
- BE는 S3 삭제 대기열 실행과 삭제 결과 확인을, AI는 임시 사본의 기한 삭제를 구현해야 한다. 실제 사용자 사진을 받기 전에 동의 화면부터 원본 삭제까지 검증한다. 어댑터 제공, DB 행 삭제 또는 대기열 등록만으로 삭제 완료를 표시하지 않는다.

### 사진 저장 설정

| 환경 변수 | 설명 |
| --- | --- |
| `SAEROK_IMAGE_S3_BUCKET` | 등록 사진용 비공개 버킷. 녹음의 24시간 Lifecycle을 적용하지 않고 ADR-001의 사진 보관 및 삭제 조건을 따른다. 별도 삭제 처리가 없으면 안 된다는 뜻이며 무기한 보관 설정이 아니다 |
| `SAEROK_IMAGE_S3_REGION` | S3 리전, 기본 `ap-northeast-2` |
| `SAEROK_IMAGE_S3_PREFIX` | 개인정보를 넣지 않는 객체 키 접두사, 기본 `photos` |
| `SAEROK_IMAGE_S3_ENCRYPTION` | 서버 측 암호화 `AES256` 또는 `aws:kms` |
| `SAEROK_IMAGE_PRESIGNED_TTL_SECONDS` | 조회와 AI 다운로드 URL 수명, 기본 900초 |
| `SAEROK_MAX_IMAGE_BYTES` | 사진 크기 상한, 기본 20MB |

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
| `GET` | `/api/v1/profiles/{profileId}/reports` | 7-1 리포트 기록. 리포트가 저장된 회차만 |
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
  `started_at`의 한국 시간 날짜다. 7-2는 면회 사진이 있을 때만 사진 저장소에서 조회 URL을
  만든다.
- 7-4는 회차 행을 잠근 한 트랜잭션에서 모든 제안을 `settled`로 바꾸고, 승인한 생애 정보
  제안은 요청의 `title`, `content`로 생애 정보를, 승인한 주제 제안은 요청의 `action`으로
  `topic_feedback`을 만든다. 제안 값은 바꾸지 않는다. 제안이 없는 회차에 빈 요청을 보내면
  아무것도 바꾸지 않고 `200`이다(명세 미정 사항 2).
- 리포트 생성기(8-3)는 요청 조립(이름, 성별, 생년월일 제외) → AI 서버 호출(트랜잭션 밖) →
  응답 검증 → 리포트, 카드 요약, 변경 제안 저장(한 트랜잭션) 순서다. 검증에 걸리면 아무것도
  저장하지 않고 작업을 `INVALID_AI_RESPONSE`로 실패시킨다.
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
| `INVALID_CARD_REVIEW` | 422 | 6-1. 선택 카드가 아니거나, 중복이거나, `wasUsed`와 `caregiverReaction`의 짝이 틀림 |
| `INVALID_PROPOSAL_REVIEW` | 422 | 7-4. `pending` 제안이 빠졌거나 다른 회차의 제안이거나 중복 |
| `IMAGE_STORAGE_UNAVAILABLE`, `IMAGE_STORAGE_NOT_CONFIGURED` | 503 | 7-2. 면회 사진의 조회 URL을 만들지 못함 |

worker가 작업 실패로 남기는 코드: `INVALID_AI_RESPONSE`, `AI_SERVER_TIMEOUT`,
`AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`, `REPORT_ALREADY_GENERATED`(이미 리포트가 있는 회차),
`EVALUATION_REQUIRED`(평가 없는 회차. 6-2가 막으므로 정상 흐름에서는 생기지 않음).

### 다른 작업과 병합한 뒤 정리할 것

- 작업 B(PR #99)의 `load_visit_session`: `VisitSession`은 B의 모델(`app/schemas/visit_session.py`)
  하나로 합쳤다. B의 5-1, 5-3은 아직 상태를 `evaluationPending`으로 고정한 임시
  `load_visit_session`(`app/services/visit_sessions.py`)을 쓴다. 작업 B와 확인한 뒤
  `session_status.load_visit_session`을 쓰게 한다.
