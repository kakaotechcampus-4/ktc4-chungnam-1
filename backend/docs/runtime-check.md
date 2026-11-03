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
- 임대 시간이 지난 처리 작업 수와 삭제 기한이 지난 녹음 수
- S3 삭제 대기 건수와 현재 DB에 있는 이야기 후보 수

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
합성 사진 worker를 따로 운영할 때만 `photo=컨테이너이름`도 지정한다. 이름은 실제 컨테이너 목록에서
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
worker가 정상이라고 결론 내리지 않는다. API, card-worker와 speech-worker 모두의
이미지 ID, 재시작 수, 실제 실행 명령과 migration을 배포 기록에 남긴다.
환경 변수 전체 출력, 원문 로그 복사와 `docker inspect` 전체 결과 공유는 피한다.

이 점검 도구의 경고가 바로 자동 삭제나 재시작을 허용하지 않는다. 운영 변경과
실제 자료 삭제는 대상과 복구 방법을 확인한 후 별도 승인받는다.
