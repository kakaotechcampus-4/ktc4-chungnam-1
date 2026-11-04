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
`SAEROK_AI_SERVER_BACKUP_URL`로 설정한 예비 STT는 조회하지 않는다. 기본 경로가 끊겨도
예비 경로로 실제 분석이 성공할 수 있으므로 예비 경로 동작은 [STT 예비 서버 전환](stt-backup.md)과
[ck 예비 서버 SSH 운영 연결](stt-backup-ssh.md) 기준으로 따로 확인한다.

## 확인하지 않는 것

- worker 프로세스의 실제 생존과 이미지 버전: 출력의 `workerProcessState`는 항상 `not_inspected`다.
- S3 객체의 실제 존재 여부와 삭제 완료
- ML API 인증, 잔여 한도, 실제 생성과 전사 품질
- 긴 녹음과 두 번째 회차까지의 앱 성공

worker와 이미지 확인은 별도 컨테이너 점검과 함께 한다. 대기 작업이 없다는 이유로
worker가 정상이라고 결론 내리지 않는다. API, card-worker와 speech-worker 모두의
이미지 ID, 재시작 수, 실제 실행 명령과 migration을 배포 기록에 남긴다.
환경 변수 전체 출력, 원문 로그 복사와 `docker inspect` 전체 결과 공유는 피한다.

이 점검 도구의 경고가 바로 자동 삭제나 재시작을 허용하지 않는다. 운영 변경과
실제 자료 삭제는 대상과 복구 방법을 확인한 후 별도 승인받는다.
