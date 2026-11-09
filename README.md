# 새록

새록은 보호자가 면회 전에 확인된 생애 정보와 지난 면회의 반응을 참고해 대화 소재를 준비하고, 면회에서 확인된 이야기를 다음 회차에 활용하도록 돕는 Android 우선 Flutter 앱이다. 의료 진단, 치료 또는 기억 회복을 제공하지 않는다.

## 상태 표시

이 문서의 상태 표시는 2026-11-10 기준이다. 이후 바뀔 수 있다.

| 표시 | 뜻 |
| --- | --- |
| [운영 반영] | 운영 서버에 있는 것. 운영 서버는 11/10 01:41 승인 배포 workflow(Deploy run 42656825849)로 develop `83695093`을 배포했다 |
| [develop 구현] | GitHub `develop`(`83695093`)에 병합됐지만 운영 서버에는 아직 없는 것. 11/10 배포로 운영 서버 코드가 develop과 같아져, 11/9까지 병합한 BE 수정(#275, #277~#291)과 11/10 병합한 #295의 BE 변경도 모두 운영에 있다([알려진 제한](#알려진-제한)의 첫 줄). 11/9 병합한 STT 서버 기본값 변경(#276)은 BE 배포 대상이 아니며, 운영 기록에 따르면 예비 STT 서버에만 손으로 적용했다. 앱 화면은 Play 검토(11/8 현재 프로덕션 첫 게시 검토 중)가 끝나기 전까지 develop으로 빌드한 APK에서만 최신이라 이 표시로 적는다 |
| [PR 검토 중] | 열린 PR에만 있고 `develop`에 병합되지 않은 것. PR 번호를 함께 적는다. 합성 자료와 격리 DB로만 검사했다 |
| [미구현] | `develop`에 코드가 없고 검토 중인 PR도 없다 |
| [계획] | 아직 정하지 않았거나 준비 중이다 |

## 제품 원칙

- 의료 진단, 병세 예측, 치료 효과를 만들지 않는다.
- 최근 기억을 시험하는 질문이나 확인되지 않은 생애 정보를 만들지 않는다.
- 신뢰할 수 없는 분석을 정상 결과처럼 표시하거나 임의의 수치와 해석을 만들지 않는다. 코드로 아직 검사하지 못하는 부분은 [알려진 제한](#알려진-제한)에 적었다.
- AI가 만든 변경 제안은 보호자가 확인하기 전에 프로필과 일대기에 반영하지 않는다.
- 녹음 원본은 STT가 끝나면 바로 지우고 업로드 뒤 24시간을 넘겨 두지 않는 것이 기준이다. 이 기한을 운영에서 강제하는 설정은 아직 없다([알려진 제한](#알려진-제한)).
- 실제 사용자 자료, 마스킹한 실제 자료, API 키는 저장소, 로그, 테스트 자료에 남기지 않는다.

## 핵심 흐름

개수, 장수, 형식 같은 세부 값은 코드 기준이다. 서버는 11/10 배포분(`83695093`, develop과 같다), 앱은 develop 기준으로 적는다.

| 단계 | 하는 일 | 상태 |
| --- | --- | --- |
| 로그인과 동의 | 구글 로그인 뒤 필수 동의 2종을 제출해야 계정이 생긴다. 선택 동의는 서비스 개선, 알림 수신, AI 사진 분석 3종이고 설정의 계정 약관 동의에서 바꾼다 | [운영 반영]. AI 사진 분석 동의 항목(#257)과 설정의 동의 화면 분리(#271)는 앱 [develop 구현] |
| 프로필 | 보호자 1명당 어르신 최대 3명. 기본 정보와 세부 정보 4칸(하시던 일, 고향, 취미, 가족) | [운영 반영]. 보호자가 적은 관계를 휴대폰에만 두고 이름으로 부르는 화면(#270)은 [develop 구현] |
| 세부 정보 음성 입력 | 짧은 녹음을 서버(6-6)에 보내 글로 받아 입력칸에 채운다. 실패하면 글 입력으로 넘어간다 | 서버 API(#214)와 5분을 채운 녹음이 거절되던 문제의 수정(#267)은 [운영 반영], 앱 화면은 [develop 구현] |
| 프로필 사진 | 어르신마다 사진 최대 5장을 서버에 올린다 | 서버 API는 [운영 반영], 앱 화면은 [develop 구현] |
| 사진 설명 | 프로필 설정 갤러리에서 사진을 눌러 설명을 고친다. 보호자가 고친 설명은 AI 원문과 따로 서버에 저장해 다음 카드 입력에 우선 쓴다(3-3, #205). 갈 화면이 없는 갤러리 머리글 `수정하기`는 숨겼다(#209). 사진 삭제 API(3-4, #240)는 서버에 있고 앱의 삭제 버튼은 아직 없다. AI 사진 분석에 동의한 계정의 사진은 photo-worker가 설명을 만든다(#257). 동의하지 않은 계정은 "분석 중" 대신 직접 쓰는 칸을 보여주고(#261), 사진을 올리기 전에 동의 시트를 띄운다(#272). 동의를 거두면 서버가 저장된 AI 설명을 지운다(#288) | 서버 저장, photo-worker(#257), 동의 철회 때 AI 설명 삭제(#288)는 [운영 반영]. 고치는 화면, 미동의 처리(#261), 동의 시트(#272)는 앱 [develop 구현]. 11/9 실기기에서 동의 시트 뒤 업로드와 AI 설명 생성, 동의를 끈 뒤 AI 설명 삭제와 직접 쓰기 안내를 확인했다. 앱의 사진 삭제 버튼은 [미구현] |
| 대화 카드 | card-worker가 카드 12장을 만든다. 1~9번 중에서 골라 면회를 시작하고 10~12번은 면회 중 보충 카드다 | [운영 반영] |
| 면회 | 기기에서 WAV 16kHz mono로 녹음하고 끝낼 때 참여자 수를 확인한다. 면회 사진 1장을 올릴 수 있다. 녹음하는 동안에는 Android 화면이 저절로 꺼지지 않게 한다. 녹음 중 앱이 꺼지면 다음 실행 때 녹음 파일을 고쳐 다시 보낸다(#262) | [운영 반영] 회차와 녹음 전송. 화면 켜짐(#207), 녹음 복구(#262), 면회 사진 화면은 앱 [develop 구현]. 백그라운드 녹음 유지(포그라운드 서비스)는 [미구현] |
| 소감 | 만족도, 어르신 반응, 카드별 사용 여부와 반응을 저장한 뒤에만 녹음을 서버로 보낸다 | 서버는 [운영 반영], 앱 화면은 [develop 구현] |
| 음성 분석과 리포트 | speech-worker가 STT와 화자 분리를 부르고 같은 작업에서 리포트와 변경 제안을 만든다. 라벨 누락이나 인원 차이로 생성을 막지 않고, 불확실한 이야기 후보는 제안 이유에 확인 필요를 적도록 지시한다. 무음이나 소음에서 STT가 지어내는 알려진 문장은 빼고(#263, #267), 보호자에게 보이는 글에는 전사, 화자 같은 처리 과정의 말을 쓰지 않는다(#273) | [운영 반영] STT, 리포트 생성, 화자 조건 제거(#251), 알려진 무음 문장 거르기(#263), 나뉘어 온 문장 거르기(#267), 처리 과정의 말 빼기(#273). STT 서버가 말소리 구간만 전사하게 바꾼 기본값(#276)은 develop에 병합됐고, 운영 기록에 따르면 11/9 예비 STT 서버에만 손으로 적용했다([배포와 시연](#배포와-시연)의 STT 줄) |
| 변경 제안 확인 | 이야기 후보와 주제 조정(more, less, exclude)을 보호자가 고치거나 빼고 승인한다. 승인 전에는 반영하지 않는다 | 서버는 [운영 반영], 앱 화면은 [develop 구현]. 운영에서 보호자 승인까지 써 본 기록은 없다 |
| 다음 회차 반영 | 승인한 이야기와 주제 조정이 다음 카드 생성 입력에 들어간다 | 서버는 [운영 반영]. 운영에서 두 번째 면회까지 이어 본 기록은 없다 |
| 화면 낭독(#180) | 카드 고르기, 면회 녹음과 카드 꺼내기, 소감, 리포트와 변경 제안, 세부 정보 음성 입력 등 핵심 흐름에서 TalkBack이 읽을 이름, 선택 상태, 읽기 순서와 대비를 보완했다 | [develop 구현], #208. 위젯 테스트만 했고 실기기 TalkBack 확인과 낭독 문구의 PM 확인이 남았다 |
| 사실 정정 뒤 카드 갱신 | 프로필이나 일대기를 고치면 아직 쓰지 않은 카드로는 면회를 시작할 수 없고, 홈의 `오늘의 대화카드 받기`로 카드 묶음 전체를 한 번 다시 만든다. 사진 설명을 고치거나 사진을 지울 때도 같다. AI 사진 분석 동의를 거둬 보호자 설명이 없는 사진의 AI 설명이 지워질 때도 같고, 이때는 카드를 만드는 중이어도 동의 변경을 거절하지 않는다(#288). 변경 제안 확인(7-4)에서 주제 조정을 승인할 때도 같은 규칙을 따르고, 카드를 만드는 중이면 409로 거절한다(#277). 사진 분석이 끝난 것만으로는 받아 둔 카드를 다시 만들 대상으로 바꾸지 않고 다음 카드부터 반영한다(#275) | 서버는 #277, #275, #288을 포함해 [운영 반영], 앱 화면은 [develop 구현]. 앱은 7-4의 이 409를 일반 실패 문구("처리하지 못했어요. 잠시 뒤 다시 시도해주세요.")로 보여준다. 11/9 배포 전 운영 서버(`9c2b8276`)는 사진 분석이 끝나면 받아 둔 카드를 다시 만들 대상으로 바꿔 온보딩 `마치기`로 받은 첫 카드가 막힐 수 있었다. 11/9 실기기에서 사진 분석이 끝나기 전에 받아 둔 카드로 분석이 끝난 뒤에도 면회를 시작할 수 있음을 확인했다(팀 운영 기록) |
| 분석 실패 후 다시 요청 | 남은 전사로 리포트만 다시 만들고(6-5, 면회 회차당 3회까지, #285), 전사가 없으면 기기에 남긴 녹음을 다시 보낸다. 이를 위해 실패한 분석의 전사를 즉시 지우지 않고 최초 STT 저장 후 24시간의 남은 기한 동안 보관한다 | 서버(#213, #285)는 [운영 반영], 앱 화면은 [develop 구현]. 실패 전사 보관 변경은 2026-11-03 PM이 승인했고 동의 문구 반영은 운영 적용 전에 확인하기로 했다. #213은 11/5 운영 배포(#187의 배포 기록)부터 운영에 있으나, 이 보관을 실제 동의 화면 문구에 반영하는 일은 남아 있다([동의안](docs/legal/consent-draft.md)) |
| 리포트 완료 알림 | 리포트가 완료되면 알림 수신에 동의한 계정의 등록 기기로 FCM 푸시를 보낸다. 알림을 누르면 그 리포트를 연다 | 서버는 [운영 반영]. 앱의 기기 등록 수정(#259), 재등록과 알림 열기(#264)는 [develop 구현]. 11/7, 11/8 Galaxy S22에서 운영 서버로 받는 것을 확인했다(11/8 안정성 시험 39건 모두 도착) |

카드, 리포트, 변경 제안은 엘리스 ML API를 쓴다. STT는 faster-whisper와 pyannote 화자 분리를 쓴다. 모델 이름과 설정은 [AI README](ai/README.md)와 [STT 서버 README](stt-server/README.md)를 따른다.

## 구성

| 경로 | 역할 | 실행 형태 |
| --- | --- | --- |
| `app/` | Flutter 앱(Android, Application ID `app.saerok.android`) | 기기나 에뮬레이터 |
| `backend/` | FastAPI API, PostgreSQL 스키마와 Alembic migration, card-worker, speech-worker, photo-worker. 삭제 대기열 실행기와 운영 점검 도구 포함 | `uv` 로컬 실행 또는 Docker Compose |
| `ai/` | 카드, 리포트, 변경 제안, 사진 설명(`photo_analysis/`) 생성 패키지와 합성 페르소나 시뮬레이터. 생성 패키지는 DB를 읽거나 쓰지 않는다. 시뮬레이터는 `TOPIC_REC_DATABASE_URL`의 합성 DB를 쓴다 | backend가 경로 의존성으로 설치해 worker 안에서 부른다 |
| `stt-server/` | Whisper ASR과 pyannote 화자 분리를 실행하고 결과를 시간축으로 결합하는 내부 FastAPI 서버 | GPU 서버. backend가 사설망으로 호출 |
| `evals/` | STT 시험 케이스 9개, 기대 결과, 합성 음성 생성 스크립트. 자동 채점 스크립트는 없다 | 로컬 |
| `docs/` | PM 제품 기준, 데이터 계약, API 명세, ADR, 처리 복구 기준, 법률 검토, 테크스펙 | - |

호출 흐름

1. 앱이 backend API를 HTTPS로 부른다. 로그인, 프로필, 사진, 카드 생성 요청, 회차, 평가, 녹음 전송, 리포트와 변경 제안 조회가 모두 이 API로 간다.
2. API는 PostgreSQL에 저장하고 카드 생성, 음성 분석, 사진 분석 요청을 작업 행으로 남긴다.
3. card-worker가 카드 생성 작업을 가져와 `ai/`의 카드 생성 패키지를 부른다.
4. photo-worker는 AI 사진 분석에 동의한 계정의 프로필 사진만 가져와 `ai/`의 사진 설명 함수를 부르고 설명을 저장한다(#257, [사진 분석](backend/docs/photo-analysis.md)). 동의하지 않은 계정의 사진은 분석하지 않고 대기로 남긴다.
5. 녹음은 S3 임시 저장소에 올라간다. speech-worker가 S3 Presigned GET URL을 `stt-server`에 넘기고, 전사를 저장한 뒤 원본 삭제를 시도한다. 이어서 리포트와 변경 제안을 만든다.
6. 사진과 녹음 행을 지우면 S3 객체 키가 삭제 대기열에 쌓인다. 대기열을 처리해 S3 객체를 지우는 실행기(#204)는 운영 이미지에 들어 있지만 compose 서비스가 아니라 손으로 실행하는 명령이다. 운영 기록에 따르면 11/6에 조회 모드로 대상만 확인했고 실제 삭제(`--apply`)는 PM 결정으로 보류했다. 주기 실행을 설치한 기록은 없다.

## 로컬 실행

아래 명령은 각 영역 README와 배포 문서에 적힌 것만 옮겼다. 세부 설정은 링크한 문서를 따른다. 실제 사용자 자료는 쓰지 않고 합성 데이터만 쓴다. `powershell` 블록은 Windows PowerShell에서, `bash` 블록과 `.sh` 스크립트는 Git Bash, WSL, macOS나 Linux 셸에서 실행한다.

### 준비물

| 준비물 | 쓰는 곳 |
| --- | --- |
| Docker와 Docker Compose | 로컬 PostgreSQL 17, card-worker |
| uv, Python 3.12 | backend, ai, stt-server |
| Flutter 3.44.8, Dart 3.12.2 | app |
| ML API 키(`SAEROK_ML_API_KEY`) | card-worker의 카드 생성, speech-worker의 리포트 생성, photo-worker의 사진 설명. 없으면 세 worker가 시작하지 않는다. photo-worker는 사진 버킷 설정도 있어야 시작한다. 팀 키는 공개하지 않는다 |
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

7. 사진 분석 worker. `compose.yml`의 `photo-worker` 서비스(`workers` profile)로 띄운다. 한 번만 처리할 때는 `backend/`에서 `uv run python -m app.workers.photo_analysis --once`를 쓴다. AI 사진 분석에 동의한 계정의 사진만 처리한다([사진 분석](backend/docs/photo-analysis.md)).

8. 앱. `app/`에서 실행한다. 처음 설치는 [환경 세팅](app/SETUP.md)을 따른다.

   ```bash
   flutter pub get
   flutter run --dart-define=SAEROK_GOOGLE_SERVER_CLIENT_ID=<웹 클라이언트 ID> --dart-define=SAEROK_API_BASE_URL=http://10.0.2.2:8000
   ```

   `SAEROK_API_BASE_URL`의 기본값 `http://10.0.2.2:8000`은 에뮬레이터에서 PC를 가리킨다. 릴리스 빌드는 이 주소가 비어 있거나 https가 아니거나 형식이 틀리면(query, fragment 포함), 또는 구글 클라이언트 ID가 비어 있으면 로그인 대신 설정 오류 화면을 띄운다(#209). 실기기는 PC의 LAN 주소를 넘긴다. `--dart-define` 없이 실행한 디버그 빌드는 구글 로그인을 건너뛰고 합성 목 데이터로 화면을 보여준다. 이때는 서버를 부르지 않으며 로그아웃과 탈퇴도 동작하지 않는다. 설정이 준비되면 지울 임시 경로다([FE README](app/README.md#실행과-테스트)).

### 운영 점검과 복구 도구

아래 도구는 `backend/`에서 실행한다. 운영에서 실행한 기록이 있는 것은 읽기 전용 점검과 배포 검사다. 승인 배포 workflow는 배포마다 백업 복원 검사(`verify_database_backup.py`, 2단계), 배포 기록(`capture_release.py`, 컨테이너 교체 뒤 8단계)과 운영 상태 점검(교체 전후)을 실행한다. 운영 기록에 따르면 운영 상태 점검은 11/7부터 서버의 알림 timer가 5분마다 실행하고, S3와 DB 대조와 삭제 대기열 실행기는 11/6에 읽기 전용으로만 실행했다(`--s3`는 Lifecycle 조회 권한이 없어 실패). 실제 자료 삭제는 별도 승인이 필요하다. 사용법은 `backend/docs/`의 각 문서에 있다.

| 도구 | 기본 동작 | 문서 |
| --- | --- | --- |
| 운영 상태 점검(`app.ops.runtime_check`) | 읽기 전용. migration revision, 작업 상태별 건수, 기한 지난 녹음 수, worker와 예비 STT 상태를 JSON으로 출력. 문제 목록이 바뀔 때만 Discord로 알린다 | [runtime-check](backend/docs/runtime-check.md) |
| S3와 DB 대조(`app.ops.storage_audit`) | 읽기 전용. `--s3`는 버킷 목록까지 읽는다. `--enqueue-safe-expired`만 DB를 수정한다 | [storage-audit](backend/docs/storage-audit.md) |
| 삭제 대기열 실행(`app.workers.storage_deletion`) | DB 조회만 하는 dry run. `--apply`에서만 S3 삭제와 확인을 한다 | [storage-deletion](backend/docs/storage-deletion.md) |
| 배포 후 API 연결 검사(`scripts/verify_api_cycle.py`) | 인수 없이 실행하면 검사 순서만 출력하고 요청을 보내지 않는다 | [api-cycle-runner](backend/docs/api-cycle-runner.md) |
| 배포 전 기록과 백업 복원 검사(`scripts/capture_release.py`, `scripts/verify_database_backup.py`) | 이미지와 버전 기록, 격리 컨테이너 복원 검사 | [release-safety](backend/docs/release-safety.md) |
| 오래된 백업 정리(`scripts/prune_database_backups.py`) | 지울 목록만 출력. `--apply`에서만 만든 지 14일이 지난 백업을 지우고, 복원 확인된 가장 최근 백업 1개는 남긴다. 매일 실행할 systemd timer는 `backend/ops/backup-prune/`에 있다. 승인 배포 workflow는 이 timer를 설치하지 않고, 서버에 설치한 기록도 없다 | [release-safety](backend/docs/release-safety.md#오래된-백업-정리14일-보관) |

## 테스트

| 영역 | 실행 위치 | 명령 | 출처 |
| --- | --- | --- | --- |
| 앱 | `app/` | `flutter pub get`, `flutter analyze`, `flutter test` | [FE README](app/README.md#실행과-테스트) |
| 백엔드 | `backend/` | `uv sync`, `uv run pytest` | [BE README](backend/README.md#실행과-테스트) |
| AI | `ai/` | `uv run pytest` | [카드 생성 README](ai/card_generation/README.md) |
| STT 서버 | `stt-server/` | `PYTHONPATH=src uv run python -m unittest discover -s tests -v` | [STT 서버 README](stt-server/README.md) |
| 평가 자료 | `evals/fixtures/speech/` | 합성 음성 생성 스크립트 4개 | [평가 README](evals/README.md). 자동 채점 스크립트 없음 |

- 백엔드 DB 테스트는 `SAEROK_TEST_DATABASE_URL`, AI DB 테스트는 `TOPIC_REC_TEST_DATABASE_URL`이 있어야 돌고 없으면 건너뛴다. 두 값 모두 생성과 삭제가 허용된 전용 테스트 PostgreSQL만 가리켜야 한다. 건너뛴 실행은 DB 통합 검사 통과로 기록하지 않는다.
- 위 테스트는 외부 모델, S3, Google 인증을 대역으로 처리한다. 실제 모델 품질, GPU 실행, Android 마이크와 화면 잠금, Play 서명 빌드, 운영 배포, 실기기의 다음 회차 성공은 확인하지 않는다.
- PR마다 위 테스트를 GitHub Actions에서 돌린다([product-tests.yml](.github/workflows/product-tests.yml), #211). 두 번째 면회 시작까지 실제 API 라우터와 PostgreSQL, worker를 연결해 보는 검사(#192, [문서](backend/docs/second-visit-verification.md))와 앱의 API 코드로 실제 BE를 부르는 E2E(#226, [FE README](app/README.md#앱과-실제-서버-e2e))도 있다. 이 E2E는 #258부터 PR마다 `App and backend E2E (synthetic boundaries)` 작업으로 돈다. 구글 로그인, 모델, S3, STT는 합성 대역이다.
- 실제 모델을 부르는 평가 스크립트(`ai/card_generation/tests/eval/`)와 시뮬레이터(`ai/simulation/`)는 위 테스트에 들어가지 않는다.

## 배포와 시연

서버 주소, 인스턴스 정보, 키 파일과 `.env` 값은 공개 저장소의 문서, 이슈, PR에 쓰지 않는다.

| 대상 | 현재 | 상태 |
| --- | --- | --- |
| Android 앱 | Google Play 프로덕션 첫 게시를 검토 중이다(11/8). 그동안 비공개 테스트 트랙에도 새 빌드를 올리지 못해 이전 빌드가 남아 있다. 시연과 테스트는 develop으로 빌드한 APK를 쓰고, 앱이 바뀌면 GitHub Releases에 올린다(11/8 팀 결정). 푸시가 되려면 빌드에 `google-services.json`이 들어가야 한다. Play에 올리는 서명 빌드는 업로드 키를 가진 릴리스 담당자가 만든다([FE README](app/README.md#play-업로드용-빌드)). GitHub Releases의 APK는 11/8 18:31 KST에 게시한 빌드라 그 뒤 병합한 앱 변경(#270, #271, #272와 #295)은 들어 있지 않다. #295의 앱 변경(변경 사항 확인의 이야기 분류 고르기, 리포트의 녹음 파일 공유, 아픈 경험 카드의 `조심스러운 이야기` 표시)은 Play에 있는 빌드에도 없어서 새 APK를 빌드해야 휴대폰에 간다. 아래 백엔드 배포가 성공해도 앱이 출시된 것은 아니다 | 검토 중 |
| 백엔드 서버 | AWS EC2의 Docker Compose와 Caddy HTTPS. 11/10 Release build(run 42653146404) 뒤 승인 배포 workflow(Deploy run 42656825849, PM 승인)로 01:41에 develop `83695093`을 배포했다. 11/9 배포분 `59190ba7`에 더해진 것은 #293(개인정보 처리방침과 엘리스 ML API 문서)과 #295(이야기 후보 `proposals-8`, 리포트 `report-6`, 카드 생성 2판과 아픈 경험 카드 표시, 처리 로그에 개수만 남기기, migration `9c4e2b7a1f63`)뿐이다. 팀이 서버에서 확인한 바로는 배포 뒤 migration은 `9c4e2b7a1f63`이고, api, card-worker, speech-worker, photo-worker가 다시 시작해 정상이며 `/health/ready`는 200이다. 운영 설정에 카드 생성 판 번호를 따로 두지 않아 코드 기본값인 2판으로 카드를 만든다. 그 전 11/9에는 Release build(run 42567070594, uv 설치 단계의 일시 실패 뒤 실패한 작업만 다시 실행) 성공 뒤 승인 배포 workflow(Deploy run 42568179490)로 14:42에 develop `59190ba7`을 배포했다. 첫 시도는 사전 점검에서 진행 중인 카드 생성 작업 1건을 보고 멈췄고 서버와 DB는 바뀌지 않았다. 다시 실행한 두 번째 시도는 사전 점검부터 DB 백업과 격리 복원 검사, 배포 기록까지 1~8단계를 모두 통과했고 migration `e7c3a1f94d20` → `202cdc671d82`(#286) → `685f243e9f1f`(#291)를 적용했다. 사후 점검은 live, ready 200이고 주의 항목(`DELETION_QUEUE`, `OVERDUE_AUDIO`)은 이전 배포와 같다. 그 전에는 11/8에 같은 방식으로 `9e292149`(run 42385596940, photo-worker 첫 실행), `42938250`(run 42397653863), `9c2b8276`(run 42485750502)을 차례로 배포했다. #276은 STT 서버 변경이라 이 workflow의 배포 대상이 아니다. #278이 바꾼 `Caddyfile`은 caddy를 따로 다시 만들어야 적용되는데, 팀 운영 기록에는 11/9 배포 뒤 caddy를 다시 만든 기록이 없다 | [운영 반영] |
| STT | 기본 STT 연결이 실패하면 예비 STT로 한 번 전환한다(#189, #188, #190). 11/8에는 기본 STT 서버에 연결되지 않아 예비 STT로 처리했다. 말소리 구간만 전사하는 기본값(#276, VAD 켬, 앞 문장 조건 끔)은 운영 기록에 따르면 11/9 예비 STT 서버에 손으로 적용했고, 기본 STT 서버(개인 GPU)는 아직 갱신하지 않았다. 승인 배포 workflow는 STT 서버를 배포하지 않는다 | [운영 반영], 기본 STT 연결 문제와 기본 STT의 #276 적용은 남음 |
| 로그인 없는 화면 확인 | 디버그 빌드를 `--dart-define` 없이 실행하면 합성 목 데이터로 화면을 볼 수 있다. 서버 기능은 확인할 수 없다 | [develop 구현] 임시 |
| 심사자 접근 방법, 시연 영상 | 테스터 등록 경로와 촬영 시점을 정하는 중 | [계획] |

| 문서 | 내용 |
| --- | --- |
| [컨테이너 실행과 개발 서버 배포](backend/docs/deployment.md) | Compose 서비스 구성, EC2 처음 설정과 갱신, worker 종료 유예. 승인 배포 workflow는 운영 서버 저장소를 배포 커밋에 detached로 체크아웃하므로 운영 서버 갱신에는 이 문서의 손 갱신 절차를 쓰지 않는다. 다만 workflow는 caddy를 교체하지 않아, `Caddyfile`이 바뀐 배포(#278)는 Deploy 뒤 caddy만 이 문서의 갱신 절에 적힌 명령으로 다시 만든다 |
| [STT 예비 서버 전환](backend/docs/stt-backup.md), [ck 예비 서버 SSH 연결](backend/docs/stt-backup-ssh.md) | 예비 STT 설정, 전환 조건과 SSH 운영 연결 |
| [비동기 면회 음성 STT 구현 및 테스트 가이드](backend/docs/async-speech-analysis.md) | 음성 분석 구현 파일, 환경 설정, 합성 WAV 시험 |
| [FE README의 Play 업로드용 빌드](app/README.md#play-업로드용-빌드) | 업로드 키 서명과 versionCode 규칙 |
| [배포 후보 빌드와 승인 배포 workflow](docs/deploy-workflows.md) | CI 다음 단계. Release build로 백엔드 이미지를 빌드해 검사하고 이미지 기록, OpenAPI 스키마와 배포 후보 기록을 남긴다. 앱 빌드는 설정 두 값이 없어 지금은 건너뛰므로 APK와 AAB는 나오지 않는다([알려진 제한](#알려진-제한)). Deploy로 승인 뒤 운영 서버에 백업, migration, 교체를 실행 |
| [작업 중단과 실패 후 복구 기준](docs/architecture/processing-recovery.md) | 녹음 전송, STT, 리포트 실패 복구(상태 `proposed`) |

운영 서버 배포는 승인 배포 workflow([배포 후보 빌드와 승인 배포 workflow](docs/deploy-workflows.md))로 한다.

## 알려진 제한

| 내용 | 상태 |
| --- | --- |
| 운영 서버는 develop `83695093`(11/10 01:41 배포, Deploy run 42656825849)이다. 11/9까지 병합한 BE 수정(#275, #277~#291)과 11/10 병합한 #295의 BE 변경(migration `9c4e2b7a1f63`, 카드 생성 2판 포함)은 모두 운영에 있다. 다만 #287의 매일 백업 정리 timer는 승인 배포 workflow가 설치하지 않고 서버에 설치한 기록도 없다. STT 서버 기본값 변경(#276)은 BE 배포로 반영되지 않으며 운영 기록에 따르면 예비 STT 서버에만 손으로 적용했다. Play 앱은 검토 중이라 최신 앱 화면이 없다 | 앱, 기본 STT의 #276, 백업 정리 timer는 운영 미반영 |
| 녹음 원본의 24시간 상한을 운영에서 강제하지 못한다. 삭제 대기열 실행기와 기한 대조 도구(#204)는 운영 이미지에 있지만, 운영 기록에 따르면 실제 삭제는 PM 결정으로 보류했고 주기 실행을 설치한 기록은 없다. 음성 버킷 Lifecycle 보조 규칙은 적용하지 않았다 | 운영 설정 남음 |
| AI 사진 분석은 동의한 계정의 프로필 사진만 분석한다(#257). 11/8 운영에서 공개 사진 43장을 두 번씩 분석해 86건 모두 완료됐고 설명의 주요 내용은 같았지만, 작고 어두운 옛 사진은 세부가 엇갈렸다. 동의를 철회하면 이미 만든 AI 설명을 지우기로 11/9 PM이 정했고, 그 서버 처리(#288)는 11/9 배포로 운영에 들어갔다. AI 분석 동의와 별개인 사진 보관 동의는 없어서 업로드 때 보관 동의를 확인하지 않는다 | 서버와 철회 처리 [운영 반영], 사진 보관 동의 [미구현] |
| BE는 STT가 무음이나 소음에서 지어내는 문장을 알려진 문장 목록으로 거른다(#263, #267). 목록에 없는 문장, 실제 대화 중간에 섞인 문장, 배경 음악 가사는 남는다. 식당 웅성거림처럼 "감사합니다"만 옮겨진 녹음은 리포트가 만들어진다(PM 결정으로 거르지 않는다). STT 쪽 무음 판정은 #276(VAD 켬, 앞 문장 조건 끔)으로 develop에 들어왔다. 11/9 비교에서 지어낸 말은 거의 사라졌지만 짧은 말을 일부 빠뜨리고 아주 작은 목소리를 버릴 수 있다([전사 옵션 비교](stt-server/docs/vad-condition-comparison-20261109.md)) | 목록 방식은 [운영 반영], VAD는 예비 STT에만 적용(운영 기록) |
| CI의 Release build가 앱을 빌드할 때 푸시 설정을 넣는 GitHub 시크릿 `GOOGLE_SERVICES_JSON_BASE64`(#265)는 11/8 등록했다. 다만 11/9 확인 시점까지의 Release build 실행은 모두(예: 11/8 run 42485330291, 11/9 운영 배포분 `59190ba7`의 run 42567070594) 앱 빌드 설정(`SAEROK_API_BASE_URL`, `SAEROK_GOOGLE_SERVER_CLIENT_ID`)이 없어 앱 빌드를 건너뛰었다. 이때 artifact는 백엔드 이미지 기록, OpenAPI 스키마와 배포 후보 기록뿐이고 APK와 AAB는 없다. 업로드 키 시크릿도 저장소에 없어, 설정을 넣어 CI가 앱을 만들더라도 디버그 키로 서명되어 Play에 올릴 수 없다. 팀원이 로컬에서 빌드할 때 파일을 넣으면 그 빌드는 푸시를 받는다 | CI 앱 빌드 설정 남음 |
| 11/8 운영 안정성 시험(면회 44회, 음성 입력 94건, 사진 86건, 푸시 39건)의 결과와 남은 문제는 [stability-test-20261108.md](backend/docs/stability-test-20261108.md)에 있다 | 기록 |
| 빈 전사는 생성 전에 거절한다. [#251](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/pull/251)은 라벨 누락이나 인원 차이에도 리포트와 제안을 생성하고, 불확실한 이야기 후보는 제안 이유에 확인 필요를 적도록 지시한다. 리포트의 인물 귀속이나 확인 필요 문구의 적절성을 코드로 검사하지는 않는다 | 생성 차단 제거는 [운영 반영], 귀속 검사는 [미구현] |
| 리포트와 변경 제안(#198), 카드 문안(#212)에서 치료 효과를 직접 보장하는 표현을 정규식으로 검사한다. 모든 우회 표현을 판정하지는 않는다. 카드 질문의 최근 기억 시험은 코드로 검사하지 않고 프롬프트에 맡긴다 | [운영 반영] |
| #203은 녹음 원본 삭제가 실패해도 전사와 리포트는 계속 만들고 삭제 요청을 대기열에 남긴다 | [운영 반영] |
| #213의 실패한 분석 수동 재요청(6-5)은 전사 보관 기한 안에서만 리포트를 다시 만든다. 자동 재시도는 없다. 실패 전사의 만료 삭제는 worker가 돌아야 실행되므로 worker가 멈추면 늦어진다 | 서버 [운영 반영], 앱 화면 [develop 구현] |
| 전사를 저장한 직후 리포트 생성 전에 worker가 멈추면 인계 임대가 끝난 뒤 다음 worker가 같은 작업을 이어받는다(#280). 남은 전사 기한이 생성 임대 시간(기본 900초)보다 짧으면 생성을 시작하지 않고, 변경 제안 호출 직전에 작업 행과 전사 기한을 다시 확인해 지워졌거나 기한이 지난 작업의 전사를 외부 ML API로 보내지 않는다(#279). 11/9 배포 전 운영 서버(`9c2b8276`)에서는 이렇게 멈춘 작업이 `sttCompleted`로 남아 24시간 뒤 `TRANSCRIPT_EXPIRED`가 될 때까지 리포트와 같은 회차의 재제출, 재요청이 막혔다. #280 이전부터 `sttCompleted`로 멈춰 있던 작업은 인계 임대가 없어 이어받지 않으므로 처음 배포할 때 손으로 한 번 정리하게 되어 있는데, 팀 운영 기록에는 11/9 배포 뒤 이 정리를 한 기록이 없다([배포 workflow의 실제 실행 기록](docs/deploy-workflows.md#실제-실행-기록-2026-11-09-기준), [분석 복구](backend/docs/speech-recovery.md)) | 서버 [운영 반영], 배포 전 멈춘 작업 정리는 기록 없음 |
| API는 경로별 본문 상한(기본 설정에서 사진 21 MiB, 면회 음성 513 MiB, 짧은 음성 11 MiB, 그 밖의 요청 1 MiB)을 두고, 업로드 네 경로에서는 본문을 읽기 전에 앱 버전과 세션 토큰의 서명과 만료를 확인한다(#278, [BE README](backend/README.md#요청-본문-크기-상한)). 11/9 배포 전 운영 서버(`9c2b8276`)는 본문 상한이 없어 로그인하지 않은 요청의 큰 본문도 끝까지 받은 뒤에야 거절했다. 승인 배포 workflow는 caddy를 교체하지 않으므로 Caddy의 바깥 상한(514MiB)은 caddy를 따로 다시 만들어야 적용되는데, 팀 운영 기록에는 11/9 배포 뒤 caddy를 다시 만든 기록이 없다([배포 문서의 갱신](backend/docs/deployment.md#갱신)) | API 상한 [운영 반영], Caddy 바깥 상한은 적용 기록 없음 |
| 세부 정보 음성 입력의 서버 API(6-6, #214)는 11/8 운영에서 5~30초 녹음 응답 중앙값 0.6~0.8초, 2~5분 녹음 4~5초였다. 동시 요청과 대기열 혼잡은 재지 않았다 | [운영 반영], 부하 미검사 |
| 발화량, 응답 지연 같은 관찰 수치는 계산하지 않는다. `docs/tech-spec.md`와 `docs/pm/presentation-qna.md`의 해당 내용은 과거 계획이다 | [미구현] |
| 녹음 중 화면 켜짐(#207)은 화면이 꺼지지 않게만 한다. 전원 버튼으로 끄거나 다른 앱으로 옮긴 뒤의 녹음 유지는 보장하지 않는다 | 화면 켜짐은 [develop 구현], 포그라운드 서비스는 [미구현] |
| 릴리스 설정 오류 화면(#209)은 테스트에서 릴리스 여부를 인자로 넘겨 확인했다. 실제 `flutter build appbundle --release` 결과물에서 뜨는지는 실행하지 않았다 | [develop 구현], 미검사 |
| 11/7, 11/8 Galaxy S22에서 실제 마이크 녹음, 강제 종료 뒤 녹음 복구와 리포트 생성, 푸시와 알림으로 리포트 열기를 운영 서버로 확인했고 큰 글자 화면도 확인했다(#259, #262, #264, #266의 확인 기록). 11/9 배포 뒤에는 develop `59190ba7`으로 로컬 빌드한 APK(versionCode 7, 디버그 서명)와 시험 계정으로 운영 서버에서 로그아웃 뒤 다시 로그인, 앱 재실행 뒤 세션 유지, 계정 약관 동의 화면(5개 항목), 사진 올리기 전 동의 시트(#272)와 업로드 뒤 AI 설명 생성, 사진 분석이 끝나기 전에 받아 둔 카드로 분석이 끝난 뒤 면회 시작(#275), AI 사진 분석 동의를 끈 뒤 AI 설명 삭제와 직접 쓰기 안내(#288), 면회 뒤 새 카드 생성(약 30초)을 확인했다. 말소리 없는 15초 녹음은 리포트 실패로 끝났고, 다시 요청은 기기 녹음을 다시 보냈으며 다시 실패했다(말소리가 없어 예상한 결과). 녹음 중 화면 잠금, 새 계정 가입과 탈퇴, 두 번째 면회까지의 흐름, 11/9 배포 뒤의 정상 리포트와 푸시(말소리 녹음 필요), 7-4 승인, 긴 이야기 입력은 확인하지 않았다(팀 운영 기록) | 일부 미검사 |
| 화면 낭독 보완(#180, #208)은 위젯 테스트로만 확인했다. 실기기 TalkBack으로 읽어 본 확인은 하지 않았다 | 실기기 미검사 |

## 문서 지도

| 알고 싶은 내용 | 문서 | 비고 |
| --- | --- | --- |
| 목적별 정본 찾기 | [문서 안내](docs/README.md) | 같은 내용이 여러 곳에 있을 때 우선할 문서 |
| 제품 대상, 범위, 정정 처리 기준 | [PM 제품 기준](docs/pm/README.md) | 문서 기준은 구현 완료를 뜻하지 않는다 |
| 제품과 기술 청사진 | [테크스펙](docs/tech-spec.md) | 과거 계획 일부 남음 |
| 앱 화면, 경로, 실행 | [FE README](app/README.md), [환경 세팅](app/SETUP.md), [디자인 기준](app/DESIGN.md) | |
| API, DB, worker, 실행 | [BE README](backend/README.md), [DB 스키마](backend/database/init.sql) | |
| 카드, 리포트, 변경 제안, 사진 설명 생성 | [AI README](ai/README.md), [카드 생성](ai/card_generation/README.md), [시뮬레이션](ai/simulation/README.md) | |
| STT와 화자 분리 | [STT 서버 README](stt-server/README.md), [STT 파이프라인 설계](stt-server/docs/stt-pipeline.md) | |
| 평가 자료 | [평가 README](evals/README.md) | |
| 앱과 BE, BE와 AI 사이 API | [API 명세](docs/architecture/api-spec.md), [데이터 계약](docs/architecture/data-contracts.md), [합성 목 데이터](docs/architecture/mock/README.md) | |
| 카드 첫 생성과 다음 면회 반영 설계 | [주제 카드 전체 설계 검토안](docs/architecture/card-generation-flow.md) | |
| 11/3 이후 병합한 BE 기능 문서 | [리포트 의료 표현 검사](backend/docs/report-safety.md), [전사 입력과 화자 검사](backend/docs/speech-input-safety.md), [화자 정보와 리포트 생성](backend/docs/speaker-fact-boundary.md), [삭제 실패 분리](backend/docs/audio-deletion-isolation.md), [삭제 대기열](backend/docs/storage-deletion.md), [수동 복구](backend/docs/speech-recovery.md), [짧은 음성 전사](backend/docs/short-speech-transcription.md), [사진 분석](backend/docs/photo-analysis.md) | |
| 기술 결정 | [ADR 목록](docs/architecture/decisions/README.md) | accepted는 구현 완료를 뜻하지 않는다 |
| 개인정보와 동의 | [법률 검토](docs/legal/README.md), [동의안](docs/legal/consent-draft.md), [기능 대응표](docs/legal/consent-mapping.md) | |
| 실제 환경 검증 기록 | [10/18 통합 검증](docs/pm/integration-verification-20261018.md), [11/8 운영 안정성 시험](backend/docs/stability-test-20261108.md), [11/9 STT 전사 옵션 비교](stt-server/docs/vad-condition-comparison-20261109.md) | |
| 협업 규칙 | [협업 규칙](CONTRIBUTING.md) | 브랜치, PR 단위, 검토 책임, 문서 갱신 |

## 개발 시작

1. `develop`을 최신 상태로 갱신한다.
2. 루트 `AGENTS.md` 또는 `CLAUDE.md`와 담당 영역의 같은 지침을 읽는다.
3. 최신 `develop`에서 작업 브랜치를 만들고 구현과 검증 뒤 `develop` 대상 PR을 올린다. PR 단위는 [협업 규칙](CONTRIBUTING.md#독립적으로-검증할-작업-단위)을 따른다.

실제 사용자 자료, 마스킹한 실제 자료, 시크릿, 로컬 DB와 모델 파일은 저장소에 올리지 않는다.
