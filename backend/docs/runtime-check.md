# 운영 상태 읽기 전용 점검

`/health/live`는 API 프로세스가 응답하는지만 확인한다. `/health/ready`는 DB 연결과
`SELECT 1`까지 3초 안에 실행해야 `ready`를 반환한다. 설정 누락과 연결 실패는 503이며
DB 주소나 오류 원문을 공개하지 않는다. DB 구조 일치, GPU, 모델 한도와 worker 동작을
이 응답 하나로 확인했다고 보고하지 않는다.

## 내부 점검 명령

`backend/`에서 서버 환경 변수를 읽어 실행한다. 별도 HTTP 공개 API는 만들지 않는다.

```bash
uv run python -m app.ops.runtime_check
uv run python -m app.ops.runtime_check --probe-stt
uv run python -m app.ops.runtime_check --check-ml-config
```

`--expected-revision`에는 해당 배포 이미지의 `alembic heads`에서 확인한 revision을
넣는다. DB의 실제 revision과 다르면 종료 코드 1과 `MIGRATION_MISMATCH`를 남긴다.
출력은 JSON이며 검사 시작 시각은 UTC다. 팀 보고에는 KST로 변환해 적는다.

점검은 읽기 전용 트랜잭션으로 다음만 조회한다.

- 실제 migration revision
- 녹음 분석, 카드 생성과 사진 분석의 상태별 건수
- 녹음 분석과 카드 생성 중 임대 시간이 지난 작업 수와 삭제 기한이 지난 녹음 수. 사진 분석 작업의 임대 만료는 세지 않는다. 녹음은 `uploading`, `transcribing`, `generatingReport`만 센다. 전사 저장 때 두는 인계 임대가 끝난 `sttCompleted` 작업(#280)도 세지 않는다. 그런 작업은 다음 worker가 리포트 생성을 이어받는다
- S3 삭제 대기 건수와 현재 DB에 있는 이야기 후보 수. 삭제 대기 건수(`deletion_queue`)는 삭제 실행기처럼 `not_before`가 지난 요청만 센다. 업로드 중 사전 등록처럼 기한 전인 요청은 세지 않는다(#283).

전사문, 이름, 계정 식별자, 사진 설명과 S3 객체 키는 읽거나 출력하지 않는다.
대기열을 정리하거나 작업을 실패로 바꾸는 서비스 함수도 호출하지 않는다.
`story_candidates_present=0`은 현재 남아 있는 후보가 없다는 뜻이며,
과거에도 후보를 만든 적이 없다는 증거는 아니다.

`--probe-stt`는 현재 설정의 기본 STT 주소에 `GET /health/live`만 보낸다.
HTTP 200과 `status=ok`를 확인하며 녹음을 제출하거나 모델을 실행하지 않는다.
`SAEROK_AI_SERVER_BACKUP_URL`도 설정돼 있으면 예비 주소의 같은 경로를 별도로 조회한다.
기본 결과는 `sttLiveness`, 예비 결과는 `backupSttLiveness`다. 주소와 인증값은 출력하지 않는다.
userinfo, query, fragment가 들어간 주소는 호출하지 않는다. 이 조회는 예비 전환을 실행하지 않는다.
실제 전환 동작은 [STT 예비 서버 전환](stt-backup.md)과 [ck 예비 서버 SSH 운영 연결](stt-backup-ssh.md)
기준으로 따로 확인한다. 이 조회가 성공했다고 worker의 전환 성공까지 확인한 것은 아니다.

## worker와 STT를 구분해서 보기

`--worker-container speech=컨테이너이름`, `--worker-container card=컨테이너이름`을 추가한다.
사진 분석 worker(`photo-worker`, 11/8 배포부터 운영에서 실행)도 볼 때는 `photo=컨테이너이름`을 지정한다. 이름은 실제 컨테이너 목록에서
확인하고 한 역할을 중복 지정하지 않는다. Docker CLI가 있고 선택된 Docker 연결 대상에 대한
읽기 권한이 있는 환경에서 실행한다. 검사 때문에 API 컨테이너에 Docker 소켓을 새로 연결하지 않는다.

- `workers.speech/card/photo.state`: running, restarting, exited 등 해당 컨테이너의 상태.
- `restartCount`: 누적 재시작 횟수. 많다는 이유만으로 지금도 재시작 중이라고 단정하지 않고 두 시점의 증가 여부를 비교한다.
- `inspection_failed`: Docker가 없거나 접근이 거절됐거나 지정한 컨테이너를 조회하지 못함. worker 장애 확정과 구분한다.
- `workerProcessState`: 선택한 worker들만의 요약. 지정하지 않았으면 `not_inspected`다.
- `processingVerified: false`: 프로세스가 실행 중이어도 작업 소비, 모델 호출과 DB 저장 성공은 아직 검증하지 않았다는 뜻이다.
- `sttAnalysisVerified: false`: `/health/live`의 200은 STT HTTP 응답 확인이다. GPU 메모리, 모델 로딩, 화자 분리나 긴 녹음 처리 성공을 보장하지 않는다.

예비 STT가 응답해도 기본 STT 장애와 worker 정지는 각각 경고한다. 상태 조회만으로 새 녹음을 보내거나
컨테이너를 다시 띄우지 않는다. `status: ok`는 `scope: selected_checks_only`에 해당하며 전체 서비스의
정상 판정이 아니다. worker를 지정하지 않고 DB만 검사한 결과도 이 범위를 넘겨 해석하지 않는다.

## ML API 키와 잔여 한도 확인

`--check-ml-config`는 `SAEROK_ML_API_KEY`에 공백 이외의 값이 있는지만 확인한다.
키 원문, 일부 글자, 길이나 해시는 출력하지 않는다. 결과의 `keyConfigured`와 별개로
`authentication`, `remainingQuota`는 `not_checked`, `generationVerified`는 `false`다.
키가 없으면 `ML_API_KEY_NOT_CONFIGURED` 경고를 낸다.

저장소에는 공급자의 읽기 전용 키 유효성 또는 잔여 사용량 API 계약이 없다. 임의의 `/usage`나
`/models`를 호출하거나 오류 응답만 보고 잔여 한도를 추정하지 않는다. 다음은 승인된 운영 점검 때
기존 로그인 세션으로 확인할 항목이다. 이번 로컬 작업에서 콘솔이나 실제 키를 검사한 것은 아니다.

1. 카테캠 ML API 콘솔에서 팀이 사용하는 프로젝트와 해당 모델을 연다. 다른 개인 계정의 한도를 팀 한도로 기록하지 않는다.
2. 키 관리 화면에서 사용 중인 키의 활성 여부와 만료 정보가 제공되는지 확인한다. 새 키 발급, 기존 키 공개와 폐기는 하지 않는다. 화면에서 현재 키를 특정할 수 없으면 미확인으로 남긴다.
3. 사용량 또는 잔여 한도 화면에서 남은 양, 단위, 갱신 주기와 조회 시각을 확인한다. 표시가 없거나 권한이 없으면 0 또는 무제한이라고 쓰지 않는다.
4. 기록에는 KST 확인 시각, 프로젝트와 모델, 활성/미확인, 잔여량과 단위, 갱신 기준만 남긴다. 키가 보이는 화면 캡처는 저장하지 않는다.
5. 콘솔에서 활성으로 보여도 실제 생성 성공은 별도다. 필요하면 비용과 입력 자료에 대한 승인 후 합성 입력으로 최소 생성 검사를 수행하고 읽기 전용 점검과 따로 기록한다.

## 확인하지 않는 것

- worker의 실제 작업 완료와 이미지 버전: 프로세스 상태 조회와 다르다. 이미지 대조는 별도 배포 기록으로 한다.
- S3 객체의 실제 존재 여부와 삭제 완료
- ML API 인증, 잔여 한도, 실제 생성과 전사 품질
- 긴 녹음과 두 번째 회차까지의 앱 성공

worker와 이미지 확인은 위 선택 점검과 별도 배포 기록을 함께 사용한다. 대기 작업이 없다는 이유로
worker가 정상이라고 결론 내리지 않는다. API, card-worker, speech-worker와 photo-worker 모두의
이미지 ID, 재시작 수, 실제 실행 명령과 migration을 배포 기록에 남긴다.
환경 변수 전체 출력, 원문 로그 복사와 `docker inspect` 전체 결과 공유는 피한다.

이 점검 도구의 경고가 바로 자동 삭제나 재시작을 허용하지 않는다. 운영 변경과
실제 자료 삭제는 대상과 복구 방법을 확인한 후 별도 승인받는다.

## 주기 실행과 알림

`app.ops.runtime_alert`는 점검 결과를 읽어 문제 목록이 바뀌었을 때만 Discord 웹훅으로 알린다. 같은 문제가 이어지면 다시 보내지 않고, 문제가 모두 사라지면 해소 알림을 한 번 보낸다. 보내는 내용은 문제 코드, 시각, 서버 이름뿐이며 점검 결과의 다른 값, DB 건수와 주소는 보내지 않는다.

```bash
# 컨테이너 밖 호스트에서 5분마다 실행하는 예. 웹훅 주소는 root만 읽는 파일에 둔다.
# /etc/saerok-runtime-alert.env: SAEROK_ALERT_WEBHOOK_URL=..., SAEROK_ALERT_HOST_LABEL=ec2-prod
set -a; . /etc/saerok-runtime-alert.env; set +a
docker compose -f compose.yml exec -T api python -m app.ops.runtime_check --probe-stt \
  | docker compose -f compose.yml exec -T -e SAEROK_ALERT_WEBHOOK_URL -e SAEROK_ALERT_HOST_LABEL api \
      python -m app.ops.runtime_alert --state /tmp/saerok-runtime-alert.json --ignore DELETION_QUEUE,OVERDUE_AUDIO
```

- worker 상태까지 보려면 Docker 읽기 권한이 있는 호스트 쪽에서 `--worker-container`를 붙여 실행한다. API 컨테이너에 Docker 소켓을 연결하지 않는다.
- `--ignore`에는 이미 알고 있고 처리 일정이 정해진 코드만 넣는다. 11/11 갱신: #341로 삭제 대기열을 5분마다 처리하게 되어 11/11 14:45 KST 대기열은 0건이었다. 아래는 그전 기록이다. 삭제 대기열 실행기(#204) 코드는 11/5 배포부터 운영 이미지에 있었지만, 실제 삭제를 보류해(11/6 PM 결정, 운영 배포 기록) 두 코드가 계속 남았다. 11/8 배포와 11/9 배포(Deploy run 42568179490)의 사후 점검에도 `DELETION_QUEUE`, `OVERDUE_AUDIO`가 남았다. 11/9 배포부터는 `DELETION_QUEUE`가 `not_before`가 지난 요청만 센 결과다. 대기열과 기한 지난 원본을 실제로 정리한 뒤에 두 코드를 뺀다.
- 종료 코드는 0(보낼 일 없음 또는 전송 성공), 1(전송 실패, 다음 실행에서 다시 보냄), 2(웹훅 미설정 또는 https가 아닌 주소)다.
- 상태 파일이 컨테이너 안 `/tmp`에 있으면 컨테이너를 다시 만들 때 사라져 첫 실행처럼 동작한다. 그때 문제가 있으면 한 번 다시 알린다.
- 운영 서버에 타이머를 설치하고 웹훅 주소를 넣는 일은 PM 승인 뒤 서버 담당이 한다. 처음 이 문서를 쓸 때는 설치하지 않았고, 이후 설치 상태는 아래에 둔다.

### 운영 설치 상태

현재 구현 (2026-11-09 기준, 운영 배포 기록): 11/7 16:29 KST에 PM 승인으로 운영 서버에 설치했다. 호스트 스크립트와 timer 원본은 저장소에 없고, 아래는 운영 배포 기록에 적힌 내용이다.

- systemd timer가 5분마다(부팅 3분 뒤 시작) 호스트 스크립트를 실행한다. 웹훅 주소는 root만 읽는 환경 파일에 두고 어디에도 출력하지 않았다.
- 스크립트는 API 컨테이너 안에서 `runtime_check --probe-stt`를 실행하고, 실행하지 못하면 `RUNTIME_CHECK_FAILED`로 알린다. card-worker와 speech-worker는 호스트에서 실행 여부를 직접 보고 꺼져 있으면 `*_DOWN`을 더한다. 전송은 같은 이미지로 잠깐 띄운 컨테이너의 `runtime_alert`가 하므로 API가 죽어도 보낸다.
- 상태 파일은 컨테이너 밖 `/var/lib/saerok/` 아래에 두어 컨테이너를 다시 만들어도 남는다. 위 예시의 `/tmp` 문제는 운영 설치에는 해당하지 않는다.
- 흔들림을 줄이려고 11/7 16:37에 보완했다. 문제마다 두 번 연속(약 10분) 보여야 알리고, 두 번 연속 사라져야 해소로 본다. 직전 관찰은 별도 파일에 둔다. 이 연속 판정은 호스트 스크립트에 있고 `app.ops.runtime_alert` 모듈은 바뀔 때마다 보내는 위 동작 그대로다.
- 알리지 않는 코드는 `DELETION_QUEUE`, `OVERDUE_AUDIO`다.
- 남은 점: 기록상 호스트 스크립트는 photo-worker 실행 여부를 보지 않는다(설치는 photo-worker가 생기기 전인 11/7이고, 이후 추가 기록이 없다). EC2 자체가 꺼지는 것은 이 방식으로 알 수 없다.
