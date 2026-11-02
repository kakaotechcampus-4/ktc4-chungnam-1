# 새록

새록은 보호자가 면회 전에 확인된 생애 정보와 지난 면회의 반응을 참고해 대화 소재를 준비하고, 면회에서 확인된 이야기를 다음 회차에 활용하도록 돕는 Android 우선 Flutter 앱이다. 의료 진단, 치료 또는 기억 회복을 제공하지 않는다.

## 상태 표시

이 문서의 상태 표시는 2026-11-03 기준이다. 이후 바뀔 수 있다.

| 표시 | 뜻 |
| --- | --- |
| [운영 반영] | 11/3 새벽 운영 서버와 Play Console을 읽기 전용으로 확인했을 때 있던 것. 운영 이미지는 10/25 빌드라 develop보다 뒤처져 있다 |
| [develop 구현] | GitHub `develop`(`2f3c141`)에 병합된 코드. 운영 반영 여부는 따로 적는다 |
| [로컬 작업] | `develop` 위에 쌓은 로컬 통합 커밋에만 있고 GitHub에 올리지 않은 것. 합성 자료와 격리 DB로만 검사했다 |
| [미구현] | 코드가 없다 |
| [계획] | 아직 정하지 않았거나 준비 중이다 |

## 제품 원칙

