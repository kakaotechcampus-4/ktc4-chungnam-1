# 기본 GPU와 ck 예비 STT 운영 절차

2026-11-03 로컬 절차안. 실제 서버에 접속하거나 설정을 바꾸지 않았다.
기준은 통합본 `48af8c7`과 기존 PR #189의 로컬 브랜치 `feature/backend-stt-backup-20261103`,
PR #190의 `feature/stt-ssh-backup-runtime-20261103`에 있는 코드와 운영 문서다.
이 통합본에는 두 PR의 예비 전환 코드와 운영 파일이 아직 없다. 이 문서가 병합을 대신하지 않는다.
팀 PR이 들어오면 실제 파일, 환경변수와 실행 방법을 다시 대조한다.

## 세 경로를 구분한다

| 경로 | 용도 | 확인과 변경 경계 |
| --- | --- | --- |
| 이문영님의 개인 GPU와 Tailscale | 기본 STT | `SAEROK_AI_SERVER_URL`이 가리키는 주소. PC 전원, Tailscale 연결과 STT 앱을 각각 확인 |
| `saerok-stt-backup.service`와 ck | 기본 서버 연결 실패 시 쓰는 예비 경로 | BE 호스트의 제한된 SSH 연결. worker가 접근 가능한 Docker bridge 사설 주소를 사용. ck에서는 Supervisor의 `saerok-ck-stt`만 관리 |
| 기존 compose의 `stt-tunnel` | 과거 기본 GPU SSH 경로 | 위 예비 서비스와 다르다. card-worker 등 남은 참조를 확인하고 대체 경로 검증을 마친 뒤 승인받아 정리 |

컨테이너 내부 `127.0.0.1`은 그 컨테이너 자체다. 호스트에서 상태 확인이 됐다는 이유로
speech-worker에서도 연결된다고 판단하지 않는다. 주소, 키 경로와 S3 서명 URL은 보고서에 복사하지 않는다.
학교 공유 서버나 GPU 호스트 전체를 재부팅하거나 다른 사용자의 프로세스를 종료하지 않는다.

## 정상 상태를 확인하는 순서

1. 검증 이미지 SHA와 실제 실행 이미지, migration을 [배포 기록](release-safety.md)으로 확인한다. `compose.override.yml`의 링크와 임시 image 고정을 함께 확인한다.
2. `runtime_check`에 실제 speech, card 컨테이너를 지정해 worker가 running인지 확인한다. 누적 재시작 수는 두 시점의 증감을 비교한다. 실행 중이라는 사실만으로 분석 성공을 보고하지 않는다.
3. 실제 worker와 같은 네트워크에서 `--probe-stt`로 기본 및 예비 `/health/live`를 각각 확인한다. HTTP 200과 `status=ok`를 요구한다. 예비 주소는 외부에 공개하지 않는다.
4. `python -m app.ops.deployment_control status`로 접수 차단, 새 임대 중지와 진행 건수를 확인한다. 중지 상태를 장애로 오해해 임의로 해제하지 않는다.
5. 최종 확인은 별도 승인된 합성 녹음으로 STT, 전사 저장, 리포트와 다음 회차까지 실행한다. `/health/live`만 통과한 결과와 실제 처리 결과를 나눠 기록한다.

## 기본 서버에서 예비 서버로 바뀌는 조건

#189의 동작은 기본 서버를 먼저 호출하고 **TCP 연결 실패 또는 연결 시간 초과**일 때만 ck를 한 번 호출하는 것이다.
응답 대기 시간 초과, 전송 도중 오류, HTTP 오류와 잘못된 결과에는 재전송하지 않는다.
이미 기본 서버에서 처리 중일 수 있어 두 서버에 같은 녹음을 중복으로 맡기지 않기 위해서다.
두 시도는 하나의 전체 시간 제한을 공유하며 다음 작업은 다시 기본 서버부터 시작한다.

- `SAEROK_AI_SERVER_URL`: 기본 경로.
- `SAEROK_AI_SERVER_BACKUP_URL`: 예비 경로. 빈 값이면 예비 전환을 사용하지 않는다.
- `SAEROK_AI_SERVER_FAILOVER_CONNECT_TIMEOUT_SECONDS`: #189의 연결 대기 제한, 기본 5초.
- `SAEROK_AI_SERVER_TIMEOUT_SECONDS`: 두 시도에 사용하는 전체 제한.

기본을 ck로 고정하는 것은 별도 운영 결정이다. 승인받으면 새 접수를 멈추고 진행 분석을 비운 뒤,
기본 및 예비 URL이 같은 서버를 중복 호출하지 않도록 설정을 검토하고 speech-worker를 재생성한다.
환경변수를 바꾼 뒤 단순 `restart`만으로 새 값이 반영됐다고 판단하지 않는다.
실제 적용한 compose 파일 조합과 이미지를 기록하며 DB나 다른 서비스는 함께 내리지 않는다.
이 문서는 현재 기본 경로를 ck로 바꾸도록 승인하지 않는다.

