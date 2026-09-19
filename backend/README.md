# BE 영역

담당 리더: 김민혁

상태: FastAPI 골격, 구글 인증 API와 PostgreSQL 개발 스키마 구성. 실제 STT, VLM과 계정의 DB 영속 저장은 아직 연결되지 않았다. MVP의 STT와 VLM은 ADR-006에 따라 온프레미스 GPU 1대에서 처리하며 데이터 관리는 서버 중심으로 전환한다. ADR-007은 계정 저장 항목 등의 공동 검토를 위해 `proposed`로 유지한다.

## 담당 범위

- 이미지, STT와 화자 처리 모델의 서버 실행 연동
- 녹음부터 전사, 화자 처리와 결과 반환까지의 처리 파이프라인
- 모델 파일 배포, 로딩, 자원 해제와 오류 처리
- 앱과 로컬 AI 사이의 데이터 계약
- 단말 데이터 구조, 로컬 DB, 암호화와 마이그레이션 정책
- 선택적 중계 서버가 필요한 조건
- 마스킹, API, 인증, 로그와 삭제 정책
- 타임아웃, 재시도와 대체 흐름

BE는 실행 위치와 데이터 흐름을 정한다. 모델 선택과 품질 기준은 AI와 공동 검토한다.

## 확정된 기준

괄호에 `제안`이나 `미정`을 적은 항목은 아직 확정 전이며 표시한 검토를 거쳐 확정한다.

- 데이터 관리는 서버 중심으로 전환하며, 데이터별 서버 저장 항목, 단말 보관 여부, 접근 권한과 보관 기간은 미정 (ADR-006)
- 녹음과 이미지 원본은 동의한 기능에 필요한 경우 암호화하여 서버에서 임시 처리할 수 있음
- 원본 자료는 처리 완료 후 즉시 삭제하며 최대 24시간을 넘기지 않음
- 직접 식별정보와 허용 목록 밖의 원본 자료는 외부 AI로 전송하지 않음
- 인증은 구글 소셜 로그인 한 가지를 사용하며 자체 아이디와 비밀번호는 받지 않음 (PM이 동의한 방향, 계정 저장 항목 등 ADR-007의 미정 내용과 구분)
- 구글 ID 토큰은 백엔드가 구글 공개키로 직접 검증하며 Firebase Auth를 사용하지 않음
- 계정과 동의 이력은 구글 인증 뒤 필수 동의가 완료될 때 함께 생성함. 현재는 메모리 저장이며 DB 연결은 후속 작업이고, 동의 전에는 계정을 만들지 않음
- 계정에 저장할 항목의 범위는 검토 중이며, 나머지 데이터의 서버 저장 범위와 보관 기간은 ADR-006에 따라 BE가 정리하고 FE, AI와 PM이 함께 확인함
- STT와 VLM은 온프레미스 GPU 1대에서 처리하며 장비와 운영 방식은 미확정
- 외부 LLM 사용과 백엔드의 구체적인 운영 배포 방식은 미확정
- 서버 중심 전환이 모든 원본의 영구 저장을 뜻하지 않으며, 녹음과 이미지 원본은 처리 후 즉시 삭제하고 최대 24시간을 넘기지 않는 제한을 유지함
- 실제 사용자 정보와 전사문을 로그에 남기지 않음
- 서버 처리 구조가 필요하면 데이터 흐름과 법률 문서를 먼저 갱신

## BE 리더가 정할 사항

- 온프레미스 GPU 모델 실행 런타임과 Flutter 연동 방식
- 녹음 형식, 입력 조건과 처리 단계
- 작업 상태, 타임아웃, 재시도와 복구 방식
- 모델 파일 다운로드와 무결성 확인
- 로컬 DB 기술, 스키마, 암호화와 마이그레이션 방식
- 외부 LLM과 무저장 중계 서버 필요 여부
- 서버가 받을 수 있는 필드의 허용 목록
- 마스킹 위치, 전송 전 확인, 로그와 삭제 증명
- 백엔드 세션의 형식과 수명은 아래 구현 상태를 확인하고, 앱의 세션 복원과 자동 재인증 및 계정 삭제 시 삭제 범위를 후속 검토
- 서버 사용 시 언어, 프레임워크, 배포와 테스트 명령

선택 결과에는 입력과 출력, 데이터 저장 여부, 실패 조건, 보안 영향, 검증 방법과 재검토 조건을 기록한다. 구조 결정은 ADR도 작성한다.

