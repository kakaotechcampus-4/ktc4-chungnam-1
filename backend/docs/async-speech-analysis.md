# 비동기 면회 음성 STT 구현 및 테스트 가이드

작성 기준: `feature/backend-async-visit-processing`, 2026-09-25

> 현재 구현 (2026-11-10 기준, develop `83695093`): 면회 회차 생성(5-1), 보호자 평가(6-1),
> 회차 목록(5-4)과 실패 분석 재요청(`POST /api/v1/speech-analyses/{analysisId}/retry`,
> [수동 복구](speech-recovery.md)) API가 있다. 운영에서는 speech-worker가 STT 뒤 리포트까지
> 만든다. 아래 본문의 9월 기준 설명 중 바뀐 곳은 6절, 10.2절, 11.1절, 12절과 14절에 표시했다.
>
> 지금 운영 BE는 2026-11-10 01:41 KST Deploy run 42656825849가 배포한 develop `83695093`이다.
> 11/9 배포분(`59190ba7`)에 더해진 BE 코드 변경은 #295뿐이다(#293은 문서). speech-worker가 쓰는
> 이야기 후보와 리포트 프롬프트가 `proposals-8`, `report-6`으로 바뀌었고, 이야기 후보의 분류와
> 아픈 기억 표시를 저장하며(migration `9c4e2b7a1f63`), 작업이 끝나거나 실패할 때 처리 기록 한 줄을
> 남긴다(10.6절).
>
> 다음 변경은 2026-11-09 develop에 병합됐고 같은 날 Deploy run 42568179490(develop `59190ba7`)으로
> 운영에 들어갔다. 그 전 운영 BE는 11/8 Deploy run 42485750502가 배포한 develop `9c2b8276`이었다.
>
> - #278: 본문을 읽기 전 앱 버전과 세션 토큰 확인, 요청 본문 상한(2절, 12절)
> - #280: 전사 저장 뒤 리포트 시작 전에 멈춘 작업의 이어받기(3절, 7절, 12절, 14절)
> - #279: 남은 전사 기한이 임대 시간 이상일 때만 리포트 생성 시작, 변경 제안 호출 직전 작업
>   재확인(3절, 11.4절, 12절, 14절)
> - #283: 업로드가 끝나기 전에 작업 행이 지워져도 올라간 원본 키를 삭제 대기열에 기록(12절)
> - #285: 리포트 재요청(6-5)의 회차당 3회 한도(14절, [수동 복구](speech-recovery.md))

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

