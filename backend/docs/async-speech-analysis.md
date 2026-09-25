# 비동기 면회 음성 STT 구현 및 테스트 가이드

작성 기준: `feature/backend-async-visit-processing`, 2026-09-25

이 문서는 Flutter가 면회 녹음 WAV와 참여자 수를 백엔드로 보내고, 백엔드가 음성을
S3에 임시 저장한 뒤 별도 worker에서 AI 서버의 STT 파이프라인을 호출하는 구현과
테스트 방법을 설명한다.

설계 결정과 검토 상태는
[ADR-008](../../docs/architecture/decisions/ADR-008-stt-pipeline.md), JSON 및 상태 이름은
[공통 데이터 계약](../../docs/architecture/data-contracts.md)을 정본으로 삼는다.

> 실제 사용자 음성, 마스킹한 실제 음성과 실제 전사문을 개발 및 테스트에 사용하지
> 않는다. 아래 절차는 직접 만든 무음 WAV나 사용이 허가된 합성 자료만 대상으로 한다.

## 1. 구현 목표

이 브랜치가 연결하는 범위는 다음 두 가지다.

1. 앱이 녹음한 WAV와 보호자가 확인한 면회 참여자 수를 백엔드에 전달한다.
2. 백엔드가 WAV를 S3에 임시 저장하고 AI 서버에 STT 처리를 요청한 뒤 검증된 응답을
   받는다.

리포트 생성은 이 범위와 분리한다. 리포트 생성기가 없어도 STT 성공은
`sttCompleted`로 기록하며, 리포트까지 만들어진 것처럼 `completed`로 표시하지 않는다.

## 2. 전체 처리 흐름

```text
Flutter
  └─ WAV + participantCount + sessionId
        ↓ multipart/form-data
BE API
  ├─ 세션 인증
  ├─ 계정 필수 동의 확인
  ├─ 면회 소유권·피보호자 확인·녹음 허가 확인
  ├─ WAV/PCM 16-bit/16kHz/mono 검증
  ├─ 파일 크기와 SHA-256 계산
  ├─ 비공개 S3 업로드
  └─ PostgreSQL 작업 등록
        ↓
  202 Accepted + analysisId

BE worker
  ├─ queued 작업 선점
  ├─ S3 Presigned GET 생성
  ├─ participantCount → speakerCount
  ├─ AI 서버 동기 API 호출
  ├─ SpeechAnalysisResult 및 analysisId 검증
  ├─ S3 원본 삭제
  └─ sttCompleted 기록

Flutter
  └─ analysisId 상태 조회
```

API 요청은 S3 업로드와 작업 저장까지만 기다린다. GPU 처리 중에는 Flutter의 요청
연결을 유지하지 않는다. BE worker와 AI 서버 사이는 기존 동기 HTTP 계약을 재사용한다.

## 3. 상태 전이

```text
uploading → queued → transcribing → sttCompleted
                                      └→ generatingReport → completed
                └──────────── 실패 ──────────────────────▶ failed
```

| 상태 | 의미 | 홈 화면 표시 |
| --- | --- | --- |
| `uploading` | 요청 안에서 S3 업로드 중인 내부 상태 | 202 이전이므로 표시하지 않음 |
| `queued` | 서버가 원본과 작업을 인수함 | 리포트를 만들고 있어요 |
| `transcribing` | worker가 AI 서버에 STT 요청 중 | 리포트를 만들고 있어요 |
| `sttCompleted` | AI 응답 검증 및 S3 원본 삭제 완료 | 리포트를 만들고 있어요 |
| `generatingReport` | 리포트 생성 중 | 리포트를 만들고 있어요 |
| `completed` | 리포트 저장까지 완료 | 완성된 리포트 타일 |
| `failed` | 정상 결과를 만들지 못함 | 실패 안내 및 후속 동작 |

현재 기본 worker는 리포트 생성기를 주입하지 않으므로 `sttCompleted`에서 멈춘다.

## 4. 공개 API

### 4.1 음성 분석 작업 제출

```http
POST /api/v1/visit-sessions/{sessionId}/speech-analyses
Authorization: Bearer <accessToken>
Content-Type: multipart/form-data
```

