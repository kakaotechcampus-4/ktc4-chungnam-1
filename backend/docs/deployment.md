# 컨테이너 실행과 개발 서버 배포

[Dockerfile](../Dockerfile)과 [compose.yml](../compose.yml)로 API, worker와 PostgreSQL을 실행한다. 개발 서버는 develop에 병합된 코드만 올리며 합성 데이터와 개발용 계정으로만 쓴다. 이 문서는 개발 서버의 실행 절차이며 운영 배포 구조를 확정하지 않는다. 외부 공개 전에 필요한 결정은 [아직 정하지 않은 것](#아직-정하지-않은-것)에 둔다.

저장소는 공개 저장소다. 서버 주소, 인스턴스 ID, 키 파일과 `.env` 값을 이 문서, 이슈와 PR에 남기지 않는다.

## 구성

| 서비스 | 켜는 방법 | 하는 일 |
| --- | --- | --- |
| `api` | 기본 | FastAPI. 호스트의 `127.0.0.1:8000`에만 열린다. 세션 폐기 목록이 메모리에 있으므로 프로세스는 하나다 |
| `speech-worker` | `--profile workers` | 음성 STT worker. AI 서버 연결 경로가 정해진 뒤 켠다 |
| `db` | `--profile local-db` | PostgreSQL 17. 외부 DB(RDS 등)를 쓰면 켜지 않는다. 데이터는 `postgres-data` 볼륨에 남는다 |

이미지에는 `.env`를 넣지 않는다([.dockerignore](../.dockerignore)). 컨테이너는 `backend/.env`의 값을 환경 변수로 받는다.

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
2. 보안 그룹의 인바운드는 SSH(22)만 팀원 IP로 연다. 8000과 5432는 열지 않는다.
3. S3를 쓸 때는 액세스 키 대신 두 버킷에 대한 `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`만 허용한 IAM 역할을 인스턴스에 붙인다. 코드는 boto3의 기본 자격증명 조회를 쓰므로 키 설정이 필요 없다.
4. 저장소를 받고 develop을 쓴다.

   ```bash
   git clone https://github.com/kakaotechcampus-4/ktc4-chungnam-1.git
   cd ktc4-chungnam-1/backend
   git switch develop
   ```

5. `.env`를 만들고 다른 사용자가 읽지 못하게 한다.

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

   | 항목 | 값 |
   | --- | --- |
   | `SAEROK_POSTGRES_PASSWORD` | db 컨테이너를 쓸 때 새로 만든 비밀번호 |
   | `SAEROK_DATABASE_URL` | db 컨테이너면 `postgresql+psycopg://saerok:<비밀번호>@db:5432/saerok` |
   | `SAEROK_SESSION_SECRET` | `openssl rand -base64 48`로 만든 값. 로컬 개발의 값과 다르게 둔다 |
   | `SAEROK_GOOGLE_CLIENT_IDS` | FE가 쓰는 클라이언트 ID([README](../README.md)의 `aud` 설명) |
   | `SAEROK_AI_SERVER_URL` | 컨테이너 안의 `127.0.0.1`은 컨테이너 자신이다. AI 서버 연결 경로가 정해진 뒤 채운다 |
   | S3 버킷 | 비워 두면 음성 제출과 사진 업로드를 거절한다 |

6. DB, migration, API 순서로 띄운다.

   ```bash
   docker compose --profile local-db up -d db
   docker compose build
   docker compose run --rm api alembic upgrade head
   docker compose up -d api
   curl http://127.0.0.1:8000/health/live
   ```

### 갱신

develop에 병합된 뒤 실행한다. migration은 이 단계에서만 적용한다.

```bash
git pull
docker compose build
docker compose run --rm api alembic upgrade head
docker compose up -d api
```

상태는 `docker compose ps`, 로그는 `docker compose logs -f api`로 본다. `docker compose down -v`는 DB 볼륨까지 지운다.

### 외부 공개 전에 접속하기

API는 인스턴스 밖에서 보이지 않는다. 팀원은 SSH 터널로 붙는다.

```bash
ssh -N -L 8000:127.0.0.1:8000 <사용자>@<인스턴스 주소>
```

터널을 연 PC에서는 `http://127.0.0.1:8000`, Android 에뮬레이터에서는 `http://10.0.2.2:8000`으로 접속한다. 앱의 debug 빌드만 평문 HTTP를 허용한다.

## 아직 정하지 않은 것

- **외부 공개.** 외부에서 접근할 수 있는 배포는 [ADR-004](../../docs/architecture/decisions/ADR-004-python-fastapi-reference-environment.md)의 재검토 조건이다. 개발 서버 ADR, HTTPS 앞단(도메인과 Caddy 또는 nginx, 또는 ALB)과 접근 제한을 정한 뒤 연다.
- **AI 서버 연결.** AI 서버는 온프레미스 GPU에 있다([ADR-006](../../docs/architecture/decisions/ADR-006-server-side-ai-processing.md)). EC2에서 닿는 경로, 또는 백엔드를 GPU 장비 옆에 둘지는 정하지 않았다. 정하기 전에는 `speech-worker`를 켜지 않는다.
- **DB 위치와 백업.** 인스턴스의 db 컨테이너와 RDS 중 무엇을 쓸지, 백업 여부는 정하지 않았다. 지금 개발 서버의 데이터는 합성 데이터만 둔다.
- **배포 자동화.** 지금은 위의 수동 절차다. GitHub Actions로 옮길 때 `.github/workflows/`는 카테캠 운영진이 제공하는 디렉터리이므로 먼저 확인한다.
