# 컨테이너 실행과 개발 서버 배포

[Dockerfile](../Dockerfile)과 [compose.yml](../compose.yml)로 API, worker와 PostgreSQL을 실행한다. 개발 서버는 develop에 병합된 코드만 올리며 합성 데이터와 개발용 계정으로만 쓴다. 이 문서는 개발 서버의 실행 절차이며 운영 배포 구조를 확정하지 않는다. 외부 공개 전에 필요한 결정은 [아직 정하지 않은 것](#아직-정하지-않은-것)에 둔다.

저장소는 공개 저장소다. 서버 주소, 인스턴스 ID, 키 파일과 `.env` 값을 이 문서, 이슈와 PR에 남기지 않는다.

## 구성

| 서비스 | 켜는 방법 | 하는 일 |
| --- | --- | --- |
| `api` | 기본 | FastAPI. 호스트의 `127.0.0.1:8000`에만 열린다. 개발 서버는 프로세스 하나로 띄운다. 세션 폐기 기록은 DB에 둔다 |
| `card-worker` | 기본 | 카드 생성(4-1) worker. `SAEROK_ML_API_KEY`와 DB 연결 설정이 필요하며, 설정이 없으면 시작하지 않는다. 카드 생성 요청의 실제 처리는 이 worker가 맡는다 |
| `speech-worker` | `--profile workers` | 음성 STT worker. AI 서버 연결 경로가 정해진 뒤 켠다 |
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
   | `SAEROK_AI_SERVER_URL` | 컨테이너 안의 `127.0.0.1`은 컨테이너 자신이다. AI 서버 연결 경로가 정해진 뒤 채운다 |
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
- **AI 서버 연결.** AI 서버는 온프레미스 GPU에 있다([ADR-006](../../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)). EC2에서 닿는 경로, 또는 백엔드를 GPU 장비 옆에 둘지는 정하지 않았다. 정하기 전에는 `speech-worker`를 켜지 않는다.
- **DB 위치와 백업.** 인스턴스의 db 컨테이너와 RDS 중 무엇을 쓸지, 백업 여부는 정하지 않았다. 지금 개발 서버의 데이터는 합성 데이터만 둔다.
- **배포 자동화.** 지금은 위의 수동 절차다. GitHub Actions로 옮길 때 `.github/workflows/`는 카테캠 운영진이 제공하는 디렉터리이므로 먼저 확인한다.
