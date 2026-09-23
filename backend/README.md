# BE 영역

담당 리더: 김민혁. Python 3.12와 FastAPI의 상태 확인, 공통 오류 및 요청 로그, 구글 인증 API와 PostgreSQL 개발 스키마가 있다. 실제 STT, VLM과 계정의 DB 영속 저장은 아직 연결되지 않았다.

MVP의 STT와 VLM은 [ADR-006](../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)에 따라 온프레미스 GPU 1대에서 처리하고 데이터 관리도 서버 중심으로 전환한다. 현재 RTX 3060 Ti는 개발용이며 시연 장비의 사양과 처리 성능은 추가 실험 후 정한다. 운영 방식과 데이터별 저장 계약은 미정이며, 이 FastAPI 골격을 운영 배포 구조로 확정한 것은 아니다.

[ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)은 계정 저장 항목 등의 공동 검토를 위해 `proposed`로 유지한다.

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

`SAEROK_DATABASE_URL`(`.env`)에 연결 문자열을 설정한 뒤 다음으로 최신 스키마를 적용한다.

```powershell
uv run alembic upgrade head
```

새 migration을 추가할 때는 `uv run alembic revision -m "설명"`으로 뼈대를 만든 뒤
`upgrade`/`downgrade`를 직접 작성한다. `alembic revision --autogenerate`의 결과는
CHECK constraint, JSONB, partial index, FK `ON DELETE` 동작을 빠뜨릴 수 있으므로
그대로 신뢰하지 않고 반드시 검토한다.

PR #32의 500 응답 헤더와 완료 로그 보완이 develop에 반영됐다. 모델과 저장소가 연결되면 readiness에도 실제 의존성 점검을 추가한다. 개발 스키마가 있어도 인증 API의 저장소는 아직 프로세스 메모리 구현이다.

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
    → 원본 즉시 삭제와 삭제 결과 확인
    → 보호자 검토
    → 승인된 사실 반영, 서버 중심 관리

이 흐름은 구현해야 할 목표다. BE가 데이터별 저장 위치, 단말 보관 여부, 기간과 접근 및 삭제 조건을 PR로 정리하고 FE, AI와 PM이 함께 확인한다. DB와 GPU를 같은 장비에 배치할지도 미정이다. 원본의 서버 보관은 처리 완료 후 즉시 삭제, 최대 24시간을 유지한다. 실제 사용자 자료와 마스킹한 실제 자료는 개발 골격의 테스트에 사용하지 않는다.

직접 식별정보와 허용 목록 밖의 원본은 외부 AI로 보내지 않는다. 데이터 경로 변경 전 [법률 문서](../docs/legal/README.md), [동의 및 임시 처리 ADR](../docs/architecture/decisions/ADR-001-consent-and-temporary-processing.md)과 데이터 흐름을 갱신한다. 외부 업체의 이름, 국가, 목적, 항목, 보유기간과 자체 학습 여부가 정해지기 전에는 실제 사용자 자료로 호출하지 않는다.

## 로그인 API

로그인 API는 PR #47로 develop에 반영됐다. 근거는 [ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)이다. 구글 ID 토큰 직접 검증 방향에 대한 PM 동의와 개인정보 저장 항목의 검토안은 구분한다. ADR-007은 `proposed`로 유지하며, API 구현이 저장 범위 전체의 확정을 뜻하지 않는다. 응답의 `authProvider`와 nullable `email`은 [공통 Account 계약](../docs/architecture/data-contracts.md#계정-account)에 맞춘다.

인증은 구글 소셜 로그인 한 가지를 사용하고 자체 아이디와 비밀번호는 받지 않는다. 백엔드는 구글 공개키로 ID 토큰을 직접 검증하며 Firebase Auth를 사용하지 않는다.

### 흐름