| multipart 필드 | 형식 | 제약 |
| --- | --- | --- |
| `audio` | WAV 파일 | PCM, 16-bit, 16kHz, mono, 서버 크기 상한 이하 |
| `participantCount` | 정수 | 1 이상 8 이하 |

성공 응답:

```http
HTTP/1.1 202 Accepted
```

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "sessionId": "4ad84021-e2db-4a04-8995-b148f3cdb853",
  "status": "queued"
}
```

`202`는 STT 완료가 아니라 서버가 원본과 작업을 안전하게 인수했다는 뜻이다. 앱은
`202`를 받기 전에는 로컬 WAV를 삭제하지 않는다.

같은 면회에 활성 작업이 이미 있으면 새 S3 객체를 만들지 않고 기존 작업 식별자를
반환한다. 최초 업로드가 `202` 전에 실패하면 예약 작업을 제거해 같은 로컬 원본으로
다시 제출할 수 있게 한다.

### 4.2 작업 상태 조회

```http
GET /api/v1/speech-analyses/{analysisId}
Authorization: Bearer <accessToken>
```

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "sessionId": "4ad84021-e2db-4a04-8995-b148f3cdb853",
  "status": "sttCompleted",
  "errorCode": null
}
```

다른 계정의 작업은 존재 여부를 노출하지 않고 404를 반환한다. 응답에는 음성,
전사문, 원래 파일명, S3 객체 키와 Presigned URL을 포함하지 않는다.

## 5. AI 서버 내부 계약

worker는 `participantCount`를 변경 없이 `speakerCount`로 이름만 바꾸어 AI 서버에
전달한다.

```http
POST /internal/v1/speech-analyses
Content-Type: application/json
```

```json
{
  "schemaVersion": 1,
  "analysisId": "0c6aa54d-17ec-46e4-a270-80e88f15c77f",
  "language": "ko",
  "speakerCount": 2,
  "audioSource": {
    "type": "s3PresignedGet",
    "downloadUrl": "https://example-bucket.s3.ap-northeast-2.amazonaws.com/...",
    "downloadUrlExpiresAt": "2026-09-25T15:10:00+09:00",
    "sizeBytes": 320044,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "dataExpiresAt": "2026-09-26T14:00:00+09:00"
}
```

BE는 성공 응답 스키마와 요청·응답의 `analysisId`가 같은지 검증한다. AI 오류 본문은
앱에 그대로 노출하거나 로그에 기록하지 않는다.

## 6. 주요 구현 파일

| 파일 | 역할 |
| --- | --- |
| `app/api/routes/speech_analyses.py` | multipart 제출 및 상태 조회 API |
| `app/services/audio_validation.py` | 크기, SHA-256과 WAV 규격 검사 |
| `app/services/audio_storage.py` | S3 업로드, Presigned GET과 삭제 |
| `app/services/speech_analysis_jobs.py` | 작업 모델, 메모리 테스트 저장소와 PostgreSQL 저장소 |
| `app/services/speech_analysis_pipeline.py` | 제출 서비스와 STT worker 처리 순서 |
| `app/workers/speech_analysis.py` | 독립 worker 실행 진입점 |
| `app/clients/ai_server.py` | 내부 AI 서버 HTTP 클라이언트와 오류 매핑 |
| `alembic/versions/a8c31f17d902_add_async_speech_analysis_jobs.py` | 작업 테이블 및 참여자 수 migration |
| `database/init.sql` | 빈 개발 DB용 최신 bootstrap 스키마 |
| `tests/test_speech_analyses.py` | API, 중복 제출, worker와 AI 계약 테스트 |
| `tests/test_audio_storage.py` | S3 암호화, URL 수명과 삭제 어댑터 테스트 |

## 7. 데이터베이스 변경

`visit_sessions`에 다음 필드를 추가한다.

```text
participant_count SMALLINT NULL CHECK (participant_count BETWEEN 1 AND 8)
```

`speech_analysis_jobs`에는 다음 정보를 저장한다.

```text
analysis_id
session_id                 한 면회당 하나로 UNIQUE
status
participant_count
s3_object_key              직접 식별정보와 원래 파일명 제외
size_bytes
sha256
data_expires_at
attempt_count
lease_expires_at
error_code
audio_deleted_at
stt_completed_at
created_at / updated_at / completed_at
```