## 중단 뒤 재시작 순서

1. API 새 접수를 중지하고 현재 분석을 끝낸다. worker 새 임대도 중지한 뒤 진행 건수를 확인한다. [접수 제어 절차](deployment-control.md)를 따른다.
2. 기본 PC를 복구하는 경우 담당자가 PC 전원과 Tailscale 접속을 확인한 뒤 프로젝트 STT 프로세스를 시작한다. 다른 GPU 작업을 강제 종료하지 않는다.
3. ck를 복구하는 경우 컨테이너와 지정 GPU 사용 가능 여부를 확인한다. #190의 배포 디렉터리에 설치한 Supervisor 설정으로 `saerok-ck-stt` 상태를 조회한다. 중지돼 있으면 승인 후 해당 프로그램만 시작한다. 실패 반복 시 로그의 오류 코드와 GPU 여유를 확인하고 무한 재시작하지 않는다.
4. ck 컨테이너 자체가 재시작됐다면 Supervisor도 내려갔을 수 있다. 배포해 둔 가상 환경의 `supervisord`와 설정 경로를 확인해 기동한다. 문서만 보고 새 systemd 서비스를 만들거나 GPU 호스트를 재부팅하지 않는다.
5. ck 안의 STT `/health/live`가 응답한 뒤 BE의 `saerok-stt-backup.service`를 확인한다. 설치된 호스트에서는 `systemctl show saerok-stt-backup.service -p ActiveState -p SubState -p NRestarts`로 필요한 상태만 읽는다. 재시작이 필요하면 승인 후 이 서비스만 재시작한다.
6. worker 네트워크에서 기본과 예비 상태를 다시 확인한다. 호스트 키 불일치는 등록 정보를 대조해 해결한다. `StrictHostKeyChecking=no`로 넘기지 않는다.
7. worker만 먼저 재개하고 이전 대기 작업을 확인한다. 새 접수 재개와 합성 녹음 검증은 승인된 배포 절차대로 실행한다.

Supervisor는 `startretries=3`, SSH 연결은 `RestartSec=10s`가 #190 제안의 기준이다.
실제 설치된 설정이 같은지는 운영자가 확인한다. 설치 위치와 가상 환경 경로를 추정한 실행 명령을 복사하지 않는다.

## 증상별 확인과 대응

| 증상 | 먼저 확인 | 처리 |
| --- | --- | --- |
| 기본 health만 연결 안 됨 | 개인 PC 전원, Tailscale 온라인 여부, STT 포트, worker 네트워크 | #189 통합 및 예비 설정이 있으면 연결 실패 시에만 한 번 전환. health 실패 자체로 설정 변경 안 함 |
| 양쪽 연결 실패 | ck 프로세스, SSH 서비스, 사설 바인딩, worker 네트워크 | 새 접수를 제한하고 경로 복구. 실패한 회차가 자동으로 재실행된다고 안내하지 않음 |
| SSH는 active인데 예비 health 실패 | ck STT 시작 상태, GPU 메모리와 모델 준비, 터널 목적지 | ck의 해당 STT 프로세스와 설정만 복구. 기존 `stt-tunnel`을 임의로 되살리지 않음 |
| health는 정상인데 분석 HTTP 오류 또는 응답 시간 초과 | 안전한 오류 코드, 처리 시간, GPU 상태와 임대 기한 | 예비로 중복 전송하지 않음. 생성 단계 실패와 STT 실패를 구분하고 [재처리 기준](speech-recovery.md) 적용 |
| worker가 exited 또는 restarting | 실행 이미지, 필수 환경변수의 설정 여부, 안전한 오류 코드 | DB와 모델 설정을 확인한 뒤 해당 worker만 재생성. 원문 환경변수와 로그 전체를 게시하지 않음 |
| queued가 쌓이고 worker는 running | 접수 제어의 `workerClaimsPaused`, 모델 설정, 임대 만료 건수 | 의도한 배포 중지인지 먼저 확인. GPU 연결만 고쳐도 worker의 DB 문제는 해결되지 않음 |
| 오래된 터널 재시작 수가 계속 증가 | 어떤 서비스가 예전 주소를 사용하는지 | 새 경로로 실제 처리 검증 후 옛 참조와 컨테이너만 승인받아 제거. ck 서비스는 보존 |

## 시연 전에 정할 운영 책임

11/11 제출과 11/14 발표에 사용할 기본 및 예비 경로의 가동 시간, 담당자 연락,
ck 컨테이너 재시작 시 Supervisor 복구 담당, 실제 사용자 음성 처리 허용 조건을 확정한다.
이 문서는 해당 담당을 임의로 배정하지 않는다. ML API 키와 잔여 한도는 [읽기 전용 점검](runtime-check.md#ml-api-키와-잔여-한도-확인)을 따른다.