## 녹음과 처리의 기본 상태

    Flutter 앱
    → 단말 녹음과 기능 동의 확인
    → 암호화된 원본의 서버 임시 처리
    → STT, 화자 처리와 VLM 결과 반환
    → 원본 즉시 삭제와 삭제 결과 확인
    → 보호자 검토
    → 승인된 사실 반영, 서버 중심 관리

위 흐름은 구현 목표다. STT와 VLM의 실행 위치와 데이터 관리 방향은 ADR-006을 따른다. 데이터별 서버 저장 항목, 단말 보관 여부와 보관 기간은 아직 정하지 않았다. 현재 인증 API는 구현됐지만 DB 영속 저장과 모델 실행 연결은 완료되지 않았다.

온프레미스 GPU의 장비와 운영 방식은 PM, AI와 BE가 정한다. 필수 동의 확인, 전송 암호화, 원본과 임시 파일의 최대 24시간 삭제, 작업 큐와 로그의 삭제 확인을 완료 조건에 포함한다. 외부 업체는 업체명, 국가, 처리 목적, 항목, 보유기간과 자체 학습 여부를 확정하기 전 호출하지 않는다.

## 실행과 테스트

현재 골격은 Python 3.12, FastAPI와 Uvicorn을 사용한다. 의존성과 가상 환경은 `uv`로 관리하고 테스트는 `pytest`로 실행한다. 실제 사용자 자료와 마스킹한 실제 자료는 이 환경에서 사용하지 않는다.

`backend/`에서 최초 환경설정을 수행한다.

```powershell
cd backend
uv python install 3.12
uv sync
uv run python --version
```

최초 환경설정 후 다음과 같이 서버를 활성화한다.
```powershell
cd backend
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload --no-access-log
```

Android 에뮬레이터 또는 허가된 개발 단말에서 합성 데이터로 연동할 때만 외부 인터페이스에 바인딩한다.

```powershell
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
```

테스트는 다음 명령으로 실행한다.

```powershell
uv run pytest
```

## 데이터베이스 마이그레이션 (Alembic)

PostgreSQL 스키마의 소유권은 Alembic migration에 있다. `backend/database/init.sql`은
빈 개발 DB를 한 번에 세우는 bootstrap 스크립트일 뿐이며, 스키마가 바뀌면 Alembic
migration을 먼저 바꾸고 `init.sql`을 그에 맞춘다(자세한 로컬 적용 방법은
`backend/database/로컬설정법.md` 참고).

`SAEROK_DATABASE_URL`(`.env`)에 연결 문자열을 설정한 뒤 다음으로 최신 스키마를 적용한다.

```powershell
cd backend
uv run alembic upgrade head
```

새 migration을 추가할 때는 `uv run alembic revision -m "설명"`으로 뼈대를 만든 뒤
`upgrade`/`downgrade`를 직접 작성한다. `alembic revision --autogenerate`의 결과는
CHECK constraint, JSONB, partial index, FK `ON DELETE` 동작을 빠뜨릴 수 있으므로
그대로 신뢰하지 않고 반드시 검토한다.

상태 확인 API는 다음과 같다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `GET` | `/health/live` | 프로세스 생존 확인 |
| `GET` | `/health/ready` | 요청 처리 준비 상태 확인 |

로컬 API 문서는 서버 실행 후 `http://127.0.0.1:8000/docs`에서 확인한다. 현재 readiness는 외부 의존성이 없는 골격의 준비 상태만 나타내며, 모델과 저장소가 추가되면 실제 의존성 점검을 연결한다.

## 로그인 API

로그인 API는 PR #47로 develop에 반영됐다. 근거는 [ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)이다. 구글 ID 토큰 직접 검증 방향에 대한 PM 동의와 개인정보 저장 항목의 검토안은 구분한다. ADR-007은 `proposed`로 유지하며, API 구현이 저장 범위 전체의 확정을 뜻하지 않는다. 응답의 `authProvider`와 nullable `email`은 [공통 Account 계약](../docs/architecture/data-contracts.md#계정-account)에 맞춘다.

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

아래 동의 목록은 현재 develop 구현의 예시다. 공통 계약과 FE에서는 알림이 선택이지만 BE는 아직 필수로 처리한다. 이를 선택 동의로 고치는 [PR #49](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/49)는 미병합이며, 아래 예시를 제품의 확정 동의 기준으로 사용하지 않는다.

```json
{
  "schemaVersion": 1,
  "status": "consentRequired",
  "registrationToken": "...",
  "expiresIn": 600,
  "consentVersion": "2026-09-06",
  "requiredConsents": ["serviceData", "sensitiveData", "pushNotification"],
  "optionalConsents": ["serviceImprovement"]
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