- 의료 진단, 병세 예측, 치료 효과를 만들지 않는다.
- 최근 기억을 시험하는 질문이나 확인되지 않은 생애 정보를 만들지 않는다.
- 신뢰할 수 없는 분석을 정상 결과처럼 표시하거나 임의의 수치와 해석을 만들지 않는다. 코드로 아직 검사하지 못하는 부분은 [알려진 제한](#알려진-제한)에 적었다.
- AI가 만든 변경 제안은 보호자가 확인하기 전에 프로필과 일대기에 반영하지 않는다.
- 녹음 원본은 STT가 끝나면 바로 지우고 업로드 뒤 24시간을 넘겨 두지 않는 것이 기준이다. 이 기한을 운영에서 강제하는 설정은 아직 없다([알려진 제한](#알려진-제한)).
- 실제 사용자 자료, 마스킹한 실제 자료, API 키는 저장소, 로그, 테스트 자료에 남기지 않는다.

## 핵심 흐름

개수, 장수, 형식 같은 세부 값은 코드 기준이며 10/25 운영 빌드와 다를 수 있다.

| 단계 | 하는 일 | 상태 |
| --- | --- | --- |
| 로그인과 동의 | 구글 로그인 뒤 필수 동의 2종을 제출해야 계정이 생긴다 | [운영 반영] |
| 프로필 | 보호자 1명당 어르신 최대 3명. 기본 정보와 세부 정보 4칸(하시던 일, 고향, 취미, 가족) | [운영 반영] |
| 세부 정보 음성 입력 | 짧은 녹음을 서버(6-6)에 보내 글로 받아 입력칸에 채운다. 실패하면 글 입력으로 넘어간다 | 앱은 [develop 구현], 서버 API는 [로컬 작업] |
| 프로필 사진 | 어르신마다 사진 최대 5장을 서버에 올린다 | [develop 구현], 운영 앱 미반영 |
| 사진 설명 | 사진 분석 worker가 설명을 만들고, 보호자가 고친 설명은 AI 원문과 따로 저장해 다음 카드 입력에 우선 쓴다 | [로컬 작업]. 분석 worker는 합성 자료 전용이며 운영 환경에서는 실행을 거절한다 |
| 대화 카드 | card-worker가 카드 12장을 만든다. 1~9번 중에서 골라 면회를 시작하고 10~12번은 면회 중 보충 카드다 | [운영 반영] |
| 면회 | 기기에서 WAV 16kHz mono로 녹음하고 끝낼 때 참여자 수를 확인한다. 면회 사진 1장을 올릴 수 있다 | [운영 반영] 회차와 녹음 전송. 면회 사진은 [develop 구현], 운영 사용 미확인 |
| 소감 | 만족도, 어르신 반응, 카드별 사용 여부와 반응을 저장한 뒤에만 녹음을 서버로 보낸다 | [develop 구현] |
| 음성 분석과 리포트 | speech-worker가 STT와 화자 분리를 부르고 같은 작업에서 리포트와 변경 제안을 만든다 | [운영 반영] STT와 리포트 생성 |
| 변경 제안 확인 | 이야기 후보와 주제 조정(more, less, exclude)을 보호자가 고치거나 빼고 승인한다. 승인 전에는 반영하지 않는다 | [develop 구현], 운영 사용 미확인 |
| 다음 회차 반영 | 승인한 이야기와 주제 조정이 다음 카드 생성 입력에 들어간다 | [develop 구현] |
| 사실 정정 뒤 카드 갱신 | 프로필이나 일대기를 고치면 아직 쓰지 않은 카드로는 면회를 시작할 수 없고, `다음 대화 준비하기`로 카드 묶음 전체를 한 번 다시 만든다 | [develop 구현], 운영 미반영 |
| 분석 실패 후 다시 요청 | 남은 전사로 리포트만 다시 만들고(6-5), 전사가 없으면 기기에 남긴 녹음을 다시 보낸다 | [로컬 작업] |

카드, 리포트, 변경 제안, 사진 설명은 엘리스 ML API를 쓴다. STT는 faster-whisper와 pyannote 화자 분리를 쓴다. 모델 이름과 설정은 [AI README](ai/README.md)와 [STT 서버 README](stt-server/README.md)를 따른다.

## 구성

| 경로 | 역할 | 실행 형태 |
| --- | --- | --- |
| `app/` | Flutter 앱(Android, Application ID `app.saerok.android`) | 기기나 에뮬레이터 |
| `backend/` | FastAPI API, PostgreSQL 스키마와 Alembic migration, card-worker, speech-worker, 사진 분석과 삭제 대기열 실행기, 운영 점검 도구 | `uv` 로컬 실행 또는 Docker Compose |
| `ai/` | 카드, 리포트, 변경 제안 생성 패키지(사진 설명 생성은 [로컬 작업])와 합성 페르소나 시뮬레이터. DB를 읽거나 쓰지 않는다 | backend가 경로 의존성으로 설치해 worker 안에서 부른다 |
| `stt-server/` | Whisper ASR과 pyannote 화자 분리를 실행하고 결과를 시간축으로 결합하는 내부 FastAPI 서버 | GPU 서버. backend가 사설망으로 호출 |
| `evals/` | STT 시험 케이스 9개, 기대 결과, 합성 음성 생성 스크립트. 자동 채점 스크립트는 없다 | 로컬 |
| `docs/` | PM 제품 기준, 데이터 계약, API 명세, ADR, 처리 복구 기준, 법률 검토, 테크스펙, 제품 테스트 CI | - |

호출 흐름

1. 앱이 backend API를 HTTPS로 부른다. 로그인, 프로필, 사진, 카드 생성 요청, 회차, 평가, 녹음 전송, 리포트와 변경 제안 조회가 모두 이 API로 간다.
2. API는 PostgreSQL에 저장하고 카드 생성, 음성 분석, 사진 분석 요청을 작업 행으로 남긴다.
3. card-worker가 카드 생성 작업을 가져와 `ai/`의 카드 생성 패키지를 부른다.
4. 녹음은 S3 임시 저장소에 올라간다. speech-worker가 S3 Presigned GET URL을 `stt-server`에 넘기고, 전사를 저장한 뒤 원본 삭제를 시도한다. 이어서 리포트와 변경 제안을 만든다.
5. 사진과 녹음 행을 지우면 S3 객체 키가 삭제 대기열에 쌓인다. 대기열 실행기는 [로컬 작업]이며 운영에 배포하거나 주기 실행으로 연결하지 않았다.

## 로컬 실행

아래 명령은 각 영역 README, 배포 문서와 [제품 테스트 CI](docs/product-tests.md)에 적힌 것만 옮겼다. 세부 설정은 링크한 문서를 따른다. 실제 사용자 자료는 쓰지 않고 합성 데이터만 쓴다. `powershell` 블록은 Windows PowerShell에서, `bash` 블록과 `.sh` 스크립트는 Git Bash, WSL, macOS나 Linux 셸에서 실행한다.

### 준비물

| 준비물 | 쓰는 곳 |
| --- | --- |
| Docker와 Docker Compose | 로컬 PostgreSQL 17, card-worker |
| uv, Python 3.12 | backend, ai, stt-server |
| Flutter 3.44.8, Dart 3.12.2 | app |
| ML API 키(`SAEROK_ML_API_KEY`) | card-worker, speech-worker의 리포트 생성. 없으면 두 worker가 시작하지 않는다. 팀 키는 공개하지 않는다 |
| Google OAuth 웹 클라이언트 ID와 Android 앱 등록 | 앱 구글 로그인과 backend `SAEROK_GOOGLE_CLIENT_IDS`. 앱과 backend에 같은 클라이언트 ID를 넣는다 |
| GPU 서버(Linux x86_64) | stt-server |

키 없이 확인할 수 있는 범위는 API 서버 실행과 `/docs`, 각 영역 테스트, 로그인 없는 디버그 빌드의 목 데이터 화면이다. 카드 생성, 리포트 생성, 구글 로그인은 위 키와 클라이언트가 있어야 확인할 수 있다.

### 순서

1. 백엔드 설치. 저장소 루트에서 처음 한 번 실행한다([BE README](backend/README.md#실행과-테스트)).

   ```powershell
   cd backend
   uv python install 3.12
   uv sync
   ```

2. PostgreSQL. `backend/.env`에 `SAEROK_POSTGRES_PASSWORD`와 `SAEROK_DATABASE_URL`을 채운 뒤 `backend/`에서 실행한다. 값 형식은 [배포 문서](backend/docs/deployment.md#로컬에서-postgresql만-컨테이너로-띄우기)를 따른다.

   ```powershell
   docker compose --profile local-db up -d db
   uv run alembic upgrade head
   ```

3. API 서버. 기본 주소는 `127.0.0.1:8000`, API 문서는 `http://127.0.0.1:8000/docs`다. Android 에뮬레이터나 허가된 개발 단말과 연동할 때만 `SAEROK_BACKEND_HOST=0.0.0.0`을 붙인다.

   ```bash
   ./scripts/run_backend.sh
   ```

4. STT 서버(GPU 환경에서만). `stt-server/`에서 실행한다. 다른 기기의 backend와 연결할 때의 수신 주소와 접근 범위는 [STT 서버 README](stt-server/README.md#개인-gpu와-tailscale-운영)를 따른다.

   ```bash
   chmod +x scripts/run_stt_server.sh
   ./scripts/run_stt_server.sh
   curl http://127.0.0.1:8001/health/live
   ```

5. 음성 분석 worker. API 서버와 다른 터미널의 `backend/`에서 실행한다. 키 없이 STT만 확인할 때는 `--stt-only`를 쓴다(development, test 환경 한정, 작업은 `sttCompleted`에서 멈춘다).

   ```bash
   bash ./scripts/run_speech_worker.sh
   bash ./scripts/run_speech_worker.sh --stt-only --once
   ```

6. 카드 생성 worker. `compose.yml`의 `card-worker` 서비스로 띄운다([배포 문서](backend/docs/deployment.md)).

7. 앱. `app/`에서 실행한다. 처음 설치는 [환경 세팅](app/SETUP.md)을 따른다.

   ```bash
   flutter pub get
   flutter run --dart-define=SAEROK_GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID> --dart-define=SAEROK_API_BASE_URL=http://10.0.2.2:8000
   ```

   `SAEROK_API_BASE_URL`의 기본값 `http://10.0.2.2:8000`은 에뮬레이터에서 PC를 가리킨다. 실기기는 PC의 LAN 주소를 넘긴다. `--dart-define` 없이 실행한 디버그 빌드는 구글 로그인을 건너뛰고 합성 목 데이터로 화면을 보여준다. 이때는 서버를 부르지 않으며 로그아웃과 탈퇴도 동작하지 않는다. 설정이 준비되면 지울 임시 경로다([FE README](app/README.md#실행과-테스트)).

### 운영 점검과 복구 도구 [로컬 작업]

모두 `backend/`에서 실행한다. 운영 서버에서 실행한 기록은 없다. 운영 실행과 실제 자료 삭제는 별도 승인이 필요하다.

| 도구 | 기본 명령 | 기본 동작 | 문서 |
| --- | --- | --- | --- |
| 운영 상태 점검 | `uv run python -m app.ops.runtime_check` | 읽기 전용. migration revision, 작업 상태별 건수, 기한 지난 녹음 수를 JSON으로 출력 | [읽기 전용 운영 점검](backend/docs/runtime-check.md) |
| S3와 DB 대조 | `uv run python -m app.ops.storage_audit` | 읽기 전용. `--s3`는 버킷 목록까지 읽는다. `--enqueue-safe-expired`만 DB를 수정한다 | [S3 원본과 DB 참조 점검](backend/docs/storage-audit.md) |
| 삭제 대기열 실행 | `uv run python -m app.workers.storage_deletion --limit 100` | DB 조회만 하는 dry run. `--apply`에서만 S3 삭제와 확인을 한다 | [S3 삭제 대기열 실행](backend/docs/storage-deletion.md) |
| 사진 분석 worker | `uv run python -m app.workers.photo_analysis --synthetic-test-data --once` | 합성 사진만 있는 테스트 DB 전용. 운영 환경에서는 거절한다 | [프로필 사진 분석 연결](backend/docs/photo-analysis.md) |
| 배포 후 API 연결 검사 | `uv run --locked python scripts/verify_api_cycle.py` | 인수 없이 실행하면 검사 순서만 출력하고 요청을 보내지 않는다 | [API 연결 검사](backend/docs/api-cycle-runner.md) |
| 배포 전 기록과 백업 복원 검사 | `scripts/capture_release.py`, `scripts/verify_database_backup.py` | 이미지와 버전 기록, 격리 컨테이너 복원 검사. 필수 인수는 문서 참고 | [배포 전 백업, 버전 대조와 되돌리기](backend/docs/release-safety.md) |

## 테스트

명령은 [제품 테스트 CI](docs/product-tests.md)와 같다. CI 워크플로(`.github/workflows/product-tests.yml`)는 [로컬 작업]이며 GitHub Actions에서 실행한 기록은 아직 없다.

| 영역 | 실행 위치 | 명령 | 11/3 로컬 결과 (`1b3acaa`) |
| --- | --- | --- | --- |
| 앱 | `app/` | `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` | analyze 이슈 0, 테스트 715개 통과 (Flutter 3.44.8, `pub get --offline`로 설치) |
| 백엔드 | `backend/` | `uv sync --locked`, `uv run --locked pytest -ra` | 일회용 PostgreSQL 17 연결 시 557개 중 554 통과, 3 건너뜀. 건너뛴 3개는 별도 Docker 이미지나 복원용 컨테이너를 지정해야 도는 백업 복원, 이미지 패키지, worker 종료 검사다 |
| AI | `ai/` | `uv sync --locked`, `uv run --locked pytest -ra` | 일회용 PostgreSQL 17의 전용 DB 연결 시 113개 통과 |
| STT 서버 | `stt-server/` | `uv sync --locked`, `PYTHONPATH=src uv run --locked python -m unittest discover -s tests -v` | 27개 중 26 통과, 1 건너뜀. Windows에서 실행했으며 CI의 TorchCodec 합성 WAV 디코딩 검사는 실행하지 않았다 |
| 평가 자료 | `evals/fixtures/speech/` | 합성 음성 생성 스크립트 4개([평가 README](evals/README.md)) | 자동 채점 스크립트 없음 |

- 백엔드 DB 테스트는 `SAEROK_TEST_DATABASE_URL`, AI DB 테스트는 `TOPIC_REC_TEST_DATABASE_URL`이 있어야 돌고 없으면 건너뛴다. 두 값 모두 생성과 삭제가 허용된 전용 테스트 PostgreSQL만 가리켜야 한다. 건너뛴 실행은 DB 통합 검사 통과로 기록하지 않는다.
- 위 테스트는 외부 모델, S3, Google 인증을 대역으로 처리한다. 실제 모델 품질, GPU 실행, Android 마이크와 화면 잠금, Play 서명 빌드, 운영 배포, 실기기의 다음 회차 성공은 확인하지 않는다.
- 두 번째 면회 시작까지의 흐름은 실제 API 라우터와 PostgreSQL, worker를 연결한 [두 번째 회차 검증](backend/docs/second-visit-verification.md)에서 검사한다 [로컬 작업].
- 실제 모델을 부르는 평가 스크립트(`ai/card_generation/tests/eval/`)와 시뮬레이터(`ai/simulation/`)는 위 테스트에 들어가지 않는다.

## 배포와 시연

서버 주소, 인스턴스 정보, 키 파일과 `.env` 값은 공개 저장소의 문서, 이슈, PR에 쓰지 않는다.

| 대상 | 현재 | 상태 |
| --- | --- | --- |
| Android 앱 | Google Play 비공개 테스트(versionCode 3, 10/25 업로드). 테스터로 등록된 계정만 설치할 수 있다. 프로덕션 트랙은 비활성 | [운영 반영] |
| 백엔드 서버 | AWS EC2의 Docker Compose와 Caddy HTTPS. api, card-worker 이미지는 10/25 빌드라 정정 뒤 카드 갱신, 프로필 사진 업로드와 위 [로컬 작업]이 없다 | [운영 반영] |
| STT | 기본 STT 연결이 실패하면 예비 STT로 한 번 전환하는 speech-worker 임시 이미지로 운영 중이다. 전환 코드는 develop에 없고 열린 PR #188~#190에서 다룬다 | [운영 반영] 임시 이미지 |
| 로그인 없는 화면 확인 | 디버그 빌드를 `--dart-define` 없이 실행하면 합성 목 데이터로 화면을 볼 수 있다. 서버 기능은 확인할 수 없다 | [develop 구현] 임시 |
| 심사자 접근 방법, 시연 영상 | 테스터 등록 경로와 촬영 시점을 정하는 중 | [계획] |

| 문서 | 내용 |
| --- | --- |
| [컨테이너 실행과 개발 서버 배포](backend/docs/deployment.md) | Compose 서비스 구성, EC2 처음 설정과 갱신, worker 종료 유예 |
| [배포 전 백업, 버전 대조와 되돌리기](backend/docs/release-safety.md) | 승인 후 적용 순서와 이상이 생겼을 때의 기준 [로컬 작업] |
| [비동기 면회 음성 STT 구현 및 테스트 가이드](backend/docs/async-speech-analysis.md) | 음성 분석 구현 파일, 환경 설정, 합성 WAV 시험 |
| [FE README의 Play 업로드용 빌드](app/README.md#play-업로드용-빌드) | 업로드 키 서명과 versionCode 규칙 |
| [작업 중단과 실패 후 복구 기준](docs/architecture/processing-recovery.md) | 녹음 전송, STT, 리포트 실패 복구(상태 `proposed`) |

배포는 수동 절차다. 위 [로컬 작업] 도구와 절차를 운영에 적용한 기록은 없다.

## 알려진 제한

| 내용 | 상태 |
| --- | --- |
| 운영 이미지가 10/25 빌드라 develop의 정정 뒤 카드 갱신과 프로필 사진 업로드, 로컬 작업의 안전 보완이 운영에 없다 | 운영 미반영 |
| 녹음 원본의 24시간 상한을 운영에서 강제하지 못한다. 삭제 대기열 실행기와 기한 대조 도구는 [로컬 작업]이고, 운영 배포, 주기 실행, 음성 버킷 Lifecycle 보조 규칙은 적용하지 않았다 | 운영 설정 남음 |
| 사진 분석 동의를 계정별로 확인하는 필드가 DB에 없다. 그래서 사진 분석 worker는 합성 자료 전용이며 운영 Compose에 넣지 않았다 | [미구현] 동의 연결 |
| 빈 전사는 리포트 생성 전에 거절하고, 화자 라벨이 부족한데 새 이야기 후보가 오면 저장을 거절한다. 리포트 문장의 인물 귀속 전체를 코드로 검사하지는 않는다 | 검사는 [로컬 작업], 귀속 검사는 [미구현] |
| 카드 설명과 리포트, 변경 제안에서 치료 효과를 직접 보장하는 표현을 정규식으로 검사한다. 모든 우회 표현을 판정하지는 않는다 | [로컬 작업] |
| 녹음 원본 삭제가 실패해도 전사와 리포트는 계속 만들고 삭제 요청을 대기열에 남긴다 | [로컬 작업] |
| 실패한 분석의 수동 재요청(6-5)은 전사 보관 기한 안에서만 리포트를 다시 만든다. 자동 재시도는 없다 | [로컬 작업] |
| 세부 정보 음성 입력(6-6)의 처리 시간 상한은 실측 전이다 | [로컬 작업] |
| 발화량, 응답 지연 같은 관찰 수치는 계산하지 않는다. `docs/tech-spec.md`와 `docs/pm/presentation-qna.md`의 해당 내용은 과거 계획이다 | [미구현] |
| 실제 Android 마이크, 화면 잠금, 강제 종료, 실기기에서 두 번째 면회까지의 흐름은 검증하지 않았다 | 미검사 |

## 문서 지도

| 알고 싶은 내용 | 문서 | 비고 |
| --- | --- | --- |
| 목적별 정본 찾기 | [문서 안내](docs/README.md) | 같은 내용이 여러 곳에 있을 때 우선할 문서 |
| 제품 대상, 범위, 정정 처리 기준 | [PM 제품 기준](docs/pm/README.md) | 문서 기준은 구현 완료를 뜻하지 않는다 |
| 제품과 기술 청사진 | [테크스펙](docs/tech-spec.md) | 과거 계획 일부 남음 |
| 앱 화면, 경로, 실행 | [FE README](app/README.md), [환경 세팅](app/SETUP.md), [디자인 기준](app/DESIGN.md) | |
| API, DB, worker, 실행 | [BE README](backend/README.md), [DB 스키마](backend/database/init.sql) | |
| 카드, 리포트, 변경 제안 생성 | [AI README](ai/README.md), [카드 생성](ai/card_generation/README.md), [시뮬레이션](ai/simulation/README.md) | |
| STT와 화자 분리 | [STT 서버 README](stt-server/README.md), [STT 파이프라인 설계](stt-server/docs/stt-pipeline.md) | |
| 평가 자료 | [평가 README](evals/README.md) | |
| 앱과 BE, BE와 AI 사이 API | [API 명세](docs/architecture/api-spec.md), [데이터 계약](docs/architecture/data-contracts.md), [합성 목 데이터](docs/architecture/mock/README.md) | |
| 카드 첫 생성과 다음 면회 반영 설계 | [주제 카드 전체 설계 검토안](docs/architecture/card-generation-flow.md) | |
| PR 자동 테스트와 범위 | [제품 테스트 CI](docs/product-tests.md) | [로컬 작업] |
| 전사와 리포트 안전 검사 | [전사 입력 검사](backend/docs/speech-input-safety.md), [리포트 안전 검사](backend/docs/report-safety.md), [화자 검사](backend/docs/speaker-fact-boundary.md) | [로컬 작업] |
| 녹음 분석 복구와 삭제 | [수동 복구](backend/docs/speech-recovery.md), [삭제 실패 분리](backend/docs/audio-deletion-isolation.md), [짧은 음성 전사](backend/docs/short-speech-transcription.md) | [로컬 작업] |
| 기술 결정 | [ADR 목록](docs/architecture/decisions/README.md) | accepted는 구현 완료를 뜻하지 않는다 |
| 개인정보와 동의 | [법률 검토](docs/legal/README.md), [동의안](docs/legal/consent-draft.md), [기능 대응표](docs/legal/consent-mapping.md) | |
| 실제 환경 검증 기록 | [10/18 통합 검증](docs/pm/integration-verification-20261018.md) | |
| 협업 규칙 | [협업 규칙](CONTRIBUTING.md) | 브랜치, PR 단위, 검토 책임, 문서 갱신 |

## 개발 시작

1. `develop`을 최신 상태로 갱신한다.
2. 루트 `AGENTS.md` 또는 `CLAUDE.md`와 담당 영역의 같은 지침을 읽는다.
3. 최신 `develop`에서 작업 브랜치를 만들고 구현과 검증 뒤 `develop` 대상 PR을 올린다. PR 단위는 [협업 규칙](CONTRIBUTING.md#독립적으로-검증할-작업-단위)을 따른다.

실제 사용자 자료, 마스킹한 실제 자료, 시크릿, 로컬 DB와 모델 파일은 저장소에 올리지 않는다.
