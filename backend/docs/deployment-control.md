# 배포 중 분석 접수와 새 작업 시작 중지

이 기능은 로컬 구현이다. 운영 변경 승인을 받은 뒤 검증한 이미지와 migration을 함께 적용한다.
DB revision은 `f95c2d7eb143`, 부모는 `e84b1c6da032`다. 기본값은 접수 허용, worker 임대 허용이다.
설정은 DB에 남으므로 API나 worker를 재시작해도 중지 상태가 풀리지 않는다.

## 제어하는 범위

- 새 녹음 분석 접수, 남은 전사를 이용한 리포트 재처리, 프로필 세부 정보의 짧은 녹음 전사, 카드 생성 요청을 멈춘다.
- 카드, 음성, 합성 사진 분석 worker가 새 작업을 가져가지 못하게 한다. 이미 시작한 처리에는 중단 신호를 보내지 않는다.
- 공개 관리 API는 추가하지 않는다. DB 접속 권한이 있는 운영자만 내부 CLI를 실행한다.
- 조회, 소감 저장, 사진 업로드와 다른 수정 API까지 막는 기능은 아니다. DB 변경이나 백업을 위해 모든 쓰기를 멈춰야 한다면 API 트래픽 차단과 다른 실행 도구 중지도 별도로 필요하다.
- 저장소를 직접 호출하는 개발용 코드와 구버전 worker는 이 제어를 우회한다. 운영 API와 모든 분석 worker가 이 버전을 사용하는지 확인해야 한다.

## 앱에서 달라지는 응답

인증과 해당 자료의 접근 권한은 기존대로 확인한다. 접수 중지 중 유효한 요청에는 아래 응답을 준다.
기존 요청과 성공 응답 형식은 바뀌지 않는다. 조회 API는 계속 사용할 수 있다.

```json
{
  "schemaVersion": 1,
  "errorCode": "SERVICE_MAINTENANCE",
  "message": "서비스 점검 중입니다. 잠시 후 다시 시도해 주세요.",
  "requestId": "req_01",
  "retryable": true
}
```

HTTP 상태는 `503`이다. `POST /api/v1/visit-sessions/{sessionId}/speech-analyses`,
`POST /api/v1/speech-analyses/{analysisId}/retry`, `POST /api/v1/speech-transcriptions`,
`POST /api/v1/profiles/{profileId}/card-generations`에 적용한다.
짧은 전사는 S3 업로드와 STT 호출 전에 거절한다. 녹음 분석도 새 작업을 저장하기 전에 거절한다.
클라이언트는 파일과 입력을 보존하고 점검 후 사용자가 다시 요청할 수 있어야 한다.
앱의 실제 안내와 파일 보존 검사는 FE E2E 담당자에게 인계한다. 이 문서만으로 앱 적용 완료를 뜻하지 않는다.

## 상태 조회

아래 명령은 환경의 DB 설정을 사용한다. 연결 문자열이나 비밀번호를 명령행에 붙이지 않는다.

```sh
python -m app.ops.deployment_control status
```

기본 실행도 `status`이며 읽기 전용이다. 반환값은 다음과 같다.

- `admissionsPaused`: 새 분석 접수 중지 여부.
- `workerClaimsPaused`: worker가 새 작업을 가져오는 동작의 중지 여부.
- `counts.active_speech`: 업로드 또는 STT, 리포트 처리 상태인 작업 수.
- `counts.active_cards`, `active_photos`: 임대된 카드, 처리 중 사진 수.
- `counts.queued_speech`, `queued_cards`, `queued_photos`: 대기 중 작업 수. 완료 건수로 읽지 않는다.
- `counts.worker_executions`: 이 버전 worker가 실제 처리 구간에 있는 DB 연결 수.
- `counts.short_speech_executions`: 짧은 녹음 전사를 처리 중인 연결 수.
- `analysisDrained`: 두 중지 설정이 켜졌고 진행 상태 및 실행 연결 수가 모두 0인지 여부.

실행 연결은 PostgreSQL 세션 잠금으로 센다. STT 저장과 리포트 시작 사이에도 유지하며,
정상 완료, 오류, 취소와 DB 연결 종료 때 해제한다. 사용자 정보나 전사 내용을 기록하지 않는다.
프로세스가 죽은 뒤 남은 임대 상태가 있으면 진행 건수가 남아 있으므로 즉시 완료로 판단하지 않는다.
이 값은 모든 DB 쓰기가 멈췄다는 뜻도, S3 삭제가 끝났다는 뜻도 아니다.

## 승인 후 사용하는 순서

1. 배포 SHA, 이미지, migration, 승인 시간과 되돌릴 버전을 기록한다. 최초 도입 때 구버전 worker는 이 기능이 없으므로, 별도 트래픽 제한과 진행 중 작업 확인 후 이 migration과 코드를 적용한다.
2. `pause-admissions --confirm-change`로 새 접수를 먼저 멈춘다. worker는 기존 대기 작업을 계속 처리한다.
3. 상태를 반복 조회해 진행 작업과 대기 작업을 확인한다. 업로드가 끝나기 전에 worker를 끄지 않는다. 대기 중 카드의 시작 제한 시간과 녹음 보관 기한은 이 기능으로 늘어나지 않는다.
4. 작업이 정리되면 `pause-workers --confirm-change`를 실행한다. 두 상태를 한번에 멈춰야 하는 승인된 상황에만 `pause-all --confirm-change`를 쓴다. 이미 처리 중인 작업은 그대로 끝난다.
5. `analysisDrained=true`와 대기 건수를 확인한다. 남은 대기를 의도적으로 보존하고 배포할 경우 그 건수를 기록한다. 이 상태에서 해당 worker를 정상 종료한다. 임대 만료 정리와 삭제 도구도 DB를 쓰므로 함께 확인한다.
6. 전체 쓰기가 멈춰야 하는 migration이면 API 접근도 별도로 제한한다. 백업과 격리 복원 검사 뒤 승인된 migration과 이미지를 적용한다. `init.sql`은 실행하지 않는다.
7. 새 이미지와 DB revision을 확인하고 `resume-workers --confirm-change`로 worker만 먼저 연다. 접수는 계속 중지 상태다. 기존 대기 작업, STT와 ML 설정을 확인한다.
8. `resume-all --confirm-change`로 접수를 연 뒤 옛 앱과 새 앱을 검사한다. 실패했으면 유지보수 상태를 유지하고 별도 승인 없이 downgrade나 DB 복원을 하지 않는다.

각 명령의 전체 형식은 `python -m app.ops.deployment_control <동작> --confirm-change`다.
변경 확인 옵션 없이 상태를 바꾸려 하면 실패한다. 접수를 열어 둔 채 worker만 멈추려 해도 실패한다.
요청 접수와 설정 변경이 겹치면 DB 잠금으로 순서를 맞춘다. 3초 안에 잠금을 얻지 못하면 변경 명령이 실패하므로 상태를 다시 확인한다.
오류 출력에는 DB 주소와 비밀번호를 넣지 않는다. 설정 행이 없거나 DB에 접근하지 못해도 임의로 허용 상태로 되돌리지 않는다.

## 로컬 검사

`tests/test_deployment_control.py`는 격리 PostgreSQL에서 기본 허용, 접수 차단, 짧은 전사의 외부 호출 방지,
동시 접수와 중지 순서, 진행 중 worker 보존, 새 임대 중지, 오류와 취소 뒤 실행 집계 해제를 검사한다.
실제 운영 접수 중지나 GPU 처리 시험은 아니다.