전사문, AI 응답 본문과 Presigned URL은 작업 테이블에 저장하지 않는다.

## 8. 환경 설정

`.env.example`을 기준으로 로컬 `.env`를 작성한다. 실제 자격증명과 버킷 이름을
저장소에 커밋하지 않는다.

```dotenv
SAEROK_DATABASE_URL=postgresql+psycopg://<user>:<password>@<host>:5432/<database>

SAEROK_AI_SERVER_URL=http://127.0.0.1:8001
SAEROK_AI_SERVER_TIMEOUT_SECONDS=600

SAEROK_SPEECH_AUDIO_S3_BUCKET=<private-bucket>
SAEROK_SPEECH_AUDIO_S3_REGION=ap-northeast-2
SAEROK_SPEECH_AUDIO_S3_PREFIX=temporary/speech
SAEROK_SPEECH_AUDIO_S3_ENCRYPTION=AES256
SAEROK_SPEECH_AUDIO_PRESIGNED_TTL_SECONDS=900
SAEROK_SPEECH_AUDIO_RETENTION_SECONDS=86400
SAEROK_MAX_AUDIO_BYTES=536870912

SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS=900
SAEROK_SPEECH_WORKER_POLL_SECONDS=2
```

API 업로드는 `SAEROK_DATABASE_URL`과 `SAEROK_SPEECH_AUDIO_S3_BUCKET`이 모두 있을
때 활성화된다. 하나라도 없으면 `SPEECH_ANALYSIS_NOT_CONFIGURED`를 반환한다.

AWS 자격증명은 실행 환경의 IAM 역할 또는 표준 AWS SDK 자격증명 체인으로 제공한다.
소스와 `.env.example`에는 접근 키를 적지 않는다.

### S3 필수 운영 조건

- 퍼블릭 액세스 차단
- 객체 ACL 비공개
- 서버 측 암호화 적용
- BE 역할에 필요한 버킷 및 접두사 범위의 업로드·조회 URL 발급·삭제 권한만 부여
- `temporary/speech/` 객체가 업로드 후 최대 24시간 이내 제거되는 Lifecycle 적용
- 정상 처리에서는 Lifecycle을 기다리지 않고 STT 응답 직후 삭제

Lifecycle은 애플리케이션 환경 변수만으로 만들어지지 않는다. 실제 버킷 설정에서 별도로
적용하고 확인해야 한다.

## 9. 자동 테스트

### 9.1 의존성 설치

저장소 루트 기준:

```powershell
cd backend
uv sync
```

### 9.2 전체 BE 테스트

```powershell
uv run pytest
```

작성 시점 결과:

```text
55 passed, 3 skipped
```

건너뛴 세 테스트는 실제 PostgreSQL에서 migration의 생성, 제약과 downgrade를 검사한다.
`SAEROK_TEST_DATABASE_URL`이 없으면 의도적으로 실행하지 않는다.

### 9.3 Python 문법 및 import 확인

```powershell
uv run python -m compileall -q app tests
```

### 9.4 Alembic SQL 생성 확인

```powershell
uv run alembic upgrade head --sql | Out-Null
```

이 검사는 migration SQL을 생성하지만 실제 DB에는 적용하지 않는다.

### 9.5 실제 PostgreSQL migration 테스트

실제 사용자 데이터가 없는 테스트 전용 PostgreSQL 관리자 DB를 준비한다. 테스트는 임시
DB를 만들고 삭제하므로 운영 DB 주소를 절대 사용하지 않는다.

```powershell
$env:SAEROK_TEST_DATABASE_URL = "postgresql://<admin>:<password>@127.0.0.1:5432/postgres"
uv run pytest tests/test_migrations.py
```

검사가 끝나면 현재 셸의 테스트 환경 변수를 제거한다.

```powershell
Remove-Item Env:SAEROK_TEST_DATABASE_URL
```

## 10. 로컬 및 통합 실행

실제 STT까지 포함한 통합 테스트에서는 다음 구성요소를 사용한다.