다음은 목표 흐름이다. 서버의 세 엔드포인트는 있지만, 앱의 세션 보관과 재실행 시 복원은 [PR #50](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/50)의 후속 보완 항목이다.

    앱 시작
    → (세션 있음) GET /auth/me → 홈
    → (세션 없음) 구글 로그인 버튼 → POST /auth/google
        → status=authenticated  → 홈
        → status=consentRequired → 동의 화면 → POST /auth/consent → 홈

구글 인증에 성공한 것만으로는 계정을 만들지 않는다. 필수 동의가 모두 완료될 때 계정과 동의 이력을 함께 만든다. 필수 동의를 거부하거나 중단하면 계정이 남지 않는다.

### 엔드포인트

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `POST` | `/auth/google` | 구글 ID 토큰 검증. 계정이 있으면 세션 발급, 없으면 동의 요청 |
| `POST` | `/auth/consent` | 필수 동의 제출. 계정과 동의 이력 생성 후 세션 발급 |
| `GET` | `/auth/me` | 세션으로 현재 계정 조회 (`Authorization: Bearer <accessToken>`) |

요청과 응답의 정확한 형태는 서버 실행 후 `http://127.0.0.1:8000/docs` 와 `openapi.json` 에서 확인한다.

`POST /auth/google` 은 `{"idToken": "..."}` 를 받고 `status` 로 갈라지는 두 응답 가운데 하나를 준다.

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

### 세션

[ADR-007의 구현 상태](../docs/architecture/decisions/ADR-007-google-social-login.md#현재-구현과-후속-작업)에 현재 서버 구현과 앱의 후속 작업을 나누어 기록했다.

- 형식: HS256 으로 서명한 JWT. 리프레시 토큰을 따로 두지 않는다.
- 수명: `SAEROK_SESSION_TTL_SECONDS`(기본 1시간).
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
| `CONSENT_VERSION_MISMATCH` | 409 | 앱이 보낸 약관 버전이 서버와 다름 |
| `UNAUTHENTICATED` | 401 | 세션이 없거나 유효하지 않음 |
| `SESSION_EXPIRED` | 401 | 세션 만료. 다시 로그인 필요 |
| `ACCOUNT_NOT_FOUND` | 404 | 세션은 읽었으나 계정이 없음 |

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
| `SAEROK_STORE_GOOGLE_PROFILE` | 이메일과 구글 계정 이름 저장 여부 (기본 `false`) |

안드로이드에서 붙일 때는 서버를 `--host 0.0.0.0` 으로 띄우고 에뮬레이터에서 `http://10.0.2.2:8000` 을 쓴다. 합성 데이터와 개발용 계정으로만 확인한다.

### 아직 정하지 않은 것

- **계정 저장 항목** — ADR-007의 PM 제안은 이메일과 구글 계정 이름을 저장하지 않는 방향이며 기본 설정은 `false`다. 스키마의 `email`은 nullable이고 표시 이름은 값이 없으면 `보호자`를 사용하므로 `nickname NOT NULL`과 충돌하지 않는다. 이메일 컬럼 유지 여부와 추가 수집 필요성은 별도 검토한다. 설정 스위치가 실제 사용자 정보 수집을 승인하는 것은 아니다.
- **`Account.email`의 널 허용** — 공통 계약, Flutter `Account`와 합성 예시는 nullable 응답을 읽도록 맞췄다. 이것으로 이메일 미저장 정책이나 DB 연결까지 확정한 것은 아니다. PR #50의 `AuthAccount`를 하나의 클래스로 합치는 작업도 포함하지 않는다.
- **`aud` 로 쓸 클라이언트 ID** — `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 웹 클라이언트 ID가 된다. FE 가 쓰는 값을 확인해서 `SAEROK_GOOGLE_CLIENT_IDS` 에 넣는다. Google Cloud Console 에 패키지명 `com.saelog.app` 과 디버그 및 릴리스 SHA-1 등록이 선행되어야 한다. 쉼표 구분 설정의 읽기 보완은 PR #51에서 다룬다.
- **계정 저장소** — 현재는 프로세스 메모리에만 남는 개발용 저장소(`InMemoryAccountRepository`)를 쓴다. 서버 재시작 시 계정과 동의 기록을 잃으므로, 클라이언트에 남은 세션 토큰만으로 기존 계정을 복구할 수 없다. 저장 항목이 확정되면 `AccountRepository`를 `users`와 `account_consents`에 연결한다.
- **재동의** — 약관 버전이 올라갔을 때 기존 계정에 다시 동의를 받는 흐름은 넣지 않았다. 응답의 `account.consent.consentVersion` 으로 앱이 비교할 수는 있다.
- **약관 본문 제공과 로그인 유지** — 약관 본문, 버전과 필수 여부의 서버 관리, 앱 재실행 시 세션 복원과 만료 후 자동 재인증은 PR #50에 남긴 후속 요청이다. 현재 API가 약관 본문까지 제공하거나 앱이 로그인 상태를 복원하는 것으로 읽지 않는다.
- **탈퇴와 계정 삭제** — ADR-007 의 재검토 조건에 있으며 이 구현에 없다.

## AI 음성 분석 연동

`POST /api/v1/speech-analyses`는 이미 S3에 업로드된 음성의 Presigned GET URL과 화자 수를 받아
AI 서버의 `POST /internal/v1/speech-analyses`로 전달한다. 이 API는 현재 S3 업로드나 Presigned URL
생성을 담당하지 않으며, AI 서버 응답의 스키마와 `analysisId`를 확인한 뒤 결과를 그대로 반환한다.
현재 단계는 BE가 음성 처리 동의를 이미 확인했다는 전제의 연동 확인용 API이며, 실제 앱 연결 전
인증과 동의 조회를 앞단에 연결해야 한다.

```json
{
  "schemaVersion": 1,
  "analysisId": "analysis_demo_001",
  "language": "ko",
  "speakerCount": 2,
  "audioSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/audio.wav?...",
    "downloadUrlExpiresAt": "2026-09-22T15:10:00+09:00",
    "sizeBytes": 123456,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "dataExpiresAt": "2026-09-22T16:00:00+09:00"
}
```

AI 서버 주소는 `SAEROK_AI_SERVER_URL`로 설정하며 기본값은 `http://127.0.0.1:8001`이다. 동기 처리
시간 제한은 `SAEROK_AI_SERVER_TIMEOUT_SECONDS`로 설정하며 기본값은 600초다. 현재 자동 재시도는
하지 않고 연결 실패, 시간 초과, AI 오류와 잘못된 응답을 공통 오류 형식으로 반환한다.
