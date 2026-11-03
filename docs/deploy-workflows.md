# 배포 후보 빌드와 수동 배포 workflow

[로컬 작업] `.github/workflows/release-build.yml`과 `.github/workflows/deploy.yml`은 아직 GitHub에 올리지 않았고 Actions에서 실행한 적이 없다. 아래 시크릿, 변수, Environment와 AWS 권한도 설정되어 있지 않다. 설정하기 전에 Deploy를 실행하면 첫 단계에서 멈춘다.

이 workflow가 옮긴 수동 절차는 [컨테이너 실행과 개발 서버 배포](../backend/docs/deployment.md#갱신)의 "갱신"이다. 그 문서는 BE 담당 영역이라 이 문서에서 따로 설명한다. GitHub에 올리기 전에 `.github/workflows/`가 카테캠 운영진이 제공하는 디렉터리라는 점을 운영진과 확인한다. 병합 시 자동 배포는 하지 않기로 범위를 정했다.

## 자동화 범위

| 구분 | 자동 | 사람 |
| --- | --- | --- |
| PR 검사 | [제품 테스트 CI](product-tests.md) | 검토와 병합 |
| 배포 후보 | `v*` 태그 push나 수동 실행 시 Release build: 같은 커밋에서 제품 테스트를 다시 돌리고 백엔드 이미지와 Android APK·AAB를 만든다 | 배포할 SHA 선택 |
| 배포 | Deploy: 사전 점검, 백업과 격리 복원 검사, 분석 접수와 worker 임대 중지와 실행 중 작업 0건 대기, 빌드, migration, 컨테이너 교체, 사후 점검, 접수와 임대 재개, 배포 기록 | 실행, `production` 승인, 기능 확인 |
| 되돌리기 | 실패 시 이전 커밋과 이전 이미지가 들어간 명령 안내 출력 | 판단과 실행 |
| 앱 배포 | 빌드와 artifact 업로드 | Play 업로드와 테스트 설치 안내 |

CD는 수동 실행에 승인을 붙이는 방식이며 병합할 때 자동으로 배포하지 않는다. 이유는 다음과 같다.

- 서버가 개발 서버 한 대다. [배포 중 분석 접수 중지](../backend/docs/deployment-control.md)는 녹음 분석, 분석 다시 요청, 짧은 음성 전사, 카드 생성 요청과 worker의 새 작업 임대만 멈추고 조회, 소감 저장, 사진 업로드 같은 다른 요청은 막지 않는다. 그리고 [배포 전 백업, 버전 대조와 되돌리기](../backend/docs/release-safety.md)의 2단계는 진행 중 작업을 확인한 뒤에만 교체하도록 한다. Deploy는 처리 중인 작업이 있으면 멈추지만 언제 배포할지는 사람이 정한다.
- migration은 되돌리기를 자동화하지 않는다. `alembic downgrade`와 운영 DB 복원은 손실 범위와 승인자를 먼저 정해야 한다.
- 로그인, 카드 생성, 녹음부터 리포트, 다음 카드까지의 확인과 옛 앱과 새 앱의 확인은 workflow가 하지 않는다.
- AWS 지원이 11월 20일에 끝난다. 이미지 레지스트리 같은 새 인프라를 들이지 않고 지금 수동 절차를 그대로 옮겼다.

## 커밋, 이미지, 앱 버전, migration과 되돌릴 버전의 연결

| 항목 | Release build 기록 | Deploy 기록 |
| --- | --- | --- |
| 커밋 | 실행한 커밋 SHA | 입력 SHA. 대상 브랜치에 포함돼 있고 성공한 Release build가 있어야 시작한다 |
| 이미지 | `saerok-backend:<SHA>`, 이미지 ID, buildx digest, revision 라벨 확인 | 서버에서 같은 SHA로 다시 빌드한 이미지 ID, `saerok-backend:<SHA>` 태그, 실행 중인 모든 서비스의 revision 라벨이 SHA와 같은지 |
| 앱 버전 | versionName, versionCode(APK에서 aapt2로 확인), 서명 방식, APK·AAB SHA-256 | 없음 |
| migration | 이미지 안의 Alembic head(하나여야 함) | 배포 전 DB revision, 새 이미지의 head, 사후 `runtime_check --expected-revision` 일치 |
| 상태 검사 | 이미지의 API와 worker 모듈 불러오기 검사 | 배포 전 `/health/ready`, 배포 후 `/health/live`, `/health/ready` |
| 되돌릴 버전 | 없음 | 이전 커밋, 이전 이미지 ID, 보존 태그 `saerok-backend:rollback-<실행 번호>`, 백업 파일 이름 |

이미지는 레지스트리에 올리지 않는다. Release build의 이미지 ID와 서버에서 다시 만든 이미지 ID는 다를 수 있으며, 같은 커밋이라는 근거는 revision 라벨과 Alembic head다. Release build 요약과 `release-manifest-<SHA>` artifact, Deploy 요약과 서버의 배포 기록 파일을 SHA로 맞춰 본다.

## Release build

- 제품 테스트는 `product-tests.yml`의 `workflow_call`로 같은 검사를 다시 실행한다.
- 백엔드 이미지는 `docker buildx build --build-context ai=../ai --build-arg SOURCE_REVISION=<SHA> --load`로 한 번 만든다. api, card-worker, speech-worker가 같은 이미지를 쓴다. 이미지 안에서 DB 없이 Alembic head를 읽고, `tests/test_container_packages.py`를 그 이미지로 실행한다.
- Android 빌드는 `SAEROK_API_BASE_URL`과 `SAEROK_GOOGLE_SERVER_CLIENT_ID`를 `--dart-define`으로 넘긴다. [릴리스 설정 검사](../app/lib/app/release_config.dart)와 같은 기준으로 값을 먼저 확인하고, 비어 있거나 https가 아니면 빌드하지 않는다.
- versionName과 versionCode는 `app/pubspec.yaml`의 `version`을 쓴다. 수동 실행에서는 `build_name`, `build_number` 입력으로 바꿀 수 있다. 태그 이름과 versionName이 다르면 경고만 남긴다.
- 업로드 키 시크릿 네 개가 모두 있을 때만 `android/key.properties`를 만들어 업로드 키로 서명하고 끝나면 지운다. keystore 시크릿은 줄바꿈과 공백을 지운 뒤 디코딩하고, 빌드 전에 `keytool -list`로 비밀번호와 별칭이 맞는지 확인한다. 없으면 [build.gradle.kts](../app/android/app/build.gradle.kts)의 기존 동작대로 디버그 키로 서명하고 요약에 `debug`라고 적는다. 이 빌드는 Play에 올릴 수 없고, 실행기마다 디버그 키가 달라 기존 설치본 위에 업데이트되지 않을 수 있다.
- 공개 저장소의 artifact는 로그인한 GitHub 사용자라면 받을 수 있다. 앱 artifact는 7일만 보관하며, 수동 실행에서는 `upload_app`을 끄고 빌드만 확인할 수 있다. 승인된 비공개 테스트 경로를 대신하지 않는다.
- 공개 저장소의 Actions 로그도 누구나 볼 수 있다. 저장소 변수(vars)는 로그에 그대로 보이므로 서버 주소는 같은 이름의 시크릿으로 넣는 것을 권한다. 시크릿이 있으면 시크릿을, 없으면 변수를 쓴다.

## Deploy

GitHub의 Actions 탭에서 Deploy (manual)를 고르고 SHA, 대상 브랜치, `deploy <SHA 앞 12자리>`를 입력한다. `production` 승인 뒤 AWS SSM `AWS-RunShellScript`로 서버에서 단계별 명령을 실행한다. SSH 포트를 GitHub 실행기에 열지 않고, 장기 액세스 키 대신 GitHub OIDC로 짧은 자격증명을 받는다. 배포는 `deploy-production` 동시 실행 그룹으로 하나씩 진행되며, 진행 중인 배포를 취소하지 않는다. GitHub는 이 그룹에 대기 실행을 하나만 둔다. 배포가 진행 중이고 하나가 대기하는 상태에서 새 요청이 오면, 먼저 대기하던 요청은 취소되고 새 요청이 대기한다. 취소된 요청은 다시 실행한다.

| 순서 | 하는 일 | 실패하면 |
| --- | --- | --- |
| 요청 확인 | SHA 형식, 확인 문자열, 대상 브랜치 포함 여부, 해당 SHA의 성공한 Release build, `production` 환경의 Required reviewers 지정 여부 | 승인 요청 전에 멈춘다 |
| 1. 사전 점검 | 도구와 Python 3.11 이상, 추적 파일 변경과 무시되지 않은 새 파일 없음(7단계 기록과 같은 `git status --porcelain` 기준), api 실행 중, `/health/ready` 200, `runtime_check`의 DB 조회 성공과 처리 중 작업 0건. 이전 커밋과 이전 이미지 ID를 기록하고 이전 이미지에 보존 태그를 붙인다 | 아무것도 바꾸지 않고 멈춘다 |
| 2. 백업 | `scripts/verify_database_backup.py`로 새 백업과 격리 복원 검사. `restoreVerified`가 true여야 한다 | 멈춘다. 백업 파일은 남는다 |
| 2b. 접수 중지 | 실행 중인(배포 전) api 컨테이너의 `python -m app.ops.deployment_control`로 `pause-admissions`를 보내고, 대기 중인 녹음 분석과 카드 생성이 빠지기를 5분까지 기다린 뒤 `pause-workers`를 보낸다. 10초마다 `status`를 읽어 `analysisDrained`가 true가 될 때까지 10분까지 기다린다. 아래 "분석 접수 중지" 참고 | 기한 안에 비지 않거나 명령이 실패하면 이 단계 안에서 `resume-all`로 다시 열고 멈춘다. 체크아웃, 이미지, DB는 바꾸지 않았다 |
| 3. 빌드 | `git fetch origin <SHA>`, `git checkout --detach <SHA>`, `docker compose build --build-arg SOURCE_REVISION=<SHA> api`. revision 라벨과 단일 Alembic head를 확인하고 `saerok-backend:<SHA>` 태그를 붙인다 | 서버 체크아웃과 이미지 이름을 이전 상태로 되돌리고 멈춘다. 컨테이너는 그대로다. 2b에서 접수를 멈췄으면 배포 전 버전의 CLI로 다시 연다 |
| 4. migration | `docker compose run --rm --no-deps api alembic upgrade head` | 멈추고 되돌리기 안내를 출력한다. 접수와 임대는 중지 상태로 둔다 |
| 5. 교체 | `docker compose up -d --no-build <DEPLOY_SERVICES>`. worker 유예 시간을 줄이지 않는다 | 멈추고 되돌리기 안내를 출력한다. 접수와 임대는 중지 상태로 둔다 |
| 6. 사후 점검 | `/health/live`, `/health/ready`를 2분까지 기다리고 `runtime_check --expected-revision <head>`가 일치해야 한다. 기한 지난 임대 같은 다른 경고는 출력만 한다 | 멈추고 되돌리기 안내를 출력한다. 접수와 임대는 중지 상태로 둔다 |
| 6b. 접수 재개 | 2b에서 멈췄을 때만. 새 이미지의 CLI로 `resume-workers`, `status`, `resume-all`을 차례로 보내고 두 값이 모두 열렸는지 확인한다 | 어디까지 열렸는지 출력하고 멈춘다. 사후 점검은 통과한 상태다 |
| 7. 기록 | `scripts/capture_release.py` 결과를 `DEPLOY_RELEASE_DIR/release-<UTC>-<SHA 12자리>.json`에 저장한다. 모든 서비스가 실행 중이고 revision 라벨이 SHA와 같아야 한다 | override가 다른 이미지를 고정한 경우 등을 실패로 알린다 |

### 분석 접수 중지

[로컬 작업] [배포 중 분석 접수 중지](../backend/docs/deployment-control.md)(DB revision `f95c2d7eb143`)를 2b와 6b 단계로 연결했다. 실제 서버와 Actions에서는 실행하지 않았다.

- 2b는 백업 뒤, 체크아웃과 migration 전에 돈다. 접수를 멈추는 시간에 백업과 복원 검사(최대 30분)가 들어가지 않게 하려는 것이다. BE 문서는 접수를 멈춘 뒤 백업하는 순서를 적고 있어, 이 순서에서는 백업 뒤 2b 전까지 접수된 분석이 백업에 들어가지 않는다. 어느 순서로 할지는 BE 담당과 확인한다.
- 명령은 지금 실행 중인 api 컨테이너 안에서 `docker compose exec -T api python -m app.ops.deployment_control <동작>`으로 보낸다. 연결 정보는 컨테이너의 환경 설정을 쓰고 명령행과 로그에 넣지 않는다.
- 먼저 실행 중인 이미지에 `app.ops.deployment_control`이 있는지와 DB에 `deployment_control` 표가 있는지(`to_regclass`) 본다. `f95c2d7eb143`을 처음 들여오는 배포에서는 둘 다 없으므로 `CONTROL_SKIPPED`를 출력하고 접수 중지 없이 진행한다. 처리 중 작업 0건은 1단계가 이미 확인했다. 이때 구버전 worker는 제어를 따르지 않으며, BE 문서 1단계의 별도 트래픽 제한이 필요하면 사람이 한다. 새 migration이 만든 표의 기본값은 허용이라 6b는 건너뛴다.
- 코드와 표 중 하나만 있거나, 배포 전부터 이미 중지 상태면 누가 멈췄는지 확인하도록 아무것도 바꾸지 않고 멈춘다.
- `pause-admissions` 뒤 대기 녹음 분석과 카드 생성, 실행 중 작업이 0건이 되기를 5분까지 기다린다. 대기 카드의 시작 제한 시간은 중지로 늘어나지 않으므로 먼저 비우려는 것이다. 남으면 `CONTROL_QUEUE_LEFT`와 건수를 남기고 `pause-workers`로 넘어간다. 사진 업로드는 중지 대상이 아니어서 대기 사진은 기다리지 않는다.
- `pause-workers` 뒤 10초마다 `status`를 읽어 `analysisDrained`가 true가 되기를 10분까지 기다린다. 로그에는 두 중지 값, `analysisDrained`와 진행, 대기, 실행 연결 건수만 남긴다.
- 2b에서 실패하면 그 단계 안에서 `resume-all`로 다시 연다(`CONTROL_RESUMED_AFTER_FAILURE`). 다시 열지 못하면 `CONTROL_RESUME_FAILED`를 남긴다.
- 3단계 빌드에서 실패하면 migration을 시작하지 않았으므로 배포 전 버전의 CLI로 다시 연다.
- 4단계부터 실패하면 자동으로 열지 않는다. migration이 일부 적용됐을 수 있어, DB revision을 확인하고 새 이미지를 유지할지 되돌릴지 정한 뒤 여는 순서를 되돌리기 안내에 출력한다. 취소나 시간 초과로 끝난 실행도 자동으로 열지 않는다.
- 사후 점검을 통과하면 6b가 `resume-workers`, `status`, `resume-all` 순서로 연다. BE 문서가 두 명령 사이에 두는 대기 작업, STT와 ML 설정 확인과 옛 앱/새 앱 확인은 사람이 한다.

서버 출력은 Actions 로그에 남으므로 서버 안에서 `127.0.0.1`로만 점검하고 `.env`와 `docker compose config` 원문을 출력하지 않는다. 백업 결과의 복원 행 수(`restoredRowCounts`)와 `runtime_check`의 상태별 집계도 운영 정보라 로그에 그대로 찍지 않는다. 로그에는 백업의 `restoreVerified`, `archive`, `sha256`, 단계와 오류 코드, `runtime_check`의 issues와 revision, 판정에 쓴 처리 중 작업 수만 남기고, 전체 JSON은 서버의 `DEPLOY_RELEASE_DIR/runs/<실행 번호>/`에만 둔다. 백업과 배포 기록 파일은 0600 또는 0700 권한으로 만든다.

이 workflow로 한 번 배포한 서버는 커밋을 직접 가리키는 detached HEAD 상태가 된다. 이후 손으로 갱신할 때는 `git pull` 대신 `git fetch origin <SHA>`와 `git checkout --detach <SHA>`를 쓴다.

서버가 갖춰야 할 조건은 다음과 같다. 하나라도 다르면 이 workflow를 쓰지 않고 [수동 절차](../backend/docs/deployment.md#갱신)를 따른다.

- SSM Agent가 실행 중이고 인스턴스 역할에 `AmazonSSMManagedInstanceCore`가 있다. SSM 명령은 root로 실행되며 git 쓰기는 `sudo -u <DEPLOY_HOST_USER>`와 umask 022로 한다. root에서 하는 git 읽기는 `--no-optional-locks`(git 2.15 이상)로 `.git/index`를 다시 쓰지 않는다. root 소유 index가 남으면 저장소 소유자의 checkout이 실패하고, umask 077로 checkout한 파일은 이미지 안의 비root 사용자가 읽지 못한다.
- `docker compose`, `git`, `curl`, `sudo`와 Python 3.11 이상이 있다. `scripts/`의 도구가 3.11 기능을 쓴다.
- DB는 compose의 `db` 컨테이너다. RDS를 쓰면 백업 도구가 동작하지 않으므로 RDS 스냅샷 절차를 따로 정한 뒤에 쓴다.
- 서버 저장소의 `origin`이 이 GitHub 저장소이고 서버에서 받을 수 있다.
- speech-worker까지 교체하려면 `DEPLOY_SERVICES=api card-worker speech-worker`, `DEPLOY_COMPOSE_PROFILES=workers`로 둔다. 실제 서버의 compose 파일 조합이 다르면 `DEPLOY_COMPOSE_FILES`에 적용 순서대로 적는다.

## 팀이 설정할 항목

| 위치 | 이름 | 필수 | 내용 |
| --- | --- | --- | --- |
| 저장소 시크릿 또는 변수 | `SAEROK_API_BASE_URL` | Release build | 앱이 쓸 https 서버 주소. 로그 노출을 피하려면 시크릿 |
| 저장소 시크릿 또는 변수 | `SAEROK_GOOGLE_SERVER_CLIENT_ID` | Release build | `SAEROK_GOOGLE_CLIENT_IDS`와 같은 웹 클라이언트 ID |
| 저장소 시크릿 | `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD` | 선택 | 업로드 키. 없으면 디버그 키 서명 |
| Environment `production` 설정 | Required reviewers, Deployment branches | Deploy | 승인자 지정. 배포 브랜치를 `develop`과 `main`으로 제한한다. 수동 실행은 고른 브랜치의 workflow 파일을 쓰므로, 제한이 없으면 다른 브랜치에서 고친 workflow가 환경 시크릿을 받을 수 있다 |
| Environment 시크릿 | `AWS_DEPLOY_ROLE_ARN` | Deploy | OIDC로 맡을 IAM 역할 |
| Environment 시크릿 | `DEPLOY_INSTANCE_ID` | Deploy | 대상 EC2 인스턴스 ID. 로그에서 가리도록 시크릿으로 둔다 |
| Environment 변수 | `AWS_REGION`, `DEPLOY_REPO_DIR`, `DEPLOY_BACKUP_DIR`, `DEPLOY_RELEASE_DIR` | Deploy | 리전, 서버 저장소 절대 경로, 저장소 밖의 백업 경로, 저장소 밖의 배포 기록 경로. 두 경로가 저장소 안이면 시작 전에 거절한다 |
| Environment 변수 | `DEPLOY_HOST_USER`(`ubuntu`), `DEPLOY_HOST_PYTHON`(`python3`), `DEPLOY_COMPOSE_FILES`(`compose.yml`), `DEPLOY_COMPOSE_PROFILES`(없음), `DEPLOY_SERVICES`(`api card-worker`), `DEPLOY_DB_CONTAINER`(`saerok-db-1`), `DEPLOY_DB_NAME`(`saerok`), `DEPLOY_DB_USER`(`saerok`) | 선택 | 괄호 안이 기본값 |
| AWS IAM | GitHub OIDC 공급자 | Deploy | `token.actions.githubusercontent.com`, audience `sts.amazonaws.com` |
| AWS IAM | 배포 역할의 신뢰 정책 | Deploy | `sub`를 `repo:kakaotechcampus-4/ktc4-chungnam-1:environment:production`으로 제한 |
| AWS IAM | 배포 역할의 권한 | Deploy | 대상 인스턴스와 `AWS-RunShellScript` 문서에 대한 `ssm:SendCommand`, `ssm:GetCommandInvocation` |

설정 순서를 지킨다. `production` 환경은 workflow가 처음 참조할 때 보호 설정 없이 자동으로 생길 수 있고, 같은 이름의 시크릿과 변수가 저장소 수준에 있으면 승인과 무관하게 배포 작업에 주어진다. IAM 신뢰 정책의 `sub`도 `environment:production`이라 그대로 통과한다.

1. `production` 환경을 만들고 Required reviewers와 Deployment branches를 먼저 지정한다.
2. 그다음 Deploy용 시크릿과 변수를 Environment 수준에만 넣는다. 저장소 수준에는 두지 않는다.
3. Deploy의 요청 확인 작업은 GitHub API로 Required reviewers 지정 여부를 확인하고, 없거나 확인하지 못하면 멈춘다. 저장소 수준 시크릿 여부는 workflow가 확인하지 못하므로 설정한 사람이 확인한다.

값에 따옴표, 공백(목록 구분 제외), `..`가 들어가면 서버 명령에 넣기 전에 거절한다. IAM 변경과 Environment 설정은 저장소 밖의 운영 변경이므로 담당자 승인 후 진행한다.

## 실패와 되돌리기

Deploy는 자동으로 되돌리지 않는다. 실패하면 요약에 이전 커밋, 이전 이미지 ID, 보존 태그와 명령을 출력한다.

- migration 전에 멈췄다면 실행 중인 컨테이너는 바뀌지 않았다. 빌드 단계 실패는 서버 체크아웃을 이전 위치로 되돌린다.
- migration 단계가 실행됐다면 실패했더라도 `alembic current`로 DB revision을 먼저 확인한다. 이전 이미지가 새 스키마를 읽을 수 있다고 확인된 경우에만 보존 태그를 이미지 이름에 다시 붙이고 `docker compose up -d --no-build`로 되돌린다. 태그를 붙이기 전에 이미지 ID를 대조한다.
- 새 migration이 들어간 배포 뒤에 이 workflow로 이전 SHA를 다시 배포하면 이전 코드에 없는 revision 때문에 `alembic upgrade head`가 실패한다. 이 경우는 위의 이미지 되돌리기와 [이상이 생겼을 때](../backend/docs/release-safety.md#이상이-생겼을-때)를 따른다.
- `alembic downgrade`와 운영 DB 복원은 workflow에 넣지 않았다. `f95c2d7eb143`의 downgrade는 접수나 임대가 중지 상태면 거절되므로 먼저 `resume-all`로 연다.
- 분석 접수와 worker 임대를 언제 다시 여는지는 되돌리기 안내의 "분석 접수와 worker 임대"에 실패 지점별로 출력한다. migration 전 실패는 다시 열었는지, migration 뒤 실패는 무엇을 확인한 뒤 어떤 순서로 열지 적는다.
- 배포 작업의 시간 한도는 245분이다. 정상 경로의 단계별 SSM 대기 한도(실행 한도 + 300초) 합계 약 230분(접수 중지 25분, 재개 10분 포함)보다 길다. 대기 기한을 넘기거나 실행이 취소, 시간 초과로 끝나도 SSM 명령은 서버에서 계속 돌 수 있다. workflow는 SSM 명령을 취소하지 않는다. migration이나 컨테이너 교체를 중간에 끊으면 더 나쁜 상태가 남을 수 있어서다. 이때도 되돌리기 안내를 출력하며, 서버의 마지막 명령이 끝난 것을 확인하기 전에는 다시 배포하거나 되돌리지 않는다.

## 이미지 태그 정리

Deploy는 실행할 때마다 `saerok-backend:rollback-<실행 번호>`와 `saerok-backend:<SHA>` 태그를 남기고 지우지 않는다. 태그가 이전 이미지를 붙잡고 있어 EC2 디스크가 계속 줄어든다. workflow는 운영 서버의 이미지를 지우지 않으므로, 담당자가 배포가 없는 시간에 서버의 `backend` 디렉터리에서 정리한다. 이 절차는 실제 서버에서 실행해 보지 않았다.

1. 아래로 지울 후보를 먼저 출력해 확인한다. 각 종류에서 최근 3개는 남긴다. 직전 배포의 보존 태그는 되돌리기에 필요하므로 지우지 않는다.

   ```bash
   docker image ls saerok-backend --format '{{.CreatedAt}}|{{.Repository}}:{{.Tag}}' | sort -r | cut -d'|' -f2 | grep -E ':rollback-' | tail -n +4
   docker image ls saerok-backend --format '{{.CreatedAt}}|{{.Repository}}:{{.Tag}}' | sort -r | cut -d'|' -f2 | grep -E ':[0-9a-f]{40}$' | tail -n +4
   ```

2. 확인한 태그만 `docker image rm <태그>`로 지운다. 실행 중인 컨테이너가 쓰는 이미지의 마지막 태그는 Docker가 거절하므로 `-f`를 붙이지 않는다. compose가 쓰는 이미지 이름(`docker compose config`의 `image`)은 지우지 않는다.
3. `docker image prune`으로 태그가 없어진 이미지만 정리한다. `docker image prune -a`는 컨테이너가 쓰지 않는 이미지를 모두 지워 보존 태그가 없는 이전 이미지까지 사라질 수 있고, `docker system prune`은 멈춘 컨테이너와 네트워크까지 지우므로 쓰지 않는다.

## 검증 범위

11월 3일 로컬 통합 브랜치에서 확인한 것과 확인하지 않은 것이다. 그 브랜치에는 이 PR에 없는 다른 미병합 변경(백업 도구, 배포 중 접수 중지, 이미지 패키지 검사 등)이 함께 들어 있었다.

- actionlint 1.7.12로 저장소의 workflow 일곱 개 전체를 검사했다. `product-tests.yml`과 `release-build.yml`은 shellcheck 0.11.0 연동까지 통과했다. `deploy.yml`은 Windows에서 shellcheck 연동 실행이 끝나지 않아, 두 새 workflow의 `run` 스크립트와 서버에 보낼 스크립트를 따로 꺼내 shellcheck로 검사했다.
- 로컬 Docker에서 Release build와 같은 buildx 명령으로 이미지를 만들고, revision 라벨, Alembic head `e84b1c6da032`와 `tests/test_container_packages.py`(2개 통과)를 확인했다.
- Flutter 3.44.8로 임시 https 주소와 임시 클라이언트 ID를 넣어 release APK를 만들고 aapt2로 versionCode를 확인했다. AAB와 업로드 키 서명은 로컬에서 만들지 않았다.
- 서버 단계 스크립트는 dash 문법 검사와, docker, git, curl을 흉내 낸 컨테이너에서 정상 경로와 실패 경로(처리 중 작업, 추적 파일 변경, revision 불일치 시 체크아웃 복원, migration 불일치)를 실행했다. 실제 EC2, SSM, OIDC, 백업 도구의 실제 복원과 GitHub Actions 실행은 확인하지 않았다.
- 리뷰 반영 뒤(11월 3일) 다시 확인했다. actionlint 1.7.12는 shellcheck 연동 없이 일곱 개 모두 통과했고, `release-build.yml`과 `product-tests.yml`은 shellcheck 0.11.0 연동까지 통과했다. `deploy.yml`은 연동 실행이 4분 안에 끝나지 않아, 서버 단계 스크립트 일곱 개를 실제 실행기 단계로 만들어 `bash --posix -n`, `dash -n`, `shellcheck -s sh`(공통 앞부분의 미사용 변수 경고 SC2034 제외)로, 실행기 `run` 스크립트 열네 개(배포 작업 10, 요청 확인 작업 4)를 `bash -n`과 shellcheck로 검사해 모두 통과했다. 로그를 줄인 Python 부분은 예시 JSON과 깨진 입력으로, keystore 처리는 CRLF로 줄바꿈한 임시 키로 실행했다. Required reviewers 확인 API, root에서의 git index와 umask 동작은 실제 GitHub와 서버에서 확인하지 않았다.
- 분석 접수 중지 연결 뒤(11월 3일). actionlint 1.7.12를 shellcheck 연동 없이(`-shellcheck=`) 일곱 개 모두에 돌려 통과했다. 이 PC에는 shellcheck가 없어 이번 변경에는 shellcheck를 돌리지 않았다. `deploy.yml`의 실행기 `run` 스크립트 열일곱 개를 `bash -n`으로, 서버 단계 스크립트 열 개를 공통 앞부분과 합쳐 `bash --posix -n`과 `dash -n`으로 검사해 모두 통과했다. 2b, 6b와 migration 전 재개 단계는 docker와 CLI를 흉내 낸 대역으로 dash에서 열세 경우(최초 도입 건너뛰기, 코드와 표 불일치 두 경우, 도구 확인 오류, 이미 중지 상태, 정상 중지, 대기 작업이 남은 채 진행, 기한 초과 뒤 재개, 임대 중지 실패 뒤 재개, 재개 실패, 사후 재개, 사후 재개 일부 실패, migration 전 재개)를 실행해 기대한 종료 코드와 중지 상태를 확인했다. 실제 CLI, PostgreSQL, docker compose, SSM과 GitHub Actions에서는 실행하지 않았다.