| 구성요소 | 실행 여부 | 역할 |
| --- | --- | --- |
| PostgreSQL | 계속 실행 | 작업과 상태 저장 |
| S3 | 별도 로컬 프로세스 없음 | WAV 임시 저장과 Presigned GET 제공 |
| AI 서버 | 계속 실행 | GPU에서 STT와 화자 분리 수행 |
| BE API | 계속 실행 | FE 업로드 접수, S3 업로드와 상태 조회 |
| BE worker | 계속 실행 | DB 작업 인수, AI 호출, 원본 삭제와 상태 변경 |
| FE 앱 | 테스트 중 실행 | WAV와 참여자 수 제출, 상태 폴링 |

DB migration은 서버가 아니라 사전 준비 명령이므로 한 번 적용한 뒤 종료한다. BE API와
worker만 실행하면 worker의 AI HTTP 호출이 실패하므로, 실제 AI 서버 또는 같은 계약의
개발용 Mock AI 서버가 반드시 응답해야 한다.

### 10.1 DB migration 적용

테스트 전용 개발 DB 주소를 `.env`에 설정하고 다음을 실행한다.

```powershell
cd backend
uv run alembic upgrade head
```

운영 DB가 아니라 비어 있거나 복구 가능한 개발 DB에서 먼저 확인한다.

### 10.2 AI 서버 실행

`feature/ai-stt-pipeline`의 AI 서버를 별도 작업 디렉터리 또는 장비에서 실행한다. AI
서버에는 모델, GPU 환경, 허용 S3 호스트와 최대 음성 크기 설정이 필요하다.

현재 AI 구현의 Whisper 실행 장치는 CUDA로 고정되어 있다. GPU가 없는 BE 개발 PC에 AI
브랜치를 체크아웃하고 `uv sync`하는 것만으로는 실제 STT를 실행할 수 없다. 실제 통합
테스트에서는 AI 담당자가 GPU 장비에서 서버를 실행하고 BE가 접근할 수 있는 내부 주소를
공유한다. 원격 GPU 서버를 사용할 때 BE 개발 PC에는 AI 의존성을 설치할 필요가 없다.

AI 서버가 제공하는 실제 API는 다음과 같다.

```text
http://127.0.0.1:8001/internal/v1/speech-analyses
```

그러나 BE의 `SAEROK_AI_SERVER_URL`에는 API 경로를 제외한 기본 주소만 설정한다. BE
클라이언트가 `/internal/v1/speech-analyses`를 붙인다.

```dotenv
SAEROK_AI_SERVER_URL=http://127.0.0.1:8001
```

AI 서버가 다른 장비에 있으면 `127.0.0.1` 대신 BE에서 접근 가능한 내부 IP 또는 내부
도메인을 사용한다. AI 서버는 외부에 인증 없이 공개하지 않으며 실제 사용자 자료를 외부
AI 서비스로 보내지 않는다. worker를 실행하기 전에 다음 생존 확인이 성공해야 한다.

```powershell
Invoke-RestMethod http://<AI_SERVER_HOST>:8001/health/live
```

### 10.3 GPU 없이 연결 흐름 확인

GPU가 없으면 고정된 합성 `SpeechAnalysisResult`를 반환하는 Mock AI 서버로 다음 연결
범위를 확인할 수 있다.

```text
FE 업로드 → BE API → S3 → PostgreSQL → worker
→ Mock AI 응답 → S3 원본 삭제 → sttCompleted → FE 상태 조회
```

Mock은 실제 Whisper 전사 품질, 화자 분리와 GPU 실행 환경을 검증하지 않는다. 현재
`tests/test_speech_analyses.py`의 `FakeAiServer`는 pytest 프로세스 내부에서 worker 계약을
검사할 뿐이며 독립 실행 가능한 HTTP 서버가 아니다. 따라서 현재 코드로 FE까지 포함한
HTTP 통합 테스트를 하려면 GPU AI 서버를 사용해야 한다. 별도 Mock 서버를 추가한다면
요청의 `analysisId`를 그대로 돌려주고 합성 전사만 사용해야 하며, 실패를 실제 STT 성공으로
기록하는 운영 대체 경로로 사용해서는 안 된다.

### 10.4 BE API 실행

