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
| `caddy` | `--profile https` | 개발 서버의 HTTPS 앞단([Caddyfile](../Caddyfile)). 인증서를 자동으로 받고 갱신하며 요청을 `api`로 넘긴다. 본문 상한 514MiB를 둔다. 정상 설정에서는 API의 경로별 상한이 먼저 걸린다([요청 본문 크기 상한](../README.md#요청-본문-크기-상한)) |

이미지에는 `.env`를 넣지 않는다([.dockerignore](../.dockerignore)). 컨테이너는 `backend/.env`의 값을 환경 변수로 받는다.

이미지에는 카드 생성 패키지(`ai/`의 생성 기능 셋과 `common`)도 `/ai`에 들어간다. compose가 `additional_contexts`로 `../ai`를 넘기므로 `docker build`를 직접 쓸 때는 `--build-context ai=../ai`를 붙인다.

카드 생성 요청을 worker가 가져가지 않은 채 기본 360초(`SAEROK_CARD_GENERATION_START_TIMEOUT_SECONDS`)가 지났고 같은 시간 동안 worker가 다른 작업도 가져가지 않았으면, 다음 생성 요청(4-1)이나 상태 조회(4-2)에서 `failed`와 `CARD_GENERATION_NOT_STARTED`로 정리한다. worker가 가져간 시각은 `card_sets.claimed_at`에 남는다. 그 시간 안에 가져간 작업이나 임대가 남은 작업이 있으면 worker가 다른 작업을 처리하는 중으로 보고 기다리는 작업을 `running`으로 둔다. 작업 하나가 임대 시간(`SAEROK_CARD_GENERATION_LEASE_SECONDS`, 기본 300초)까지 걸릴 수 있어 이 값은 임대 시간보다 길게 둔다. worker가 가져간 뒤 임대가 만료된 작업은 같은 요청이나 조회, 또는 worker의 다음 정리에서 `WORKER_LEASE_EXPIRED`로 처리한다. 생성 요청과 상태 조회가 없고 worker도 실행되지 않으면 DB 상태는 바로 바뀌지 않는다. 자동 재시도가 아니라 앱에서 다시 생성을 요청할 수 있도록 실패 상태를 알리는 처리다.

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

4. S3를 쓸 때는 액세스 키 대신 두 버킷에 대한 `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`만 허용한 IAM 역할을 인스턴스에 붙인다. 코드는 boto3의 기본 자격증명 조회를 쓰므로 키 설정이 필요 없다. 컨테이너는 인스턴스 메타데이터(IMDSv2)까지 네트워크를 한 단계 더 거치므로, 인스턴스의 메타데이터 응답 홉 제한이 1이면 `api`와 `speech-worker`가 역할 자격증명을 받지 못해 S3 업로드가 실패한다. 인스턴스 설정의 메타데이터 옵션에서 홉 제한을 2로 둔다(`aws ec2 modify-instance-metadata-options --instance-id <인스턴스 ID> --http-put-response-hop-limit 2 --http-endpoint enabled`).
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
   | `SAEROK_ENVIRONMENT` | `production`. 자동 API 문서(`/docs`, `/redoc`, `/openapi.json`)를 닫는다 |
   | `SAEROK_POSTGRES_PASSWORD` | db 컨테이너를 쓸 때 새로 만든 비밀번호 |
   | `SAEROK_DATABASE_URL` | db 컨테이너면 `postgresql+psycopg://saerok:<비밀번호>@db:5432/saerok` |
   | `SAEROK_SESSION_SECRET` | `openssl rand -base64 48`로 만든 값. 로컬 개발의 값과 다르게 둔다 |
   | `SAEROK_PUBLIC_HOST` | Elastic IP의 점을 하이픈으로 바꾼 `<IP>.sslip.io`. 예: `203.0.113.10`이면 `203-0-113-10.sslip.io` |
   | `SAEROK_GOOGLE_CLIENT_IDS` | FE가 쓰는 클라이언트 ID([README](../README.md)의 `aud` 설명). 앱의 `SAEROK_GOOGLE_SERVER_CLIENT_ID`와 같아야 한다 |
   | `SAEROK_AI_SERVER_URL` | 컨테이너 안의 `127.0.0.1`은 컨테이너 자신이다. GPU 서버의 Tailscale 주소인 `http://<GPU 서버의 Tailscale IP>:8001`을 넣는다 |
   | S3 버킷 | 비워 두면 음성 제출과 사진 업로드를 거절한다 |
   | `SAEROK_ML_API_KEY` | 카드 생성에 쓰는 ML API 키. 비워 두면 4-1을 거절하고 `card-worker`가 시작하지 않는다 |
   | `SAEROK_FCM_KEY_FILE`, `SAEROK_FCM_CREDENTIALS_PATH` | 리포트 완료 푸시. 아래 "리포트 완료 푸시 키"를 따른다. 둘 다 비우면 푸시 없이 리포트만 만든다 |

   **리포트 완료 푸시 키**: Firebase 콘솔 → 프로젝트 설정 → 서비스 계정에서 받은 키 파일을 저장소 밖(예: `/opt/saerok/secrets/fcm-service-account.json`)에 두고 `chmod 600`으로 다른 사용자가 읽지 못하게 한다. `SAEROK_FCM_KEY_FILE`에 그 호스트 경로를, `SAEROK_FCM_CREDENTIALS_PATH`에 `/run/secrets/fcm-service-account.json`을 넣는다. compose가 키를 `speech-worker`에만 읽기 전용으로 붙이며 이미지에는 넣지 않는다. 경로를 넣었는데 키를 읽지 못하면 `speech-worker`가 시작하지 않는다. 키 경로와 값은 이 문서, 이슈와 PR에 남기지 않는다.

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

[Caddyfile](../Caddyfile)이 바뀐 갱신은 caddy도 다시 만든다. 실행 중인 caddy는 시작할 때 읽은 설정을 계속 쓰고, 배포 workflow도 caddy를 교체하지 않는다. 인증서는 `caddy-data` 볼륨에 남아 다시 발급받지 않는다.

```bash
docker compose --profile https up -d --no-deps --force-recreate caddy
```

상태는 `docker compose ps`, 로그는 `docker compose logs -f api card-worker`로 본다. 로그는 서비스마다 10MB 파일 3개까지만 남는다([compose.yml](../compose.yml)의 `x-logging`). `docker compose down -v`는 DB 볼륨까지 지운다.

### worker 종료와 유예 시간

`docker compose stop`, `restart`와 이미지가 바뀐 뒤의 `up -d`는 worker에 SIGTERM을 보낸다. worker는 새 작업을 가져오지 않고, 처리 중인 작업을 마친 뒤 끝난다. 로그에는 `worker_stopping` 다음에 `worker_stopped`가 남는다. 대기 중이었으면 바로 끝나고, 작업을 처리하는 중이었으면 갱신 명령이 그만큼 오래 걸린다.

- 기본 유예 시간은 카드 360초, 녹음 1860초다. 카드 임대 300초와 저장 여유 60초, 녹음은 전사와 리포트에 각각 부여하는 임대 900초의 합과 여유 60초를 사용한다. 단일 녹음의 38초 실측을 모든 작업의 상한으로 사용하지 않는다.
- `.env`의 `SAEROK_CARD_STOP_GRACE_SECONDS`, `SAEROK_SPEECH_STOP_GRACE_SECONDS`로 Compose 유예를 조정할 수 있다. 임대 설정이나 override를 바꿨다면 `python scripts/check_shutdown_budget.py --compose-file compose.yml`로 실제 합성 설정을 검사한다. 추가 override를 사용하면 같은 옵션으로 파일을 순서대로 모두 지정한다. 이 명령은 `docker compose config`만 읽고 컨테이너를 바꾸지 않는다. 비밀 값이 포함될 수 있는 config 원문은 출력하지 않는다.
- 유예 시간은 작업의 무조건 성공을 보장하지 않는다. 외부 호출이나 DB가 멈추거나 유예를 넘기면 여전히 강제 종료될 수 있다. API 접수를 차단하고 진행 중 작업이 끝났는지 확인한 뒤 교체한다. worker만 멈춰도 API는 새 작업을 받을 수 있다.
- `docker compose stop -t`처럼 시간을 별도 지정하면 Compose 설정을 덮어쓴다. 배포 중 짧은 `-t`를 붙이지 않는다. 유예 안에 끝나지 않은 작업과 임대 만료는 별도 장애로 기록하며, 유예 시간 증가가 분석 재시도 기능을 구현한 것은 아니다.
- 녹음 작업이 전사 저장 뒤 리포트 시작 전에 강제 종료되면 인계 임대(`SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS`)가 끝난 뒤 다음 worker가 리포트 생성을 이어받는다. 그래서 재시작 직후에는 그 작업이 `sttCompleted`로 남아 있을 수 있다. 전사나 리포트 생성 도중 강제 종료된 작업은 임대가 끝난 뒤 `WORKER_LEASE_EXPIRED`로 실패한다.
- 기다리지 않고 바로 끝내야 하면 `docker compose kill <서비스>`를 쓴다. 로컬에서 직접 실행한 worker는 Ctrl+C를 두 번 누르면 바로 끝난다.

### 앱 연결

앱의 `app/.env`에 `SAEROK_API_BASE_URL=https://<SAEROK_PUBLIC_HOST>`를 넣는다. HTTPS이므로 release 빌드에서도 연결된다. 이 주소는 공개 저장소의 `app/.env.example`과 문서에 적지 않는다.

`caddy`를 켜지 않은 동안에는 API가 인스턴스 밖에서 보이지 않는다. 그때는 SSH 터널(`ssh -N -L 8000:127.0.0.1:8000 <사용자>@<인스턴스 주소>`)로 붙고, 에뮬레이터에서는 `http://10.0.2.2:8000`을 쓴다.

## 아직 정하지 않은 것

- **외부 공개.** 외부에서 접근할 수 있는 배포는 [ADR-004](../../docs/architecture/decisions/ADR-004-python-fastapi-reference-environment.md)의 재검토 조건이다. 지금의 sslip.io와 Caddy 구성은 개발 서버의 임시 HTTPS이며, 공개 범위, 접근 제한과 정식 도메인 사용 여부는 개발 서버 ADR에서 정한다.
- **sslip.io와 인증서 발급처.** sslip.io는 이름을 IP로 바꿔 주는 DNS만 제공하고, 요청과 응답은 거치지 않고 EC2로 바로 간다. 인증서 발급처는 호스트 이름만 받는다. 둘 다 외부 무료 서비스라 장애나 발급 한도의 영향을 받을 수 있으므로 최종 배포 주소로 쓸지는 따로 정한다.
- **AI 서버 연결.** 현재 STT는 개인 GPU에 임시 연결한다([ADR-006의 현재 경로](../../docs/architecture/decisions/ADR-006-server-side-ai-processing.md#개인-gpu와-tailscale-임시-연결-2026-10-31-보완)). EC2와 GPU 서버를 Tailscale 사설망에 연결하고, GPU는 자신의 Tailscale IP에 STT를 바인딩한다. BE의 `SAEROK_AI_SERVER_URL`을 `http://<GPU 서버의 Tailscale IP>:8001`로 설정한 뒤 API와 worker 컨테이너를 재생성한다. 현재 설명된 접근 범위는 관리자가 승인한 tailnet 기기이며 BE 한 대만 허용한 것으로 보고하지 않는다. 실제 Grants/ACL과 기존 공개 경로를 확인하고 이슈의 BE 전용 완료 조건과 조정 여부를 맞춘다. GPU 측 확인은 이문영, BE 호출 확인은 김민혁이 맡는다. worker의 AWS 인증을 확인한 뒤 BE 컨테이너에서 상태 확인과 합성 음성 POST를 검증하고, 정상·차단 결과와 적용 환경을 주소·인증값 없이 이슈에 남긴다. 이 문서 변경에서는 현재 경로의 정상 분석, 차단 동작과 처리 성능을 검증하지 않았다. 상세 확인 항목은 [STT 운영 안내](../../stt-server/README.md#개인-gpu와-tailscale-운영)를 따른다.
- **DB 위치와 백업.** 인스턴스의 db 컨테이너와 RDS 중 무엇을 쓸지는 정하지 않았다. 지금 개발 서버의 데이터는 합성 데이터만 둔다. 운영 서버의 DB 백업은 [배포 workflow](../../docs/deploy-workflows.md#백업-파일-정리)의 백업 단계가 만들고, 2026-11-09 PM 결정에 따라 14일 보관한다. 지난 백업은 서버의 systemd timer(`ops/backup-prune/`)가 지우며, 설치와 확인은 [오래된 백업 정리](release-safety.md#오래된-백업-정리14일-보관)를 따른다.
- **배포 자동화.** 지금은 위의 수동 절차다. GitHub Actions로 옮길 때 `.github/workflows/`는 카테캠 운영진이 제공하는 디렉터리이므로 먼저 확인한다.
