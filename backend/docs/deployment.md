# 컨테이너 실행과 개발 서버 배포

[Dockerfile](../Dockerfile)과 [compose.yml](../compose.yml)로 API, worker와 PostgreSQL을 실행한다. 개발 서버는 develop에 병합된 코드만 올리며 합성 데이터와 개발용 계정으로만 쓴다. 이 문서는 개발 서버의 실행 절차이며 운영 배포 구조를 확정하지 않는다. 외부 공개 전에 필요한 결정은 [아직 정하지 않은 것](#아직-정하지-않은-것)에 둔다.

저장소는 공개 저장소다. 서버 주소, 인스턴스 ID, 키 파일과 `.env` 값을 이 문서, 이슈와 PR에 남기지 않는다.

## 구성

개인 GPU를 기본으로 두고 ck를 선택적인 예비로 연결하는 절차는
[ck SSH 예비 연결](stt-backup-ssh.md)에 분리했다. GPU 실행 설정, BE 전환 코드와 운영 연결은
각각 검토하며 이 문서의 기본 배포 전체에 예비 설정을 자동 적용하지 않는다.

| 서비스 | 켜는 방법 | 하는 일 |
| --- | --- | --- |
| `api` | 기본 | FastAPI. 호스트의 `127.0.0.1:8000`에만 열린다. 개발 서버는 프로세스 하나로 띄운다. 세션 폐기 기록은 DB에 둔다 |
| `card-worker` | 기본 | 카드 생성(4-1) worker. `SAEROK_ML_API_KEY`와 DB 연결 설정이 필요하며, 설정이 없으면 시작하지 않는다. 카드 생성 요청의 실제 처리는 이 worker가 맡는다 |
| `speech-worker` | `--profile workers` | 음성 STT worker. Tailscale STT 주소·접근 범위·AWS 인증을 확인한 뒤 켠다 |
| `db` | `--profile local-db` | PostgreSQL 17. 외부 DB(RDS 등)를 쓰면 켜지 않는다. 데이터는 `postgres-data` 볼륨에 남는다 |
| `caddy` | `--profile https` | 개발 서버의 HTTPS 앞단([Caddyfile](../Caddyfile)). 인증서를 자동으로 받고 갱신하며 요청을 `api`로 넘긴다 |

이미지에는 `.env`를 넣지 않는다([.dockerignore](../.dockerignore)). 컨테이너는 `backend/.env`의 값을 환경 변수로 받는다.

이미지에는 카드 생성 패키지(`ai/`의 생성 기능 셋과 `common`)도 `/ai`에 들어간다. compose가 `additional_contexts`로 `../ai`를 넘기므로 `docker build`를 직접 쓸 때는 `--build-context ai=../ai`를 붙인다.

카드 생성 요청을 worker가 가져가지 않은 채 기본 360초(`SAEROK_CARD_GENERATION_START_TIMEOUT_SECONDS`)가 지나면, 다음 생성 요청(4-1)이나 상태 조회(4-2)에서 `failed`와 `CARD_GENERATION_NOT_STARTED`로 정리한다. worker가 가져간 뒤 임대가 만료된 작업은 같은 요청이나 조회, 또는 worker의 다음 정리에서 `WORKER_LEASE_EXPIRED`로 처리한다. 생성 요청과 상태 조회가 없고 worker도 실행되지 않으면 DB 상태는 바로 바뀌지 않는다. 자동 재시도가 아니라 앱에서 다시 생성을 요청할 수 있도록 실패 상태를 알리는 처리다.

## 로컬에서 PostgreSQL만 컨테이너로 띄우기

[로컬 PostgreSQL 설정](../database/로컬설정법.md)의 설치를 대신한다. 앱은 지금처럼 `uv`로 실행한다. 로컬에 이미 5432 포트를 쓰는 PostgreSQL이 있으면 먼저 끈다.

`.env`에 다음을 채운다.

```
SAEROK_POSTGRES_PASSWORD=로컬비밀번호
SAEROK_DATABASE_URL=postgresql+psycopg://saerok:로컬비밀번호@localhost:5432/saerok
```

```powershell
docker compose --profile local-db up -d db
uv run alembic upgrade head
```

컨테이너의 `saerok` 계정은 관리자 권한이 있으므로 DB 테스트에 그대로 쓸 수 있다.

```powershell
$env:SAEROK_TEST_DATABASE_URL="postgresql://saerok:로컬비밀번호@localhost:5432/postgres"
uv run pytest
```

## EC2 개발 서버

### 처음 한 번

1. 인스턴스 OS에 맞는 Docker 공식 설치 안내로 Docker Engine과 Compose v2 플러그인을 설치한다. `docker compose version`이 나와야 한다. 재부팅 후에도 컨테이너가 다시 뜨도록 `sudo systemctl enable --now docker`를 실행한다.
2. 인스턴스에 Elastic IP를 붙인다. HTTPS 주소가 IP에서 만들어지므로 IP가 바뀌면 주소와 인증서가 함께 바뀐다.
3. 보안 그룹의 인바운드는 다음만 연다. 8000과 5432는 열지 않는다.

   | 포트 | 출발지 | 용도 |
   | --- | --- | --- |
   | 22 | 팀원 IP | SSH |
   | 80 | 전체 | 인증서 발급과 갱신 확인. 확인 요청의 출발지 IP는 정해져 있지 않다 |
   | 443 | 전체 또는 팀원 IP | 앱의 HTTPS 요청 |

4. S3를 쓸 때는 액세스 키 대신 두 버킷에 대한 `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`만 허용한 IAM 역할을 인스턴스에 붙인다. 코드는 boto3의 기본 자격증명 조회를 쓰므로 키 설정이 필요 없다.
5. 저장소를 받고 develop을 쓴다.

   ```bash
   git clone https://github.com/kakaotechcampus-4/ktc4-chungnam-1.git
   cd ktc4-chungnam-1/backend
   git switch develop
   ```

6. `.env`를 만들고 다른 사용자가 읽지 못하게 한다.

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

   | 항목 | 값 |
   | --- | --- |
   | `SAEROK_POSTGRES_PASSWORD` | db 컨테이너를 쓸 때 새로 만든 비밀번호 |
   | `SAEROK_DATABASE_URL` | db 컨테이너면 `postgresql+psycopg://saerok:<비밀번호>@db:5432/saerok` |
   | `SAEROK_SESSION_SECRET` | `openssl rand -base64 48`로 만든 값. 로컬 개발의 값과 다르게 둔다 |
   | `SAEROK_PUBLIC_HOST` | Elastic IP의 점을 하이픈으로 바꾼 `<IP>.sslip.io`. 예: `203.0.113.10`이면 `203-0-113-10.sslip.io` |
   | `SAEROK_GOOGLE_CLIENT_IDS` | FE가 쓰는 클라이언트 ID([README](../README.md)의 `aud` 설명). 앱의 `SAEROK_GOOGLE_SERVER_CLIENT_ID`와 같아야 한다 |
   | `SAEROK_AI_SERVER_URL` | 컨테이너 안의 `127.0.0.1`은 컨테이너 자신이다. GPU 서버의 Tailscale 주소인 `http://<GPU 서버의 Tailscale IP>:8001`을 넣는다 |
   | S3 버킷 | 비워 두면 음성 제출과 사진 업로드를 거절한다 |
   | `SAEROK_ML_API_KEY` | 카드 생성에 쓰는 ML API 키. 비워 두면 4-1을 거절하고 `card-worker`가 시작하지 않는다 |

7. DB, migration, API와 카드 worker, HTTPS 앞단 순서로 띄운다.

   ```bash
   docker compose --profile local-db up -d db
   docker compose build
   docker compose run --rm api alembic upgrade head
   docker compose up -d api card-worker
   curl http://127.0.0.1:8000/health/live
   docker compose --profile https up -d caddy
   ```

   인증서 발급 결과는 `docker compose logs caddy`로 본다. 인스턴스 밖에서 `https://<SAEROK_PUBLIC_HOST>/health/live`가 응답하면 끝이다.

### 갱신

develop에 병합된 뒤 실행한다. migration은 이 단계에서만 적용한다.

```bash
git pull
docker compose build
docker compose run --rm api alembic upgrade head
docker compose up -d api card-worker
```

상태는 `docker compose ps`, 로그는 `docker compose logs -f api card-worker`로 본다. `docker compose down -v`는 DB 볼륨까지 지운다.

같은 순서를 백업, 버전 대조와 기록까지 붙여 실행하는 workflow는 [배포 후보 빌드와 수동 배포 workflow](#배포-후보-빌드와-수동-배포-workflow)에 있다. 그 workflow로 한 번 배포한 서버는 커밋을 직접 가리키는 detached HEAD 상태가 되므로, 이후 손으로 갱신할 때는 `git pull` 대신 `git fetch origin <SHA>`와 `git checkout --detach <SHA>`를 쓴다.

### worker 종료와 유예 시간

`docker compose stop`, `restart`와 이미지가 바뀐 뒤의 `up -d`는 worker에 SIGTERM을 보낸다. worker는 새 작업을 가져오지 않고, 처리 중인 작업을 마친 뒤 끝난다. 로그에는 `worker_stopping` 다음에 `worker_stopped`가 남는다. 대기 중이었으면 바로 끝나고, 작업을 처리하는 중이었으면 갱신 명령이 그만큼 오래 걸린다.

- 유예 시간은 `card-worker`와 `speech-worker` 모두 `stop_grace_period: 180s`다. 2026-10-18 [통합 검증](../../docs/pm/integration-verification-20261018.md)에서 작업 생성부터 리포트 준비까지 약 38초(준비된 모델, 단일 실행)였고, 그 3~5배 범위의 상한에 맞췄다. 카드 생성은 실측이 없어 설정 주석의 1~2분을 덮는 같은 값을 쓴다.
- 유예 시간을 넘기면 Docker가 SIGKILL로 끝낸다. 처리 중이던 작업은 임대(음성 900초, 카드 300초)가 끝난 뒤 `WORKER_LEASE_EXPIRED`로 실패한다. 코드가 허용하는 처리 시간(STT 응답 대기 600초, 리포트 생성 600초)보다 짧으므로 긴 녹음은 이렇게 끊길 수 있다. 녹음 길이별 처리 시간을 측정한 뒤 다시 정한다.
- 기다리지 않고 바로 끝내야 하면 `docker compose kill <서비스>`를 쓴다. 로컬에서 직접 실행한 worker는 Ctrl+C를 두 번 누르면 바로 끝난다.

### 앱 연결

앱의 `app/.env`에 `SAEROK_API_BASE_URL=https://<SAEROK_PUBLIC_HOST>`를 넣는다. HTTPS이므로 release 빌드에서도 연결된다. 이 주소는 공개 저장소의 `app/.env.example`과 문서에 적지 않는다.

`caddy`를 켜지 않은 동안에는 API가 인스턴스 밖에서 보이지 않는다. 그때는 SSH 터널(`ssh -N -L 8000:127.0.0.1:8000 <사용자>@<인스턴스 주소>`)로 붙고, 에뮬레이터에서는 `http://10.0.2.2:8000`을 쓴다.

## 아직 정하지 않은 것

- **외부 공개.** 외부에서 접근할 수 있는 배포는 [ADR-004](../../docs/architecture/decisions/ADR-004-python-fastapi-reference-environment.md)의 재검토 조건이다. 지금의 sslip.io와 Caddy 구성은 개발 서버의 임시 HTTPS이며, 공개 범위, 접근 제한과 정식 도메인 사용 여부는 개발 서버 ADR에서 정한다.
- **sslip.io와 인증서 발급처.** sslip.io는 이름을 IP로 바꿔 주는 DNS만 제공하고, 요청과 응답은 거치지 않고 EC2로 바로 간다. 인증서 발급처는 호스트 이름만 받는다. 둘 다 외부 무료 서비스라 장애나 발급 한도의 영향을 받을 수 있으므로 최종 배포 주소로 쓸지는 따로 정한다.
- **AI 서버 연결.** 현재 STT는 개인 GPU에 임시 연결한다([ADR-006의 현재 경로](../../docs/architecture/decisions/ADR-006-server-side-ai-processing.md#개인-gpu와-tailscale-임시-연결-2026-10-31-보완)). EC2와 GPU 서버를 Tailscale 사설망에 연결하고, GPU는 자신의 Tailscale IP에 STT를 바인딩한다. BE의 `SAEROK_AI_SERVER_URL`을 `http://<GPU 서버의 Tailscale IP>:8001`로 설정한 뒤 API와 worker 컨테이너를 재생성한다. 현재 설명된 접근 범위는 관리자가 승인한 tailnet 기기이며 BE 한 대만 허용한 것으로 보고하지 않는다. 실제 Grants/ACL과 기존 공개 경로를 확인하고 이슈의 BE 전용 완료 조건과 조정 여부를 맞춘다. GPU 측 확인은 이문영, BE 호출 확인은 김민혁이 맡는다. worker의 AWS 인증을 확인한 뒤 BE 컨테이너에서 상태 확인과 합성 음성 POST를 검증하고, 정상·차단 결과와 적용 환경을 주소·인증값 없이 이슈에 남긴다. 이 문서 변경에서는 현재 경로의 정상 분석, 차단 동작과 처리 성능을 검증하지 않았다. 상세 확인 항목은 [STT 운영 안내](../../stt-server/README.md#개인-gpu와-tailscale-운영)를 따른다.
- **DB 위치와 백업.** 인스턴스의 db 컨테이너와 RDS 중 무엇을 쓸지, 백업 여부는 정하지 않았다. 지금 개발 서버의 데이터는 합성 데이터만 둔다.
- **배포 자동화.** 승인을 거치는 수동 실행 workflow를 로컬에 만들었다([아래](#배포-후보-빌드와-수동-배포-workflow)). GitHub에 올리기 전에 `.github/workflows/`가 카테캠 운영진이 제공하는 디렉터리라는 점을 운영진과 확인한다. 병합 시 자동 배포는 하지 않기로 범위를 정했다.

## 배포 후보 빌드와 수동 배포 workflow

[로컬 작업] `.github/workflows/release-build.yml`과 `.github/workflows/deploy.yml`은 아직 GitHub에 올리지 않았고 Actions에서 실행한 적이 없다. 아래 시크릿, 변수, Environment와 AWS 권한도 설정되어 있지 않다. 설정하기 전에 Deploy를 실행하면 첫 단계에서 멈춘다.

### 자동화 범위

| 구분 | 자동 | 사람 |
| --- | --- | --- |
| PR 검사 | [제품 테스트 CI](../../docs/product-tests.md) | 검토와 병합 |
| 배포 후보 | `v*` 태그 push나 수동 실행 시 Release build: 같은 커밋에서 제품 테스트를 다시 돌리고 백엔드 이미지와 Android APK·AAB를 만든다 | 배포할 SHA 선택 |
| 배포 | Deploy: 사전 점검, 백업과 격리 복원 검사, 빌드, migration, 컨테이너 교체, 사후 점검, 배포 기록 | 실행, `production` 승인, 기능 확인 |
| 되돌리기 | 실패 시 이전 커밋과 이전 이미지가 들어간 명령 안내 출력 | 판단과 실행 |
| 앱 배포 | 빌드와 artifact 업로드 | Play 업로드와 테스트 설치 안내 |

CD는 수동 실행에 승인을 붙이는 방식이며 병합할 때 자동으로 배포하지 않는다. 이유는 다음과 같다.

- 서버가 개발 서버 한 대다. API의 새 요청 접수를 막는 방법이 아직 없고, [배포 전 백업, 버전 대조와 되돌리기](release-safety.md)의 2단계는 진행 중 작업을 확인한 뒤에만 교체하도록 한다. Deploy는 처리 중인 작업이 있으면 멈추지만 언제 배포할지는 사람이 정한다.
- migration은 되돌리기를 자동화하지 않는다. `alembic downgrade`와 운영 DB 복원은 손실 범위와 승인자를 먼저 정해야 한다.
- 로그인, 카드 생성, 녹음부터 리포트, 다음 카드까지의 확인과 옛 앱과 새 앱의 확인은 workflow가 하지 않는다.
- AWS 지원이 11월 20일에 끝난다. 이미지 레지스트리 같은 새 인프라를 들이지 않고 지금 수동 절차를 그대로 옮겼다.

### 커밋, 이미지, 앱 버전, migration과 되돌릴 버전의 연결

| 항목 | Release build 기록 | Deploy 기록 |
| --- | --- | --- |
| 커밋 | 실행한 커밋 SHA | 입력 SHA. 대상 브랜치에 포함돼 있고 성공한 Release build가 있어야 시작한다 |
| 이미지 | `saerok-backend:<SHA>`, 이미지 ID, buildx digest, revision 라벨 확인 | 서버에서 같은 SHA로 다시 빌드한 이미지 ID, `saerok-backend:<SHA>` 태그, 실행 중인 모든 서비스의 revision 라벨이 SHA와 같은지 |
| 앱 버전 | versionName, versionCode(APK에서 aapt2로 확인), 서명 방식, APK·AAB SHA-256 | 없음 |
| migration | 이미지 안의 Alembic head(하나여야 함) | 배포 전 DB revision, 새 이미지의 head, 사후 `runtime_check --expected-revision` 일치 |
| 상태 검사 | 이미지의 API와 worker 모듈 불러오기 검사 | 배포 전 `/health/ready`, 배포 후 `/health/live`, `/health/ready` |
| 되돌릴 버전 | 없음 | 이전 커밋, 이전 이미지 ID, 보존 태그 `saerok-backend:rollback-<실행 번호>`, 백업 파일 이름 |

이미지는 레지스트리에 올리지 않는다. Release build의 이미지 ID와 서버에서 다시 만든 이미지 ID는 다를 수 있으며, 같은 커밋이라는 근거는 revision 라벨과 Alembic head다. Release build 요약과 `release-manifest-<SHA>` artifact, Deploy 요약과 서버의 배포 기록 파일을 SHA로 맞춰 본다.

### Release build

- 제품 테스트는 `product-tests.yml`의 `workflow_call`로 같은 검사를 다시 실행한다.
- 백엔드 이미지는 `docker buildx build --build-context ai=../ai --build-arg SOURCE_REVISION=<SHA> --load`로 한 번 만든다. api, card-worker, speech-worker가 같은 이미지를 쓴다. 이미지 안에서 DB 없이 Alembic head를 읽고, `tests/test_container_packages.py`를 그 이미지로 실행한다.
- Android 빌드는 `SAEROK_API_BASE_URL`과 `SAEROK_GOOGLE_SERVER_CLIENT_ID`를 `--dart-define`으로 넘긴다. [릴리스 설정 검사](../../app/lib/app/release_config.dart)와 같은 기준으로 값을 먼저 확인하고, 비어 있거나 https가 아니면 빌드하지 않는다.
- versionName과 versionCode는 `app/pubspec.yaml`의 `version`을 쓴다. 수동 실행에서는 `build_name`, `build_number` 입력으로 바꿀 수 있다. 태그 이름과 versionName이 다르면 경고만 남긴다.
- 업로드 키 시크릿 네 개가 모두 있을 때만 `android/key.properties`를 만들어 업로드 키로 서명하고 끝나면 지운다. 없으면 [build.gradle.kts](../../app/android/app/build.gradle.kts)의 기존 동작대로 디버그 키로 서명하고 요약에 `debug`라고 적는다. 이 빌드는 Play에 올릴 수 없고, 실행기마다 디버그 키가 달라 기존 설치본 위에 업데이트되지 않을 수 있다.
- 공개 저장소의 artifact는 로그인한 GitHub 사용자라면 받을 수 있다. 앱 artifact는 7일만 보관하며, 수동 실행에서는 `upload_app`을 끄고 빌드만 확인할 수 있다. 승인된 비공개 테스트 경로를 대신하지 않는다.
- 공개 저장소의 Actions 로그도 누구나 볼 수 있다. 저장소 변수(vars)는 로그에 그대로 보이므로 서버 주소는 같은 이름의 시크릿으로 넣는 것을 권한다. 시크릿이 있으면 시크릿을, 없으면 변수를 쓴다.

### Deploy

GitHub의 Actions 탭에서 Deploy (manual)를 고르고 SHA, 대상 브랜치, `deploy <SHA 앞 12자리>`를 입력한다. `production` 승인 뒤 AWS SSM `AWS-RunShellScript`로 서버에서 단계별 명령을 실행한다. SSH 포트를 GitHub 실행기에 열지 않고, 장기 액세스 키 대신 GitHub OIDC로 짧은 자격증명을 받는다. 배포는 `deploy-production` 동시 실행 그룹으로 하나씩 진행되며, 진행 중인 배포를 취소하지 않는다.

| 순서 | 하는 일 | 실패하면 |
| --- | --- | --- |
| 요청 확인 | SHA 형식, 확인 문자열, 대상 브랜치 포함 여부, 해당 SHA의 성공한 Release build | 승인 요청 전에 멈춘다 |
| 1. 사전 점검 | 도구와 Python 3.11 이상, 추적 파일 변경 없음, api 실행 중, `/health/ready` 200, `runtime_check`의 DB 조회 성공과 처리 중 작업 0건. 이전 커밋과 이전 이미지 ID를 기록하고 이전 이미지에 보존 태그를 붙인다 | 아무것도 바꾸지 않고 멈춘다 |
| 2. 백업 | `scripts/verify_database_backup.py`로 새 백업과 격리 복원 검사. `restoreVerified`가 true여야 한다 | 멈춘다. 백업 파일은 남는다 |
| 3. 빌드 | `git fetch origin <SHA>`, `git checkout --detach <SHA>`, `docker compose build --build-arg SOURCE_REVISION=<SHA> api`. revision 라벨과 단일 Alembic head를 확인하고 `saerok-backend:<SHA>` 태그를 붙인다 | 서버 체크아웃과 이미지 이름을 이전 상태로 되돌리고 멈춘다. 컨테이너는 그대로다 |
| 4. migration | `docker compose run --rm --no-deps api alembic upgrade head` | 멈추고 되돌리기 안내를 출력한다 |
| 5. 교체 | `docker compose up -d --no-build <DEPLOY_SERVICES>`. worker 유예 시간을 줄이지 않는다 | 멈추고 되돌리기 안내를 출력한다 |
| 6. 사후 점검 | `/health/live`, `/health/ready`를 2분까지 기다리고 `runtime_check --expected-revision <head>`가 일치해야 한다. 기한 지난 임대 같은 다른 경고는 출력만 한다 | 멈추고 되돌리기 안내를 출력한다 |
| 7. 기록 | `scripts/capture_release.py` 결과를 `DEPLOY_RELEASE_DIR/release-<UTC>-<SHA 12자리>.json`에 저장한다. 모든 서비스가 실행 중이고 revision 라벨이 SHA와 같아야 한다 | override가 다른 이미지를 고정한 경우 등을 실패로 알린다 |

서버 출력은 Actions 로그에 남으므로 서버 안에서 `127.0.0.1`로만 점검하고 `.env`와 `docker compose config` 원문을 출력하지 않는다. 백업과 배포 기록 파일은 0600 또는 0700 권한으로 만든다.

서버가 갖춰야 할 조건은 다음과 같다. 하나라도 다르면 이 workflow를 쓰지 않고 위의 수동 절차를 따른다.

- SSM Agent가 실행 중이고 인스턴스 역할에 `AmazonSSMManagedInstanceCore`가 있다. SSM 명령은 root로 실행되며 git 쓰기는 `sudo -u <DEPLOY_HOST_USER>`로 한다.
- `docker compose`, `git`, `curl`, `sudo`와 Python 3.11 이상이 있다. `scripts/`의 도구가 3.11 기능을 쓴다.
- DB는 compose의 `db` 컨테이너다. RDS를 쓰면 백업 도구가 동작하지 않으므로 RDS 스냅샷 절차를 따로 정한 뒤에 쓴다.
- 서버 저장소의 `origin`이 이 GitHub 저장소이고 서버에서 받을 수 있다.
- speech-worker까지 교체하려면 `DEPLOY_SERVICES=api card-worker speech-worker`, `DEPLOY_COMPOSE_PROFILES=workers`로 둔다. 실제 서버의 compose 파일 조합이 다르면 `DEPLOY_COMPOSE_FILES`에 적용 순서대로 적는다.

### 팀이 설정할 항목

| 위치 | 이름 | 필수 | 내용 |
| --- | --- | --- | --- |
| 저장소 시크릿 또는 변수 | `SAEROK_API_BASE_URL` | Release build | 앱이 쓸 https 서버 주소. 로그 노출을 피하려면 시크릿 |
| 저장소 시크릿 또는 변수 | `SAEROK_GOOGLE_SERVER_CLIENT_ID` | Release build | `SAEROK_GOOGLE_CLIENT_IDS`와 같은 웹 클라이언트 ID |
| 저장소 시크릿 | `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD` | 선택 | 업로드 키. 없으면 디버그 키 서명 |
| Environment `production` 설정 | Required reviewers, Deployment branches | Deploy | 승인자 지정. 배포 브랜치를 `develop`과 `main`으로 제한한다. 수동 실행은 고른 브랜치의 workflow 파일을 쓰므로, 제한이 없으면 다른 브랜치에서 고친 workflow가 환경 시크릿을 받을 수 있다 |
| Environment 시크릿 | `AWS_DEPLOY_ROLE_ARN` | Deploy | OIDC로 맡을 IAM 역할 |
| Environment 시크릿 | `DEPLOY_INSTANCE_ID` | Deploy | 대상 EC2 인스턴스 ID. 로그에서 가리도록 시크릿으로 둔다 |
| Environment 변수 | `AWS_REGION`, `DEPLOY_REPO_DIR`, `DEPLOY_BACKUP_DIR`, `DEPLOY_RELEASE_DIR` | Deploy | 리전, 서버 저장소 절대 경로, 저장소 밖의 백업 경로, 배포 기록 경로 |
| Environment 변수 | `DEPLOY_HOST_USER`(`ubuntu`), `DEPLOY_HOST_PYTHON`(`python3`), `DEPLOY_COMPOSE_FILES`(`compose.yml`), `DEPLOY_COMPOSE_PROFILES`(없음), `DEPLOY_SERVICES`(`api card-worker`), `DEPLOY_DB_CONTAINER`(`saerok-db-1`), `DEPLOY_DB_NAME`(`saerok`), `DEPLOY_DB_USER`(`saerok`) | 선택 | 괄호 안이 기본값 |
| AWS IAM | GitHub OIDC 공급자 | Deploy | `token.actions.githubusercontent.com`, audience `sts.amazonaws.com` |
| AWS IAM | 배포 역할의 신뢰 정책 | Deploy | `sub`를 `repo:kakaotechcampus-4/ktc4-chungnam-1:environment:production`으로 제한 |
| AWS IAM | 배포 역할의 권한 | Deploy | 대상 인스턴스와 `AWS-RunShellScript` 문서에 대한 `ssm:SendCommand`, `ssm:GetCommandInvocation` |

값에 따옴표, 공백(목록 구분 제외), `..`가 들어가면 서버 명령에 넣기 전에 거절한다. IAM 변경과 Environment 설정은 저장소 밖의 운영 변경이므로 담당자 승인 후 진행한다.

### 실패와 되돌리기

Deploy는 자동으로 되돌리지 않는다. 실패하면 요약에 이전 커밋, 이전 이미지 ID, 보존 태그와 명령을 출력한다.

- migration 전에 멈췄다면 실행 중인 컨테이너는 바뀌지 않았다. 빌드 단계 실패는 서버 체크아웃을 이전 위치로 되돌린다.
- migration 단계가 실행됐다면 실패했더라도 `alembic current`로 DB revision을 먼저 확인한다. 이전 이미지가 새 스키마를 읽을 수 있다고 확인된 경우에만 보존 태그를 이미지 이름에 다시 붙이고 `docker compose up -d --no-build`로 되돌린다. 태그를 붙이기 전에 이미지 ID를 대조한다.
- 새 migration이 들어간 배포 뒤에 이 workflow로 이전 SHA를 다시 배포하면 이전 코드에 없는 revision 때문에 `alembic upgrade head`가 실패한다. 이 경우는 위의 이미지 되돌리기와 [이상이 생겼을 때](release-safety.md#이상이-생겼을-때)를 따른다.
- `alembic downgrade`와 운영 DB 복원은 workflow에 넣지 않았다.

### 검증 범위

11월 3일 로컬에서 확인한 것과 확인하지 않은 것이다.

- actionlint 1.7.12로 저장소의 workflow 일곱 개 전체를 검사했다. `product-tests.yml`과 `release-build.yml`은 shellcheck 0.11.0 연동까지 통과했다. `deploy.yml`은 Windows에서 shellcheck 연동 실행이 끝나지 않아, 두 새 workflow의 `run` 스크립트와 서버에 보낼 스크립트를 따로 꺼내 shellcheck로 검사했다.
- 로컬 Docker에서 Release build와 같은 buildx 명령으로 이미지를 만들고, revision 라벨, Alembic head `e84b1c6da032`와 `tests/test_container_packages.py`(2개 통과)를 확인했다.
- Flutter 3.44.8로 임시 https 주소와 임시 클라이언트 ID를 넣어 release APK를 만들고 aapt2로 versionCode를 확인했다. AAB와 업로드 키 서명은 로컬에서 만들지 않았다.
- 서버 단계 스크립트는 dash 문법 검사와, docker, git, curl을 흉내 낸 컨테이너에서 정상 경로와 실패 경로(처리 중 작업, 추적 파일 변경, revision 불일치 시 체크아웃 복원, migration 불일치)를 실행했다. 실제 EC2, SSM, OIDC, 백업 도구의 실제 복원과 GitHub Actions 실행은 확인하지 않았다.
