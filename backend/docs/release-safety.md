# 배포 전 백업, 버전 대조와 되돌리기

이 문서는 배포 준비 절차다. 문서를 추가하거나 로컬 검사에 통과했다고 운영 변경이
승인된 것은 아니다. 현재 열린 PR은 각 작성자의 작업으로 유지하며, 병합된 버전을
별도 통합 작업공간에서 다시 검증한다.

현재 구현 (2026-11-09 기준): #256(11/7 병합) 이후 운영 배포는 이 문서의 백업, 버전 대조와
교체 순서를 옮긴 [승인 배포 workflow](../../docs/deploy-workflows.md)로 한다. 아래 수동 기준은
workflow가 하지 않는 판단(되돌리기, DB 복원, 앱 확인)의 기준으로 남긴다. workflow의 서버 조건이 맞지 않으면
손으로 배포하지 않고 서버 담당과 원인을 먼저 확인한다([서버 조건](../../docs/deploy-workflows.md#서버-조건)).
운영 BE는 develop `59190ba7`(11/9 14:42 KST Deploy run 42568179490)이다. 이 배포로 들어간 변경과 migration,
배포 뒤 사람이 따로 할 일은 [실제 실행 기록](../../docs/deploy-workflows.md#실제-실행-기록-2026-11-09-기준)에 둔다.
BE 배포가 끝나도 Android 앱은 바뀌지 않는다. 앱은 Play 게시나 따로 배포한 APK로만 바뀐다.

## 주소와 배포 대상

- 현재 앱이 사용하는 주소를 유지한다. 자동 할당 공인 IP에 새 Elastic IP를 붙이면 주소가 바뀐다. 기존 IP를 EIP로 전환하는 작업으로 취급하지 않는다.
- 11월 19일까지 인스턴스를 의도적으로 중지하지 않는 것을 기본으로 한다. 이 조건도 AWS 장애까지 막는 보장은 아니다. 주소 변경은 새 AAB와 옛 앱 영향을 함께 검토하는 별도 결정이다.
- versionCode 3의 설치 기기나 APK를 업데이트 전에 보존한다. 새 BE는 옛 앱과 새 앱으로 각각 확인한다. (11/5 운영 배포 전인 11/3에 쓴 항목이다. develop의 앱 버전은 `1.0.0+7`(#270)이다.)
- 1차 배포 후보는 검증한 develop SHA와 팀이 병합한 #188~#190이다. 처리 중 작업을 끊지 않는 배포 조건을 먼저 확인한다. 2차 배포는 추가 수정분을 별도로 검사한 SHA로 구분한다. (11/5 운영 배포 전인 11/3에 쓴 항목이다. 11/7 이후 배포 SHA와 교체 서비스는 Deploy workflow의 입력과 `DEPLOY_SERVICES`로 정한다.)
- API, card-worker, speech-worker, photo-worker를 모두 같은 검증 이미지로 맞춘다. photo-worker는 11/8 00:21 KST 배포(Deploy run 42385596940)부터 운영에서 실행된다. DB migration은 해당 SHA의 Alembic head와 대조한다. 열린 PR의 head를 운영에 바로 올리지 않는다.

## 배포 전 기록

`scripts/capture_release.py`에 저장소 경로와 실제 컨테이너 이름을 각각 지정한다.
이미지 ID와 태그, 이미지에 적힌 Git SHA, 실행 상태와 재시작 수를 JSON으로 출력한다.
`--compose-file`에는 실제 적용할 compose 파일을 순서대로 넣는다. 내용 대신 파일 해시,
심볼릭 링크 여부와 대상 파일명을 기록한다. 환경 변수 전체나 로그 원문은 출력하지 않는다.

Git 체크아웃의 SHA와 실행 이미지의 SHA는 다를 수 있다. 이미지 라벨이 없으면
그 SHA는 미확인으로 남긴다. 파일을 pull한 것만으로 배포 완료라고 쓰지 않는다.

특히 서버의 `compose.override.yml`이 예비 이미지 override를 가리키는 링크라면
기본 `docker compose up`도 임시 이미지를 계속 선택할 수 있다. 승인한 compose 파일
조합과 적용 순서를 명시하고, 실제 컨테이너의 image ID를 다시 확인한다.

기존 `stt-tunnel`과 새 `saerok-stt-backup.service`는 다른 경로다. card-worker와
speech-worker가 어느 주소를 쓰는지, 이전 터널을 쓰는 서비스가 남아 있는지 확인한다.
대체 경로 검증과 사용 관계 확인 전에는 어느 쪽도 제거하지 않는다.

현재 구현 (2026-11-09 기준, 운영 배포 기록): 운영 서버에서는 11/5 배포 때 speech-worker에 붙였던 임시 이미지와
설정을 걷어내며(#187의 11/5 운영 배포 기록) 임시 override 링크를 저장소 밖으로 옮겼고, 11/6 `stt-tunnel` 컨테이너를 지웠다.

## 백업과 격리 복원 검사

`scripts/verify_database_backup.py`는 PostgreSQL 17 컨테이너에서 `pg_dump`를 실행한다.
새 복원용 컨테이너는 `--network none`과 tmpfs를 사용하며 외부 포트를 열지 않는다.
운영 DB를 덮어쓰거나 기존 DB에 `--clean`을 실행하지 않는다.

필수 인수는 `--source-container`, `--source-database`, `--source-user`, `--backup-dir`다.
비밀번호를 인수로 받지 않는다. DB 컨테이너 안에서 허용된 로컬 인증을 사용하며,
인증이 거절되면 인증을 해제하지 말고 실패로 남긴다. 운영 실행은 별도 승인이 필요하다.
지금은 승인 배포 workflow가 `production` 승인 뒤 check와 deploy 실행마다 2단계에서 이 도구를 실행한다.

- 새 파일만 만든다. 기존 백업을 덮어쓰지 않는다.
- 복원용 DB는 컨테이너 내부 TCP 응답까지 기다린다. 초기화용 임시 Unix 소켓 서버를 준비 완료로 보지 않는다. 실패 기록에는 원문 오류 대신 중단 단계와 안전한 오류 코드를 남긴다.
- 백업의 SHA-256, 크기, 복원 성공 여부, 복원된 migration과 주요 테이블 건수를 기록한다.
- 이 실행에서 만든 라벨이 일치하는 복원용 컨테이너만 정리한다. 백업 파일은 실패해도 보존한다.
- 백업에는 개인정보가 들어갈 수 있다. 공개 GitHub에 넣지 않으며 암호화된 보관 위치와 접근 권한을 별도로 확인한다. Linux 파일은 0600으로 생성하지만 Windows에서는 디렉터리 ACL과 디스크 암호화를 따로 확인한다.

로컬 확인(2026-11-04): 로컬 Docker의 PostgreSQL 17에 최신 migration(`d73f0b5ca921`)과 합성 프로필 3건을 넣고 `verify_database_backup.py`를 실행했다. 4초 걸렸고 `restoreVerified: true`, 복원된 revision `d73f0b5ca921`, 사용자와 프로필과 이야기 각 3건이 원본과 같았으며 복원용 컨테이너는 지워졌다. 운영 DB에서 실행한 기록은 아니다.
- SQL 복원 성공은 서비스 복구 완료와 다르다. 앱 연결, 이미지와 migration 호환성, 외부 S3 파일까지 복원됐다는 뜻도 아니다.

운영 실행 기록: 11/7 check 실행 두 번(run 42345315160, 42383352798), 3단계에서 실패한 11/7 deploy 실행(run 42383634609), 11/8 deploy 실행 세 번(run 42385596940, 42397653863, 42485750502)과 11/9 deploy 실행(run 42568179490의 2차 시도)의 2단계가 모두 운영 DB 백업을 만들고 `restoreVerified: true`로 끝났다. 같은 실행의 1차 시도는 사전 점검에서 멈춰 백업을 만들지 않았다. 백업 파일은 서버의 백업 폴더에만 있다.

로컬 검증은 합성 DB에서만 한다. `tests/test_backup_restore_tool.py`의 Docker 복원 시험은
`SAELOG_BACKUP_TEST_CONTAINER`를 명시했을 때만 실행한다. 운영 컨테이너를 테스트 fixture에
연결하지 않는다. 일반 CI에서는 Docker 복원 시험이 생략되므로 별도 결과를 첨부한다.

### 오래된 백업 정리(14일 보관)

2026-11-09 PM 결정: 배포 DB 백업은 14일 보관한다. Deploy는 `check`와 `deploy` 모두 실행할 때마다 운영 DB 전체 덤프를 `DEPLOY_BACKUP_DIR`에 하나씩 남기고 지우지 않는다([배포 workflow](../../docs/deploy-workflows.md)의 2단계). 정리는 서버의 systemd timer가 한다. timer는 새 백업을 만들지 않는다.

이 절차를 처음 쓸 때(11/4)는 매일 백업 검사와 정리를 차례로 돌리는 예시(복원 확인된 최근 7개를 남기고 7일 기준으로 정리)만 두고 운영 서버에 설치하지 않았으며, 보관 기한은 법률 문서에 맡겼다. #287(11/9 병합)이 이를 14일 보관과 아래 timer로 바꿨다.

`scripts/prune_database_backups.py`는 같은 폴더의 백업(`saelog-*.dump`)과 기록(`saelog-*.json`)을 한 쌍으로 읽는다. 기록에 `restoreVerified: true`가 있는 가장 최근 백업 `--keep`개(기본 1)는 날짜와 상관없이 남기고, 그 밖의 백업 중 만든 지 `--older-than-days`일(기본 14)이 지난 것을 지운다. 복원 검사에 실패한 백업도 14일이 지나면 지운다. 기본은 지울 목록만 출력하며 `--apply`를 줘야 지운다. 백업 폴더가 없으면 "지울 것 없음"으로 끝내지 않고 `BACKUP_DIR_NOT_FOUND`와 종료 코드 2로 실패한다. 폴더 목록이나 기록을 읽을 권한이 없을 때도 빈 폴더나 복원 확인 안 된 백업으로 추측하지 않고 `BACKUP_UNREADABLE`과 종료 코드 2로 실패한다.

- 이름이 `saelog-`로 시작하는 `.dump`와 같은 이름의 `.json`만 다룬다. 같은 폴더에 손으로 만든 다른 이름의 덤프나 설정 파일 사본이 있으면 14일이 지나도 남는다. 설치 때 폴더 목록을 보고 서버 담당이 따로 처리한다.
- 하루 한 번 돌기 때문에 14일이 지난 백업은 그다음 정리 때 지워진다. 그 사이 하루쯤 더 남을 수 있다.
- 최근 백업의 복원 검사가 실패해도 정리는 돈다. 복원 확인된 백업이 하나라도 있으면 가장 최근 것 1개는 항상 남으므로, 되돌릴 백업이 모두 사라지지는 않는다.
- 배포가 14일 넘게 없으면 그 1개가 14일보다 오래 남는다. 다음 배포의 백업이 복원 확인되면 그다음 정리에서 지운다.
- 남은 마지막 백업은 timer가 지우지 않는다. AWS 종료 전에 남은 백업을 모두 지우는 절차와 담당은 정하지 않았다([법률 문서의 배포 DB 백업 보관](../../docs/legal/README.md#배포-db-백업-보관)).

#### 서버에 설치

설치는 서버 담당이 한다. 이 문서 작성 시점에는 운영 서버에 설치하지 않았다. 파일은 [ops/backup-prune/](../ops/backup-prune/)에 있다.

현재 구현 (2026-11-09 기준): 이 파일들은 11/9 배포(develop `59190ba7`, Deploy run 42568179490)로 서버 저장소 체크아웃에 들어왔지만, Deploy는 timer를 설치하지 않는다. 팀 운영 기록에 설치 기록이 없어 운영 서버에는 설치되지 않았고, 백업은 Deploy를 실행할 때마다 쌓인다.

| 파일 | 설치 위치 | 하는 일 |
| --- | --- | --- |
| `saerok-backup-prune.service` | `/etc/systemd/system/` | root로 정리 스크립트를 `--backup-dir /opt/saerok-backups --keep 1 --older-than-days 14 --apply`로 한 번 실행한다. 네트워크를 쓰지 않고, 백업 폴더 밖은 읽기 전용이다 |
| `saerok-backup-prune.timer` | `/etc/systemd/system/` | 매일 자정(서버 시간)에 위 service를 실행한다. 서버가 꺼져 있어 놓친 실행은 켜진 뒤 한 번 한다 |
| `scripts/prune_database_backups.py` | `/opt/saerok-backup-prune/` | 정리 스크립트의 root 소유 사본 |

스크립트를 저장소 체크아웃에서 바로 실행하지 않고 root 소유 위치에 복사한다. 서버 저장소는 `ubuntu` 소유라서, 체크아웃의 파일을 root timer가 실행하면 그 계정이 바꾼 코드가 root로 돈다. 배포 workflow가 체크아웃을 바꿔도 timer가 쓰는 사본은 그대로이므로, 이 스크립트가 바뀐 커밋을 배포했으면 아래 1번의 복사를 다시 한다.

`--backup-dir`와 `ReadWritePaths`는 운영의 `DEPLOY_BACKUP_DIR`(`/opt/saerok-backups`)와 같아야 한다. 경로가 다르면 service 파일의 두 곳을 함께 바꾼다. 백업 폴더는 Deploy가 root 소유 0700으로 만든다. service는 root의 추가 권한(capability)을 모두 빼고 실행하므로, 폴더나 기록(`.json`)이 root 소유가 아니면 읽지 못하고 `BACKUP_UNREADABLE`로 실패한다. 아래 2번의 dry run은 `sudo`의 모든 권한으로 돌기 때문에 이 권한 문제는 3번에서 service를 직접 시작해야 드러난다.

ExecStart의 `/usr/bin/python3`는 3.11 이상이어야 한다. Deploy의 사전 점검과 같은 조건이며 운영 서버는 3.12다. 2번이 같은 해석기로 돌므로 버전이 맞지 않으면 2번에서 멈춘다.

서버 저장소의 `backend/`에서, 검토한 커밋이 체크아웃된 상태로 실행한다.

```bash
# 1. 스크립트와 unit 파일을 root 소유로 복사한다.
sudo install -d -o root -g root -m 0755 /opt/saerok-backup-prune
sudo install -o root -g root -m 0644 scripts/prune_database_backups.py /opt/saerok-backup-prune/
sudo install -o root -g root -m 0644 ops/backup-prune/saerok-backup-prune.service ops/backup-prune/saerok-backup-prune.timer /etc/systemd/system/
sudo systemctl daemon-reload

# 2. 지울 목록만 본다(--apply 없음, 아무것도 지우지 않는다). 폴더는 root 700이어야 한다.
#    목록에서 saelog-*.dump와 saelog-*.json 밖의 파일은 timer가 지우지 않으므로 따로 확인한다.
sudo stat -c '%U %a' /opt/saerok-backups
sudo ls -l /opt/saerok-backups
sudo /usr/bin/python3 -I /opt/saerok-backup-prune/prune_database_backups.py --backup-dir /opt/saerok-backups --keep 1 --older-than-days 14

# 3. timer를 켠다. 바로 한 번 돌려 보려면 service를 직접 시작한다.
sudo systemctl enable --now saerok-backup-prune.timer
sudo systemctl start saerok-backup-prune.service
```

확인:

```bash
systemctl list-timers saerok-backup-prune.timer --no-pager
systemctl show saerok-backup-prune.service -p Result -p ExecMainStatus
sudo journalctl -u saerok-backup-prune.service -n 40 --no-pager
```

- `list-timers`에 다음 실행 시각이 보이고, 마지막 실행 뒤 `Result=success`, `ExecMainStatus=0`이면 정상이다.
- journal에는 실행마다 JSON 한 개가 남는다. `keep`이 1, `olderThanDays`가 14인지, `removed`에 지운 백업의 파일 이름과 만든 시각만 있는지 본다. DB 내용과 경로 밖 정보는 남기지 않는다.
- service에 적은 백업 폴더가 없으면 스크립트가 시작되기 전에 systemd가 멈춘다. `ExecMainStatus=226`(NAMESPACE)이고 journal에 `Failed to set up mount namespacing`과 그 경로가 남는다. `BACKUP_DIR_NOT_FOUND`(종료 코드 2)는 2번처럼 스크립트를 직접 실행할 때 나온다. 둘 다 경로가 실제 백업 폴더와 다르다는 뜻이다.
- `BACKUP_UNREADABLE`(종료 코드 2)은 폴더나 기록이 root 소유가 아니라서 읽지 못했다는 뜻이다. 아무것도 지우지 않고 멈춘다. 실패는 자동으로 알리지 않으므로(운영 점검 알림이 이 service를 보지 않는다) 배포 뒤 `systemctl --failed`로 함께 확인한다.

되돌리기:

```bash
sudo systemctl disable --now saerok-backup-prune.timer
sudo rm /etc/systemd/system/saerok-backup-prune.service /etc/systemd/system/saerok-backup-prune.timer
sudo rm -r /opt/saerok-backup-prune
sudo systemctl daemon-reload
```

- 되돌려도 이미 지운 백업은 돌아오지 않는다. 남은 백업 파일은 건드리지 않는다.
- 되돌린 뒤에는 Deploy를 실행할 때마다 백업이 다시 쌓인다. 다른 정리 방법을 정하기 전까지 손으로 지울 목록(2번)을 확인한다.

로컬 확인(2026-11-09): WSL Ubuntu 22.04의 systemd 249에서 `systemd-analyze verify`로 두 unit 파일을 검사했고, 두 파일에 대한 경고 없이 종료 코드 0으로 끝났다. `tests/test_prune_database_backups.py`는 service의 실행 인수를 그대로 꺼내 합성 폴더에 실행하고 14일 기준과 가장 최근 복원 확인 백업 1개를 남기는지 확인한다.

같은 WSL에서 service 파일의 두 경로만 임시 위치로 바꿔 설치하고 합성 백업 폴더로 실행했다. 이 환경의 Python이 3.10이라 스크립트는 `datetime.UTC` 가져오기만 바꾼 사본을 썼다. root 소유 0700 폴더에서는 14일이 지난 백업 3개(복원 실패 1개 포함)를 지우고 13일 된 백업은 남겼다(`Result=success`). 폴더가 없으면 226/NAMESPACE로, 폴더나 가장 최근 복원 확인 백업의 기록이 다른 사용자 소유면 `BACKUP_UNREADABLE`과 종료 코드 2로 실패했고 아무것도 지우지 않았다. 운영 서버에서의 설치와 실행, 매일 도는 timer 동작은 확인하지 않았다.

## 승인 후 적용 순서

1. 적용 시간, 승인자, 배포 SHA, 이전 이미지 ID, DB revision과 백업 복원 결과를 확인한다.
2. 새 작업 접수와 진행 중 작업을 확인한다. worker만 꺼도 API 접수는 계속될 수 있다. 사용자 요청을 어떻게 차단할지 정하지 못했거나 진행 중 작업을 안전하게 끝내지 못하면 배포하지 않는다.
3. 깨끗한 체크아웃에서 `SOURCE_REVISION` build arg에 전체 SHA를 넣어 이미지를 빌드한다. 해당 이미지에 SHA별 태그를 붙이고 이전 이미지도 보존한다.
4. 승인한 유지보수 상태에서 migration을 적용한다. `init.sql`, DB 재생성, `compose down -v`를 쓰지 않는다.
5. 명시한 compose 조합으로 API와 worker 셋(card-worker, speech-worker, photo-worker)을 교체한다. 기존 override의 임시 image 값이 마지막에 덮어쓰지 않는지 확인한다.
6. 실제 image ID와 revision을 다시 기록하고 준비 상태, 로그인과 카드 생성, 녹음부터 리포트, 이야기 확인 후 다음 카드까지 검사한다.
7. 옛 앱과 새 앱을 모두 확인한 후 새 AAB를 올린다. 공개 배포 승인 전까지는 승인된 비공개 테스트 설치 경로를 안내한다. Play에 올리는 AAB는 업로드 키를 가진 릴리스 담당자가 서명해 만든다([FE README](../../app/README.md#play-업로드용-빌드)). 11/8 기준 Play 프로덕션 첫 게시는 검토 중이다([README의 배포와 시연](../../README.md#배포와-시연)).

1~6의 기록, 빌드, migration, 교체와 상태 확인은 지금 Deploy workflow가 한다. 2는 처리 중 작업이 있으면 멈추는 방식이며 API 접수는 막지 않는다. 4도 유지보수 상태로 바꾸지 않고 API를 띄운 채 migration을 적용한다. 6의 기능 확인과 7은 사람이 한다.

## 이상이 생겼을 때

- 이미지 문제이며 DB 하위 호환이 확인되면 이전에 기록한 이미지로 API와 worker를 함께 되돌린다. 이전 태그가 같은 내용을 가리킨다고 추측하지 말고 image ID를 대조한다.
- migration 뒤에는 예전 이미지가 새 DB를 읽을 수 있는지 먼저 확인한다. 검증하지 않은 `alembic downgrade`나 운영 DB 복원은 자동 실행하지 않는다.
- DB 복원이 필요하면 백업 이후 생성된 데이터의 보존 여부와 손실 범위, 접수 차단, 복원 대상과 승인자를 먼저 정한다. 복원 시험이 성공했다는 이유로 운영 DB를 덮어쓰지 않는다.
- 백업을 운영 DB에 복원하면 백업 시점 뒤의 탈퇴(계정 삭제), 프로필과 사진 삭제, 세션 폐기, 동의 철회와 S3 삭제 대기열 기록이 되돌아갈 수 있다. 이를 찾아 다시 적용하는 절차는 후속 작업이며 아직 없다. 복원을 판단할 때 이 범위를 손실 범위에 함께 적는다.
- 11월 10일 이후에는 새 기능을 동결하고 승인된 장애 또는 보안 수정만 재검증한다. AWS 지원 종료인 11월 20일 전에 필요한 자료와 설정을 권한이 있는 보관 위치에 확보한다.

이 변경은 수동 배포의 검증과 기록을 보완한다. 자동 운영 배포, IAM 변경과 Play 업로드는
실행하지 않는다. CI에서 검증한 버전과 실제 배포 버전의 일치 여부는 매 배포마다 확인한다.