```powershell
cd backend
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

허가된 개발 단말에서 연결할 때만 내부 네트워크에 바인딩한다.

```powershell
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log
```

### 10.5 worker 실행

API와 다른 터미널에서 실행한다.

```powershell
cd backend
uv run python -m app.workers.speech_analysis
```

대기 작업 하나만 처리하고 종료하려면 다음을 사용한다.

```powershell
uv run python -m app.workers.speech_analysis --once
```

worker와 API는 같은 PostgreSQL과 S3 설정을 사용해야 한다.

## 11. 실제 API 통합 테스트

### 11.1 테스트 사전 데이터

현재 저장소에는 면회 세션 생성 API와 계정 PostgreSQL 영속화가 아직 없다. 따라서 실제
API 통합 테스트에는 다음 조건을 만족하는 합성 개발 데이터가 필요하다.

- 로그인 세션이 가리키는 `accountId`와 같은 UUID의 `users.user_id`
- 해당 사용자의 `profiles` 행
- 그 프로필에 속한 `visit_sessions` 행
- `session_status = 'ended'`
- `recording_authorization_granted = true`
- `careRecipientConfirmation`이 승인된 `session_consents` 행
- 로그인 계정의 `serviceData`, `sensitiveData` 동의

실제 사용자의 식별자나 면회 자료를 복사해서 테스트 데이터를 만들지 않는다. 계정 DB
연결과 면회 세션 API가 완성되기 전까지는 합성 개발 계정과 명시적인 테스트 fixture만
사용한다.

### 11.2 합성 WAV 만들기

Python 표준 라이브러리만으로 1초 무음 WAV를 만들 수 있다. 이 파일은 사용자 음성을
포함하지 않는다.

```powershell
@'
import wave

