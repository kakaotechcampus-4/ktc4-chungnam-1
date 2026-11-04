# 배포 전 백업, 버전 대조와 되돌리기

이 문서는 배포 준비 절차다. 문서를 추가하거나 로컬 검사에 통과했다고 운영 변경이
승인된 것은 아니다. 현재 열린 PR은 각 작성자의 작업으로 유지하며, 병합된 버전을
별도 통합 작업공간에서 다시 검증한다.

## 주소와 배포 대상

- 현재 앱이 사용하는 주소를 유지한다. 자동 할당 공인 IP에 새 Elastic IP를 붙이면 주소가 바뀐다. 기존 IP를 EIP로 전환하는 작업으로 취급하지 않는다.
- 11월 19일까지 인스턴스를 의도적으로 중지하지 않는 것을 기본으로 한다. 이 조건도 AWS 장애까지 막는 보장은 아니다. 주소 변경은 새 AAB와 옛 앱 영향을 함께 검토하는 별도 결정이다.
- versionCode 3의 설치 기기나 APK를 업데이트 전에 보존한다. 새 BE는 옛 앱과 새 앱으로 각각 확인한다.
- 1차 배포 후보는 검증한 develop SHA와 팀이 병합한 #188~#190이다. 처리 중 작업을 끊지 않는 배포 조건을 먼저 확인한다. 2차 배포는 추가 수정분을 별도로 검사한 SHA로 구분한다.
- API, card-worker, speech-worker를 모두 같은 검증 이미지로 맞춘다. DB migration은 해당 SHA의 Alembic head와 대조한다. 열린 PR의 head를 운영에 바로 올리지 않는다.

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

## 백업과 격리 복원 검사

`scripts/verify_database_backup.py`는 PostgreSQL 17 컨테이너에서 `pg_dump`를 실행한다.
새 복원용 컨테이너는 `--network none`과 tmpfs를 사용하며 외부 포트를 열지 않는다.
운영 DB를 덮어쓰거나 기존 DB에 `--clean`을 실행하지 않는다.

필수 인수는 `--source-container`, `--source-database`, `--source-user`, `--backup-dir`다.
비밀번호를 인수로 받지 않는다. DB 컨테이너 안에서 허용된 로컬 인증을 사용하며,
인증이 거절되면 인증을 해제하지 말고 실패로 남긴다. 운영 실행은 별도 승인이 필요하다.

- 새 파일만 만든다. 기존 백업을 덮어쓰지 않는다.
- 복원용 DB는 컨테이너 내부 TCP 응답까지 기다린다. 초기화용 임시 Unix 소켓 서버를 준비 완료로 보지 않는다. 실패 기록에는 원문 오류 대신 중단 단계와 안전한 오류 코드를 남긴다.
- 백업의 SHA-256, 크기, 복원 성공 여부, 복원된 migration과 주요 테이블 건수를 기록한다.
- 이 실행에서 만든 라벨이 일치하는 복원용 컨테이너만 정리한다. 백업 파일은 실패해도 보존한다.
- 백업에는 개인정보가 들어갈 수 있다. 공개 GitHub에 넣지 않으며 암호화된 보관 위치와 접근 권한을 별도로 확인한다. Linux 파일은 0600으로 생성하지만 Windows에서는 디렉터리 ACL과 디스크 암호화를 따로 확인한다.

### 매일 실행과 오래된 백업 정리

`scripts/prune_database_backups.py`는 같은 폴더의 백업과 기록을 읽어 오래된 것만 지운다. 기록에 `restoreVerified: true`가 있는 최근 백업 `--keep`개(기본 7)는 날짜와 상관없이 남기고, 그 밖의 백업 중 `--older-than-days`일(기본 7)보다 오래된 것만 지운다. 기본은 지울 목록만 출력하며 `--apply`를 줘야 지운다.

```bash
# 운영 서버 예시(승인 뒤 설치). 백업 폴더는 root만 접근하고 디스크 암호화가 된 위치를 쓴다.
python3 scripts/verify_database_backup.py --source-container saerok-db-1 --source-database saerok   --source-user saerok --backup-dir /var/backups/saerok
python3 scripts/prune_database_backups.py --backup-dir /var/backups/saerok --keep 7 --older-than-days 7 --apply
```

