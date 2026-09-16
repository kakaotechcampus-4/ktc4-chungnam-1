# BE 영역

담당 리더: 김민혁

상태: ADR-004 제안 범위의 로컬 FastAPI 기준 골격 구성, 별도 백엔드 배포 여부는 미확정, 서버 임시 처리의 법적 경계는 ADR-001로 확정

## 담당 범위

- 이미지, STT와 화자 처리 모델의 단말 실행 연동
- 녹음부터 전사, 화자 처리와 결과 반환까지의 처리 파이프라인
- 모델 파일 배포, 로딩, 자원 해제와 오류 처리
- 앱과 로컬 AI 사이의 데이터 계약
- 단말 데이터 구조, 로컬 DB, 암호화와 마이그레이션 정책
- 선택적 중계 서버가 필요한 조건
- 마스킹, API, 인증, 로그와 삭제 정책
- 타임아웃, 재시도와 대체 흐름

BE는 실행 위치와 데이터 흐름을 정한다. 모델 선택과 품질 기준은 AI와 공동 검토한다.

## 확정된 기준

- 프로필, 전사문과 회차 기록은 사용자 단말 저장을 기본으로 함
- 녹음과 이미지 원본은 동의한 기능에 필요한 경우 암호화하여 서버에서 임시 처리할 수 있음
- 원본 자료는 처리 완료 후 즉시 삭제하며 최대 24시간을 넘기지 않음
- 직접 식별정보와 허용 목록 밖의 원본 자료는 외부 AI로 전송하지 않음
- 별도 서버와 외부 LLM 사용은 현재 미확정
- 별도 서버를 사용하더라도 상시 개인정보 저장을 전제로 하지 않음
- 실제 사용자 정보와 전사문을 로그에 남기지 않음
- 서버 처리 구조가 필요하면 데이터 흐름과 법률 문서를 먼저 갱신

## BE 리더가 정할 사항

- 로컬 모델 실행 런타임과 Flutter 연동 방식
- 녹음 형식, 입력 조건과 처리 단계
- 작업 상태, 타임아웃, 재시도와 복구 방식
- 모델 파일 다운로드와 무결성 확인
- 로컬 DB 기술, 스키마, 암호화와 마이그레이션 방식
- 외부 LLM과 무저장 중계 서버 필요 여부
- 서버가 받을 수 있는 필드의 허용 목록
- 마스킹 위치, 전송 전 확인, 로그와 삭제 증명
- 서버 사용 시 언어, 프레임워크, 배포와 테스트 명령

선택 결과에는 입력과 출력, 데이터 저장 여부, 실패 조건, 보안 영향, 검증 방법과 재검토 조건을 기록한다. 구조 결정은 ADR도 작성한다.

## 서버를 사용하지 않는 기본 상태

    Flutter 앱
    → 단말 녹음
    → 로컬 STT와 화자 처리
    → 로컬 리포트 입력
    → 단말 저장

외부 LLM 또는 중계 서버는 PM, AI와 BE가 범위와 데이터 경계를 확인한 뒤 도입한다.

서버 처리 구조를 채택하면 필수 동의 확인, 전송 암호화, 원본과 임시 파일의 최대 24시간 삭제, 작업 큐와 로그의 삭제 증명을 완료 조건에 포함한다. 외부 업체는 업체명, 국가, 처리 목적, 항목, 보유기간과 자체 학습 여부를 확정하기 전 호출하지 않는다.

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

상태 확인 API는 다음과 같다.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| `GET` | `/health/live` | 프로세스 생존 확인 |
| `GET` | `/health/ready` | 요청 처리 준비 상태 확인 |

로컬 API 문서는 서버 실행 후 `http://127.0.0.1:8000/docs`에서 확인한다. 현재 readiness는 외부 의존성이 없는 골격의 준비 상태만 나타내며, 모델과 저장소가 추가되면 실제 의존성 점검을 연결한다.

## 로그인 API

근거는 [ADR-007](../docs/architecture/decisions/ADR-007-google-social-login.md)이다. ADR-007 은 `proposed` 이고 공동 검토 대기 상태이므로, 이 구현은 검토를 위한 것이며 저장 범위를 확정한 것이 아니다. 응답의 `authProvider` 는 ADR-007 이 제안한 `Account` 계약 변경을 전제로 한다.

### 흐름

앱은 두 단계를 거친다. 두 번째 실행부터는 저장한 세션으로 두 단계를 건너뛴다.

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

ADR-007 이 BE 에 남긴 항목이며 현재 구현은 다음과 같다. 팀 확인 후 ADR-007 에 추가한다.

- 형식: HS256 으로 서명한 JWT. 리프레시 토큰을 따로 두지 않는다.
- 수명: `SAEROK_SESSION_TTL_SECONDS`(기본 1시간).
- 갱신: 앱이 `google_sign_in` 의 무음 로그인으로 새 ID 토큰을 받아 `POST /auth/google` 을 다시 호출한다. 서버가 보관하는 갱신 자격증명은 없다.
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

- **계정 저장 항목** — ADR-007 의 PM 제안(이메일과 구글 계정 이름 미저장)을 기본값으로 두었다. `users` 개발 스키마는 `email` 컬럼과 `nickname NOT NULL` 을 갖고 있어 서로 맞지 않는다. `SAEROK_STORE_GOOGLE_PROFILE` 로 두 경우를 모두 확인할 수 있게 해두었고, 확정되면 기본값을 고정하고 이 항목을 지운다.
- **`Account.email` 의 널 허용** — 이메일을 저장하지 않으면 응답의 `email` 이 `null` 이 된다. 공통 계약과 `app/lib/data/models.dart` 는 아직 `email` 을 필수 문자열로 본다. 저장 범위 결정과 함께 계약을 맞춰야 한다.
- **`aud` 로 쓸 클라이언트 ID** — `google_sign_in` 에 `serverClientId` 를 넘기면 `aud` 가 웹 클라이언트 ID가 된다. FE 가 쓰는 값을 확인해서 `SAEROK_GOOGLE_CLIENT_IDS` 에 넣는다. Google Cloud Console 에 패키지명 `com.saerok.app` 과 디버그·릴리스 SHA-1 등록이 선행되어야 한다.
- **계정 저장소** — 현재는 프로세스 메모리에만 남는 개발용 저장소(`InMemoryAccountRepository`)를 쓴다. 서버를 다시 시작하면 계정과 세션이 사라진다. 저장 항목이 확정되면 `AccountRepository` 를 구현해 `users` 와 `account_consents` 에 연결한다.
- **재동의** — 약관 버전이 올라갔을 때 기존 계정에 다시 동의를 받는 흐름은 넣지 않았다. 응답의 `account.consent.consentVersion` 으로 앱이 비교할 수는 있다.
- **탈퇴와 계정 삭제** — ADR-007 의 재검토 조건에 있으며 이 구현에 없다.