리포트 생성(API 8-3)은 이 문서 범위 밖이며 [README의 평가와 리포트 API](../README.md#평가와-리포트-api)에
정리한다. STT 성공은 `sttCompleted`로 기록하며, 리포트까지 저장해야 `completed`로 표시한다.

## 2. 전체 처리 흐름

```text
Flutter
  └─ WAV + participantCount + sessionId
        ↓ multipart/form-data
BE API
  ├─ 본문을 읽기 전: 앱 버전, 세션 서명과 만료, 본문 상한(음성 상한 + 1 MiB)
  ├─ 세션 폐기 여부와 계정 확인
  ├─ 계정 필수 동의 확인
  ├─ 면회 소유권과 보호자 평가 제출 확인
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
  ├─ 전사문 임시 저장과 sttCompleted 기록
  └─ 원본 삭제 요청 기록과 S3 삭제 시도 (실패 시 대기열 유지)

Flutter
  └─ analysisId 상태 조회
```

API 요청은 S3 업로드와 작업 저장까지만 기다린다. GPU 처리 중에는 Flutter의 요청
연결을 유지하지 않는다. BE worker와 AI 서버 사이는 기존 동기 HTTP 계약을 재사용한다.

위 그림의 "본문을 읽기 전" 단계는 #278(2026-11-09 develop 병합)에서 생겼고 11/9 배포부터 운영에
있다. 그 전 운영(develop `9c2b8276`)에는 요청 본문 바이트 상한이 없었고, 파일 크기는 본문을
다 받은 뒤 라우트 안에서 검사했다(#278 PR 설명).

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
| `sttCompleted` | AI 응답 검증과 전사문 임시 저장 완료. 원본 삭제 여부는 별도 기록 | 리포트를 만들고 있어요 |
| `generatingReport` | 리포트 생성 중 | 리포트를 만들고 있어요 |
| `completed` | 리포트 저장까지 완료 | 완성된 리포트 타일 |
| `failed` | 정상 결과를 만들지 못함 | 실패 안내 및 후속 동작 |

기본 worker는 STT 뒤 리포트 생성기(8-3)를 부르고, 리포트와 변경 제안을 저장한 뒤에만
`completed`로 바꾼다. 리포트 생성기는 `ai/`의 생성 함수를 직접 부르며, 생성에 실패하면
작업은 `sttCompleted`를 지나 `failed`(`AI_SERVER_UNAVAILABLE`, `AI_SERVER_ERROR`,
`INVALID_AI_RESPONSE` 등)로 끝난다. 리포트 생성 전체가 제한 시간
(`SAEROK_REPORT_GENERATION_TIME_LIMIT_SECONDS`, 기본 600초)을 넘으면 `AI_SERVER_TIMEOUT`,
생성 중 임대가 끝나면 늦게 온 결과를 저장하지 않고 `WORKER_LEASE_EXPIRED`다. 리포트 저장과
`completed`는 한 트랜잭션이며 끝난 작업의 상태는 다시 바꾸지 않는다(README 평가와 리포트 API).
STT 중 임대가 끝나 이미 `failed`가 된 작업은 STT 응답이 늦게 와도 전사문을 남기지 않고 리포트
생성도 시작하지 않는다. 받은 전사문을 외부 생성 함수로 보내지 않기 위해서다. 이때 worker는
`speech_analysis_stopped` info 로그에 작업 ID(`analysis_id`)와 멈춘 단계(`stage`)만 남긴다.
`--stt-only`(development/test)로 실행하면 리포트 생성기를 만들지 않고 `sttCompleted`에서 멈춘다.

리포트까지 이어 가는 worker는 전사문을 저장하는 같은 문장에서 인계 임대
(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`, 기본 900초)를 기록한다. 전사 저장과 `generatingReport`
사이에 하는 일은 원본 삭제 요청과 S3 삭제 시도뿐이다. 그 사이 worker가 강제 종료되거나 DB
오류로 실패 기록도 남기지 못하면 작업은 `sttCompleted`에 남는다. 인계 임대가 끝나면 다음
worker가 같은 작업 ID와 저장된 전사로 `generatingReport`부터 이어 간다. STT와 S3 다운로드를
반복하지 않고, 빠진 원본 삭제 요청은 S3를 부르지 않고 삭제 대기열에만 남긴다. 이미 이어받은
작업이면 늦게 돌아온 원래 worker는 `generatingReport`로 바꾸지 못하므로 리포트를 두 번 만들지
않는다. 이어받는 작업은 `generatingReport`로 바뀌어 다시 `sttCompleted`로 돌아오지 않으므로
작업마다 한 번뿐이다. 남은 전사 기한이 생성 단계 임대 시간보다 짧은 작업은 이어받지 않고 아래와 같이
`TRANSCRIPT_EXPIRED`로 끝낸다. `--stt-only`는 인계 임대를 두지 않으므로 나중에 기본 worker를
실행해도 그 작업을 리포트 생성에 넘기지 않는다.

전사문은 STT 완료 후 24시간까지만 작업에 남는다. 그때까지 리포트를 저장하지 못하면
worker가 전사문을 지우고 작업을 `failed`(`TRANSCRIPT_EXPIRED`)로 바꾼다.
리포트 생성은 남은 전사 기한이 생성 단계 임대 시간(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`,
기본 900초) 이상일 때만 시작한다. 임대는 생성 제한 시간보다 60초 이상 길어야 worker가
시작하므로, 시작한 생성이 기한을 넘겨 전사문을 보내는 새 외부 호출을 하지 않는다. 기한이 그보다 적게 남은
`sttCompleted` 작업(리포트 재요청 등)은 시작하지 않고 worker 정리 때 전사문을 지우며
`failed`(`TRANSCRIPT_EXPIRED`)로 끝낸다. 리포트 호출 뒤 변경 제안 호출(전사문의 두 번째 외부
전송) 직전에는 DB의 작업 행을 다시 읽는다. 그 사이 계정, 프로필이나 회차가 지워져 작업이
없어졌거나, 작업이 `generatingReport`가 아니거나 임대가 끝났으면 `WORKER_LEASE_EXPIRED`,
전사가 지워졌거나 기한이 지났으면 `TRANSCRIPT_EXPIRED`로 멈추고 보내지 않는다. 이미 보낸
리포트 호출은 되돌리지 못한다.

현재 구현 (2026-11-09 기준): 위 두 문단의 인계 임대와 이어받기(#280), 남은 전사 기한 확인과
변경 제안 호출 직전 확인(#279)은 11/9 배포(run 42568179490)부터 운영에 있다. 그 전 운영(develop
`9c2b8276`)의 worker는 `sttCompleted`에서 리포트 재요청 작업만 가져갔으므로, 전사 저장 뒤 리포트
시작 전에 멈춘 작업은 STT 완료 후 24시간이 지나 `TRANSCRIPT_EXPIRED`로 끝날 때까지
`sttCompleted`에 남았다. 리포트 생성도 전사 기한 전이기만 하면 시작했다. 배포 전부터 멈춰 있던
작업에 필요한 한 번의 조치는 [수동 복구](speech-recovery.md#적용과-되돌리기)에 적었다.

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

BE는 성공 응답 스키마와, 요청과 응답의 `analysisId`가 같은지 검증한다. AI 오류 본문은
앱에 그대로 노출하거나 로그에 기록하지 않는다.

## 6. 주요 구현 파일

| 파일 | 역할 |
| --- | --- |
| `app/api/routes/speech_analyses.py` | multipart 제출, 상태 조회와 실패 분석 재요청 API |
| `app/services/audio_validation.py` | 크기, SHA-256, WAV 규격과 음성 데이터 누락 검사 |
| `app/services/audio_storage.py` | S3 업로드, Presigned GET과 삭제 |
| `app/services/speech_analysis_jobs.py` | 작업 모델, 메모리 테스트 저장소와 PostgreSQL 저장소 |
| `app/services/speech_analysis_pipeline.py` | 제출 서비스, 음성 대기열과 STT 처리 함수 |
| `app/services/speech_analysis_stats.py` | 작업이 끝나거나 실패할 때 남기는 처리 기록 한 줄(`speech_analysis_finished`) |
| `app/workers/base.py` | 임대, 처리와 실패 기록을 반복하는 worker 공통 골격 |
| `app/workers/speech_analysis.py` | 독립 worker 실행 진입점 |
| `app/clients/ai_server.py` | 내부 AI 서버 HTTP 클라이언트와 오류 매핑 |
| `alembic/versions/f8fd6d0e862c_initial_schema.py` | 작업 테이블을 포함한 initial migration |
| `database/init.sql` | 빈 개발 DB용 최신 bootstrap 스키마 |
| `tests/test_speech_analyses.py` | API, 중복 제출, worker와 AI 계약 테스트 |
| `tests/test_audio_storage.py` | S3 암호화, URL 수명과 삭제 어댑터 테스트 |

## 7. 데이터베이스

스키마는 `alembic/versions/f8fd6d0e862c_initial_schema.py`(`database/init.sql`과 같음)를
따른다. 회차 상태와 참여자 수는 `visit_sessions`에 저장하지 않고 작업과 평가로 계산한다.
`speech_analysis_jobs`에는 다음 정보를 저장한다.

```text
analysis_id
session_id                 실패하지 않은 작업은 한 면회당 하나
status
participant_count
s3_object_key              직접 식별정보와 원래 파일명 제외
size_bytes
sha256
data_expires_at
attempt_count
lease_expires_at           uploading, transcribing, generatingReport에서 필수
                           sttCompleted에서는 리포트로 넘기기 전 인계 임대
                           (STT 단독 실행과 리포트 재요청 작업은 비움)
error_code
audio_deleted_at
stt_completed_at
transcript                 sttCompleted, generatingReport에서만. 리포트 생성 입력
transcript_expires_at      STT 완료 후 24시간
transcript_deleted_at
created_at / updated_at / completed_at
```

전사문은 리포트 생성 요청(API 8-3)에 넣을 구간(시작, 끝, 화자 라벨, 문장)만 저장하고
단어별 시각과 확률은 저장하지 않는다. 작업이 끝나면 지운다. AI 응답 본문과 Presigned
URL은 저장하지 않는다.

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
SAEROK_SPEECH_AUDIO_RETENTION_SECONDS=86100
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
- BE 역할에는 필요한 버킷과 접두사 범위의 업로드, 조회 URL 발급, 삭제 권한만 부여
- `temporary/speech/` 객체의 `data_expires_at` 기한 삭제와 실패 대기열 실행을 별도 운영
- Lifecycle은 누락 방지용 보조 규칙. 일 단위 만료만으로 업로드 후 24시간 이내 삭제를 보장하지 않음
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

저장소의 `stt-server/`(처음 작성할 때는 `feature/ai-stt-pipeline` 브랜치)를 별도 작업 디렉터리 또는 장비에서 실행한다. AI
서버에는 모델, GPU 환경, 허용 S3 호스트와 최대 음성 크기 설정이 필요하다.

현재 AI 구현의 Whisper 실행 장치는 CUDA로 고정되어 있다. GPU가 없는 BE 개발 PC에서
`stt-server/`를 `uv sync`하는 것만으로는 실제 STT를 실행할 수 없다. 실제 통합
테스트에서는 AI 담당자가 GPU 장비에서 서버를 실행하고 BE가 접근할 수 있는 GPU 서버의 Tailscale 기본 주소를
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

AI 서버가 다른 장비에 있으면 `127.0.0.1` 대신 BE에서 접근 가능한 GPU 서버의 Tailscale 기본 주소(`http://<GPU 서버의 Tailscale IP>:8001`)를 사용한다. 현재 배포 절차는
[STT 운영 안내](../../stt-server/README.md#개인-gpu와-tailscale-운영)를 따른다. AI 서버는 외부에 인증 없이 공개하지 않으며 실제 사용자 자료를 외부
AI 서비스로 보내지 않는다. worker를 실행하기 전에 다음 생존 확인이 성공해야 한다.

```powershell
Invoke-RestMethod http://<AI_SERVER_HOST>:8001/health/live
```

### 10.3 GPU 없이 연결 흐름 확인

GPU가 없으면 고정된 합성 `SpeechAnalysisResult`를 반환하는 Mock AI 서버로 다음 연결
범위를 확인할 수 있다.

```text
FE 업로드 → BE API → S3 → PostgreSQL → worker
→ Mock AI 응답 → 전사 저장(sttCompleted) → 원본 삭제 시도 → FE 상태 조회
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

### 10.6 처리 기록

worker는 작업 하나가 끝나거나 실패할 때 `speech_analysis_finished` 한 줄을 남긴다(2026-11-09 PM
결정). JSON 로그의 필드는 다음과 같고, 대화 내용, 제목, 이름은 넣지 않는다. 모르는 값은 `null`이다.

| 필드 | 뜻 |
| --- | --- |
| `outcome`, `error_code` | `completed`, `sttCompleted`(`--stt-only`), `stopped`(다른 처리가 먼저 끝냄), `failed`와 실패 코드 |
| `analysis_id` | 작업 ID |
| `stt_server` | 결과를 돌려준 STT 서버(`primary`, `backup`). 리포트만 다시 만든 작업은 `null` |
| `audio_seconds`, `last_segment_end_seconds` | 녹음 길이와 마지막 전사 구간이 끝난 시각(초). 둘의 차이가 크면 전사가 일찍 끊긴 것이다 |
| `transcript_segments`, `transcript_chars`, `speaker_labels` | 전사 구간 수, 글자 수, 서로 다른 화자 라벨 수 |
| `report_body_chars` | 리포트 본문 글자 수 |
| `life_story_proposals_returned`, `life_story_proposals_kept` | 모델이 낸 이야기 후보 수와 AI 쪽에서 거르고 자른 뒤 남은 수 |
| `story_categories`, `sensitive_proposals` | 남은 후보의 분류별 수와 아픈 기억 표시 수 |
| `topic_proposals_returned`, `topic_proposals_kept` | 모델이 낸 주제 조정 수와 남은 수 |
| `model`, `prompt_version`, `token_usage` | 모델, 프롬프트 판(리포트와 변경 제안을 `+`로 이음), 토큰 수 |

카드 생성 worker는 저장을 마치면 `card_generation_completed`(묶음 ID, 카드 수 `cards`, 아픈 경험 카드 수
`sensitive_cards`, 모델, 프롬프트 판)를 남긴다.

## 11. 실제 API 통합 테스트

### 11.1 테스트 사전 데이터

처음 작성할 때(9월)는 면회 회차(5-1)와 보호자 평가(6-1) API가 없어 아래 행을 직접 만들어야
했다. 지금은 두 API가 있으므로 합성 개발 계정으로 로그인한 뒤 프로필 생성, 카드 생성(4-1),
회차 생성(`POST /api/v1/visit-sessions`), 평가 제출(`POST /api/v1/visit-sessions/{sessionId}/evaluation`)
순서로 API만으로 준비한다. 같은 순서를 `scripts/run_app_server_e2e.py`(#258, PR마다 실행하는
Product tests의 E2E 작업)와 `scripts/verify_api_cycle.py`([API 연결 검사](api-cycle-runner.md))가 쓴다.
API로 준비하면 다음 조건이 채워진다.

- 합성 개발 계정으로 로그인해 만든 `users` 행과 동의 이력
- 해당 사용자의 `profiles` 행
- 그 프로필에 속한 `visit_sessions` 행
- 보호자 평가를 마친 회차: `evaluated_at`, `evaluation_satisfaction`,
  `evaluation_reaction`이 채워짐

실제 사용자의 식별자나 면회 자료를 복사해서 테스트 데이터를 만들지 않는다. 합성 개발 계정과
명시적인 테스트 fixture만 사용한다.

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
`sttCompleted`와 `errorCode: null`을 확인한다. 기본 worker는 리포트 생성기(8-3)까지
부르므로 `SAEROK_ML_API_KEY`가 필요하다. 리포트 생성 함수가 실패하면 그 뒤 `failed`가 된다.
STT 경로만 확인할 때는 키 없이 `bash ./scripts/run_speech_worker.sh --stt-only --once`로
실행하고 `stt_completed`와 `audio_deleted`로 판단한다.

리포트까지 이어지는 흐름(6-1 → 6-2 → worker → 6-3, 7-x, 5-4)과 시간 제한, 늦은 결과는
실제 모델 없이 합성 데이터 테스트로 확인한다(`SAEROK_TEST_DATABASE_URL` 필요).

```bash
uv run pytest tests/test_report_flow.py tests/test_visit_report_generator.py \
  tests/test_speech_job_repository.py tests/test_speech_worker_options.py \
  tests/test_report_transcript_limit.py
```

`tests/test_report_transcript_limit.py`는 전사 기한이 임대 안에 끝나는 작업의 생성 미시작,
두 생성 호출 사이의 계정, 프로필, 회차 삭제와 작업 종료, 전사 만료 때 변경 제안 호출을 하지
않는지 검사한다.

### 11.5 DB 확인

민감한 원문을 조회하거나 출력하지 않는다. 상태와 삭제 시각만 확인한다.

```sql
SELECT status,
       participant_count,
       attempt_count,
       audio_deleted_at IS NOT NULL AS audio_deleted,
       stt_completed_at IS NOT NULL AS stt_completed,
       transcript IS NOT NULL AS transcript_stored,
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
transcript_stored = true
error_code = null
```

### 11.6 S3 삭제 확인

테스트에 사용한 `analysisId`의 임시 객체가 남아 있지 않아야 한다. 객체 목록 전체나
다른 작업 키를 로그 및 캡처에 남기지 말고 해당 합성 작업 하나만 확인한다.

정상 경로에서 즉시 삭제됐는지 확인한다. 실패하면 삭제 대기열에 남고
`audio_deleted_at`이 비어 있어야 한다. 기한 삭제 실행기와 Lifecycle 보조 규칙도
별도로 확인한다. 대기열 등록이나 Lifecycle 설정만으로 삭제 완료를 판단하지 않는다.

## 12. 필수 실패 시나리오

| 시나리오 | 예상 결과 |
| --- | --- |
| `participantCount=0` 또는 `9` | 422 `INVALID_REQUEST`, S3 업로드 없음 |
| WAV가 아닌 파일 | 422 `INVALID_AUDIO_FORMAT`, S3 업로드 없음 |
| 빈 파일 | 422 `INVALID_AUDIO`, S3 업로드 없음 |
| 헤더만 있거나 음성 데이터가 잘린 WAV | 422 `INVALID_AUDIO`, S3 업로드 없음 |
| 크기 상한 초과 | 413 `AUDIO_TOO_LARGE`, 작업 접수 안 됨. 본문이 음성 상한 + 1 MiB를 넘으면 끝까지 받지 않음 |
| 인증 없음 | 401 `UNAUTHENTICATED`, 본문을 읽기 전에 거절 |
| 다른 계정의 면회 | 404 `VISIT_SESSION_NOT_FOUND` |
| 보호자 평가 전 | 409 `EVALUATION_REQUIRED`, 업로드 없음 |
| 접수 후 실패한 면회를 다시 제출 | 전사가 남아 있으면 409 `REPORT_RETRY_AVAILABLE`(녹음 대신 재요청 API 사용). 전사가 없으면 새 작업으로 접수(202). 같은 실패 작업 ID로 한 재요청도 실패한 뒤 다시 재요청하면 409 `ANALYSIS_ALREADY_FAILED`(5-4에서 최신 ID 확인, #213) |
| S3 업로드 실패 | 503 `AUDIO_STORAGE_UNAVAILABLE`, 202 반환 안 함, 재제출 가능 |
| 업로드가 끝나기 전에 업로드 임대 만료나 계정, 프로필 삭제로 작업 행이 지워짐 | 503 `AUDIO_STORAGE_UNAVAILABLE`, 202 반환 안 함. 올라간 원본 키는 행이 없어도 삭제 대기열에 기록 |
| AI 연결 실패 | 작업 `failed`, `AI_SERVER_UNAVAILABLE` |
| AI 시간 초과(STT 응답 대기, 리포트 생성 전체 제한) | 작업 `failed`, `AI_SERVER_TIMEOUT`, 리포트 저장 없음 |
| STT 중 임대 만료 | 작업 `failed`, `WORKER_LEASE_EXPIRED`, 늦게 온 전사문 저장과 리포트 생성 없음 |
| 리포트 생성 중 임대 만료 | 작업 `failed`, `WORKER_LEASE_EXPIRED`, 늦게 온 결과 저장 없음 |
| 전사 저장 뒤 리포트 시작 전 worker 중단 | 인계 임대 동안 `sttCompleted` 유지. 끝나면 다음 worker가 같은 작업 ID로 리포트 생성, STT 반복 없음, 빠진 원본 삭제 요청은 대기열에 기록 |
| 위 작업의 남은 전사 기한이 임대 시간보다 짧음 | 이어받지 않음. 전사문 삭제, 작업 `failed`, `TRANSCRIPT_EXPIRED` |
| AI 응답 스키마 오류 | 작업 `failed`, `INVALID_AI_RESPONSE` |
| 리포트 생성 중 모델 연결 실패, 시간 초과 | 작업 `failed`, `AI_SERVER_UNAVAILABLE`, 저장 없음 |
| 리포트 생성 중 그 밖의 호출 실패, 잘린 응답, JSON 오류 | 작업 `failed`, `AI_SERVER_ERROR`, 저장 없음 |
| 카드 요약, 이야기 후보와 주제 조정이 모두 0건 | 작업 `completed`, 리포트만 저장(정상 완료) |
| 리포트 모델이 `ai/common/llm.py`의 `ENDPOINTS`에 없음 | worker 시작 안 함(`--stt-only` 제외) |
| 응답 `analysisId` 불일치 | 작업 `failed`, `INVALID_AI_RESPONSE` |
| S3 삭제만 실패 | 전사 저장과 리포트 생성은 계속. 삭제 대기열 유지, `audio_deleted_at` 미기록 |
| 같은 면회 반복 제출 | 새 객체를 만들지 않고 기존 활성 작업 반환 |
| STT 완료 후 24시간 안에 리포트 미저장 | 전사문 삭제, 작업 `failed`, `TRANSCRIPT_EXPIRED` |
| 남은 전사 기한이 생성 단계 임대 시간보다 짧은 `sttCompleted` 작업 | 리포트 생성 시작 안 함(외부 전송 없음), 전사문 삭제, 작업 `failed`, `TRANSCRIPT_EXPIRED` |
| 리포트 호출과 변경 제안 호출 사이에 계정, 프로필이나 회차 삭제 | 변경 제안 호출 안 함, 저장 없음. 작업 행은 연쇄 삭제됨 |
| 리포트 호출과 변경 제안 호출 사이에 작업 종료나 임대 만료 | 변경 제안 호출 안 함, 저장 없음, `WORKER_LEASE_EXPIRED`(먼저 남은 실패 코드는 유지) |
| 리포트 호출과 변경 제안 호출 사이에 전사 기한 경과 | 변경 제안 호출 안 함, 저장 없음, 전사문 삭제, 작업 `failed`, `TRANSCRIPT_EXPIRED` |

위 표에서 크기 상한 초과 줄의 "끝까지 받지 않음"과 인증 없음 줄의 "본문을 읽기 전에 거절"(#278),
전사 저장 뒤 리포트 시작 전 worker 중단 줄과 그 아래 줄(#280), 남은 전사 기한이 생성 단계 임대
시간보다 짧은 `sttCompleted` 작업 줄과 리포트 호출과 변경 제안 호출 사이의 세 줄(#279), 업로드가
끝나기 전에 작업 행이 지워진 줄(#283)은 2026-11-09 develop에 병합됐고 11/9 배포(run 42568179490)부터
운영에 있다.

오류 응답과 로그에서 WAV 내용, 전사문, Presigned URL, 객체 키, 인증 토큰과 AI 오류
본문이 노출되지 않는지도 함께 확인한다.

## 13. FE 연결 기준

FE는 녹음을 정상적으로 닫아 WAV 헤더가 완성된 뒤 업로드한다. 헤더만 있거나 중간에 잘려
음성 데이터가 헤더에 선언된 길이보다 짧은 파일은 BE가 `422 INVALID_AUDIO`로 거부한다.

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
- `completed`는 리포트와 변경 제안을 저장한 뒤에만 온다. `--stt-only` worker로는 오지 않는다.

## 14. 현재 제한과 후속 작업

- ADR-008은 아직 `proposed`이며 FE, AI, PM의 공동 확인이 남아 있다.
- 면회 회차 생성(5-1)과 보호자 평가(6-1) API는 처음 작성할 때 없었고 지금은 있다(11.1절).
- 실제 S3 버킷, IAM과 Lifecycle은 저장소 밖의 운영 환경에서 구성한다. 운영에서는 버킷과 역할이
  구성돼 녹음 업로드부터 리포트까지 동작했다([11/8 안정성 시험](stability-test-20261108.md)).
  S3 Lifecycle 설정은 11/6 점검 때 읽기 권한이 없어 확인하지 못했다(저장소 밖 팀 운영 배포 기록).
- 운영 설정은 기본 GPU 서버를 먼저 부르고 연결이 안 되면 ck 예비 서버로 한 번 전환한다
  ([STT 운영 절차](stt-operations.md)). 11/5 배포 확인
  ([#187 기록](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/187#issuecomment-6652039046))과
  11/8 시험([안정성 시험](stability-test-20261108.md)의 "한계") 모두 기본 서버에 연결되지 않아
  예비 서버로 처리됐다.
- 독립 실행 가능한 Mock AI HTTP 서버는 없으며 테스트의 `FakeAiServer`는 pytest에서만
  사용한다.
- worker가 멈춘 작업은 임대가 만료되면 정리한다. 업로드 중이던 작업은 지워 다시 제출할
  수 있게 하고, 처리 중이던 작업은 `WORKER_LEASE_EXPIRED`로 실패시킨다. 전사 저장 뒤 리포트
  시작 전에 멈춘 작업만 인계 임대가 끝난 뒤 리포트 생성을 이어받는다(3절, #280). 실패한 작업의
  자동 재시도와 취소는 없다. 실패한 회차는 사용자가 다시 요청한다(#213,
  `POST /api/v1/speech-analyses/{analysisId}/retry`, [분석 복구](speech-recovery.md)). 전사가
  남아 있으면 리포트만 다시 만들며, 이 재요청은 회차당 3회(`SAEROK_REPORT_RETRIES_PER_SESSION`)까지다
  (#285). develop 앱은 홈의 실패 안내("눌러서 분석 다시 요청하기")에서
  이 API를 부른다(#213). 앱 배포는 BE 배포와 별개라 그 변경이 든 앱 빌드가 설치돼야 사용자에게
  보인다.
- 기본 worker는 STT 뒤 리포트까지 만든다. `--stt-only`(development/test)는 `sttCompleted`에서
  멈춘다. 리포트 생성 제한 시간이 지난 뒤에도 이미 시작한 ML API 호출 하나는 생성 함수 쪽에서
  끊을 수 없어 끝날 때까지 남는다(결과는 저장하지 않음). 끊으려면 `ai/` 생성 함수가 마감을
  받아야 한다(AI 담당 후속).
- 전사문은 API 명세 8-1에 따라 리포트 생성을 다시 시도할 때 STT를 반복하지 않도록
  작업에 임시 저장한다. 리포트를 저장하면 지우고, 늦어도 STT 완료 후 24시간이 지나면
  worker가 매 주기에 확인해 지운다. 리포트 생성은 남은 기한이 생성 단계 임대 시간 이상일
  때만 시작하고, 변경 제안 호출 직전에 작업과 전사가 남아 있는지 다시 확인한다(3절, #279).
- 처음 작성할 때는 면회 목록 API가 없어 앱이 `analysisId`를 알고 있을 때만 단건 상태 조회가
  가능했다. 지금은 회차 목록 API 5-4(`GET /api/v1/profiles/{profileId}/visit-sessions`)가 회차마다
  `sessionStatus`와 `analysisId`를 돌려주므로, 앱을 다시 실행해도 서버 기록으로 최근 회차의
  상태를 다시 읽는다(`report_api.dart`의 `latestSession`).

이 제한들은 STT 연결 성공을 리포트 완성으로 오인하지 않기 위한 경계다. 확인되지 않은
전사나 리포트를 정상 결과처럼 표시하는 대체 경로를 추가하지 않는다.