- 하루 한 번 systemd timer나 cron으로 위 두 명령을 차례로 실행한다. 백업 검사가 실패하면 정리는 하지 않는다.
- 보관 기한과 마지막 삭제 시점(AWS 종료 전 전부 삭제)은 `docs/legal/README.md`의 백업 항목을 따른다.

로컬 확인(2026-11-04): 로컬 Docker의 PostgreSQL 17에 최신 migration(`d73f0b5ca921`)과 합성 프로필 3건을 넣고 `verify_database_backup.py`를 실행했다. 4초 걸렸고 `restoreVerified: true`, 복원된 revision `d73f0b5ca921`, 사용자와 프로필과 이야기 각 3건이 원본과 같았으며 복원용 컨테이너는 지워졌다. 운영 DB에서 실행한 기록은 아니다.
- SQL 복원 성공은 서비스 복구 완료와 다르다. 앱 연결, 이미지와 migration 호환성, 외부 S3 파일까지 복원됐다는 뜻도 아니다.

로컬 검증은 합성 DB에서만 한다. `tests/test_backup_restore_tool.py`의 Docker 복원 시험은
`SAELOG_BACKUP_TEST_CONTAINER`를 명시했을 때만 실행한다. 운영 컨테이너를 테스트 fixture에
연결하지 않는다. 일반 CI에서는 Docker 복원 시험이 생략되므로 별도 결과를 첨부한다.

## 승인 후 적용 순서

1. 적용 시간, 승인자, 배포 SHA, 이전 이미지 ID, DB revision과 백업 복원 결과를 확인한다.
2. 새 작업 접수와 진행 중 작업을 확인한다. worker만 꺼도 API 접수는 계속될 수 있다. 사용자 요청을 어떻게 차단할지 정하지 못했거나 진행 중 작업을 안전하게 끝내지 못하면 배포하지 않는다.
3. 깨끗한 체크아웃에서 `SOURCE_REVISION` build arg에 전체 SHA를 넣어 이미지를 빌드한다. 해당 이미지에 SHA별 태그를 붙이고 이전 이미지도 보존한다.
4. 승인한 유지보수 상태에서 migration을 적용한다. `init.sql`, DB 재생성, `compose down -v`를 쓰지 않는다.
5. 명시한 compose 조합으로 API와 두 worker를 교체한다. 기존 override의 임시 image 값이 마지막에 덮어쓰지 않는지 확인한다.
6. 실제 image ID와 revision을 다시 기록하고 준비 상태, 로그인과 카드 생성, 녹음부터 리포트, 이야기 확인 후 다음 카드까지 검사한다.
7. 옛 앱과 새 앱을 모두 확인한 후 새 AAB를 올린다. 공개 배포 승인 전까지는 승인된 비공개 테스트 설치 경로를 안내한다.

## 이상이 생겼을 때

- 이미지 문제이며 DB 하위 호환이 확인되면 이전에 기록한 이미지로 API와 worker를 함께 되돌린다. 이전 태그가 같은 내용을 가리킨다고 추측하지 말고 image ID를 대조한다.
- migration 뒤에는 예전 이미지가 새 DB를 읽을 수 있는지 먼저 확인한다. 검증하지 않은 `alembic downgrade`나 운영 DB 복원은 자동 실행하지 않는다.
- DB 복원이 필요하면 백업 이후 생성된 데이터의 보존 여부와 손실 범위, 접수 차단, 복원 대상과 승인자를 먼저 정한다. 복원 시험이 성공했다는 이유로 운영 DB를 덮어쓰지 않는다.
- 11월 10일 이후에는 새 기능을 동결하고 승인된 장애 또는 보안 수정만 재검증한다. AWS 지원 종료인 11월 20일 전에 필요한 자료와 설정을 권한이 있는 보관 위치에 확보한다.

이 변경은 수동 배포의 검증과 기록을 보완한다. 자동 운영 배포, IAM 변경과 Play 업로드는
실행하지 않는다. CI에서 검증한 버전과 실제 배포 버전의 일치 여부는 매 배포마다 확인한다.