with wave.open("synthetic-silence.wav", "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(16000)
    wav.writeframes(b"\x00\x00" * 16000)
'@ | uv run python -
```

테스트가 끝나면 생성한 합성 파일을 삭제해도 된다.

### 11.3 multipart 업로드

아래 값은 실제 실행 환경의 합성 개발 세션 및 토큰으로 바꾼다. 토큰을 셸 기록, 문서,
화면 캡처와 Git에 남기지 않는다.

```bash
curl -X POST \
  "http://127.0.0.1:8000/api/v1/visit-sessions/<session-id>/speech-analyses" \
  -H "Authorization: Bearer <development-access-token>" \
  -F "audio=@synthetic-silence.wav;type=audio/wav" \
  -F "participantCount=2"
```

예상 결과는 HTTP 202와 `queued` 상태다. 응답의 `analysisId`를 테스트 중에만 보관한다.

### 11.4 상태 조회

worker가 실행 중인 상태에서 조회한다.

```bash
curl \
  "http://127.0.0.1:8000/api/v1/speech-analyses/<analysis-id>" \
  -H "Authorization: Bearer <development-access-token>"
```

정상 전이는 다음과 같다.

```text
queued → transcribing → sttCompleted
```

짧은 파일은 `transcribing` 상태를 조회하기 전에 끝날 수 있다. 최종
`sttCompleted`와 `errorCode: null`을 확인한다.

### 11.5 DB 확인

민감한 원문을 조회하거나 출력하지 않는다. 상태와 삭제 시각만 확인한다.

```sql
SELECT status,
       participant_count,
       attempt_count,
       audio_deleted_at IS NOT NULL AS audio_deleted,
       stt_completed_at IS NOT NULL AS stt_completed,
       error_code
  FROM speech_analysis_jobs
 WHERE analysis_id = '<analysis-id>';
```

예상값:

```text
status = sttCompleted
participant_count = 2
attempt_count = 1
audio_deleted = true
stt_completed = true
error_code = null
```

### 11.6 S3 삭제 확인

테스트에 사용한 `analysisId`의 임시 객체가 남아 있지 않아야 한다. 객체 목록 전체나
다른 작업 키를 로그 및 캡처에 남기지 말고 해당 합성 작업 하나만 확인한다.

정상 경로에서 즉시 삭제됐는지 확인하고, 별도로 버킷 Lifecycle이 24시간 상한으로
설정됐는지 AWS 관리 설정에서 확인한다.

## 12. 필수 실패 시나리오

| 시나리오 | 예상 결과 |
| --- | --- |
| `participantCount=0` 또는 `9` | 422 `INVALID_REQUEST`, S3 업로드 없음 |
| WAV가 아닌 파일 | 422 `INVALID_AUDIO_FORMAT`, S3 업로드 없음 |
| 빈 파일 | 422 `INVALID_AUDIO`, S3 업로드 없음 |
| 크기 상한 초과 | 413 `AUDIO_TOO_LARGE`, 작업 접수 안 됨 |
| 인증 없음 | 401 `UNAUTHENTICATED` |
| 다른 계정의 면회 | 404 `VISIT_SESSION_NOT_FOUND` |
| 피보호자 확인 또는 녹음 허가 없음 | 404, 업로드 없음 |
| S3 업로드 실패 | 503 `AUDIO_STORAGE_UNAVAILABLE`, 202 반환 안 함, 재제출 가능 |
| AI 연결 실패 | 작업 `failed`, `AI_SERVER_UNAVAILABLE` |
| AI 시간 초과 | 작업 `failed`, `AI_SERVER_TIMEOUT` |
| AI 응답 스키마 오류 | 작업 `failed`, `INVALID_AI_RESPONSE` |
| 응답 `analysisId` 불일치 | 작업 `failed`, `INVALID_AI_RESPONSE` |
| S3 삭제 실패 | 작업을 STT 완료로 표시하지 않음, Lifecycle 삭제 대상 |
| 같은 면회 반복 제출 | 새 객체를 만들지 않고 기존 활성 작업 반환 |

오류 응답과 로그에서 WAV 내용, 전사문, Presigned URL, 객체 키, 인증 토큰과 AI 오류
본문이 노출되지 않는지도 함께 확인한다.

## 13. FE 연결 기준

FE는 녹음을 정상적으로 닫아 WAV 헤더가 완성된 뒤 업로드한다.

```text
recordingPath       → multipart audio
participantCount    → multipart participantCount
VisitSession ID     → URL sessionId
accessToken         → Authorization Bearer
```

- `202` 전에는 전송 중 상태를 표시하고 로컬 WAV를 유지한다.
- `202`를 받으면 홈으로 이동하고 작업 타일을 처리 중으로 표시할 수 있다.
- 업로드 실패 시 로컬 WAV를 유지해 사용자가 다시 제출할 수 있게 한다.
- 앱이 활성화되거나 홈 화면이 보일 때 상태를 다시 조회한다.
- `sttCompleted`는 리포트 준비 완료가 아니므로 완성된 리포트 타일로 바꾸지 않는다.
- 리포트 생성 계약이 연결되기 전에는 `completed`를 기대하지 않는다.

## 14. 현재 제한과 후속 작업

- ADR-008은 아직 `proposed`이며 FE, AI, PM의 공동 확인이 남아 있다.
- 실제 PostgreSQL 계정 저장소와 면회 세션 생성·종료 API가 아직 없다.
- 실제 S3 버킷, IAM과 Lifecycle은 저장소 밖의 운영 환경에서 구성해야 한다.
- AI 서버 브랜치와 실제 GPU 환경의 통합 실행은 별도로 확인해야 한다.
- 독립 실행 가능한 Mock AI HTTP 서버는 없으며 테스트의 `FakeAiServer`는 pytest에서만
  사용한다.
- 자동 재시도, 사용자 재시도, 취소와 worker 장애 복구는 아직 없다.
- 리포트 생성 계약과 저장 구현은 없으며 기본 worker는 `sttCompleted`에서 멈춘다.
- 전사문은 DB에 저장하지 않는다. 리포트 생성기를 연결할 때 같은 worker 메모리에서
  즉시 전달한다. 장애 복구를 위해 저장해야 한다면 개인정보 처리 기준을 다시 결정한다.
- 앱 재실행 후 홈 타일 전체를 복구할 면회 목록 API는 별도 기능이다. 현재는 앱이
  `analysisId`를 알고 있을 때 단건 상태 조회가 가능하다.

이 제한들은 STT 연결 성공을 리포트 완성으로 오인하지 않기 위한 경계다. 확인되지 않은
전사나 리포트를 정상 결과처럼 표시하는 대체 경로를 추가하지 않는다.
