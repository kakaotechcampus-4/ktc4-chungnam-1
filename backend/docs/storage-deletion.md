# S3 삭제 대기열 실행

기존 `storage_deletion_request_queue`에 쌓인 삭제 요청을 처리하는 도구다. 기본 실행은
DB 조회만 하며 S3에 접근하지 않는다. 운영 적용과 실제 자료 삭제는 별도 승인이 필요하다.

## 범위

- 사진 또는 녹음 행 삭제로 이미 만들어진 요청을 처리한다. 업로드 전에 미리 넣은 요청(짧은 음성 전사, 사진 업로드)도 같은 대기열에 있다.
- `not_before`가 지나지 않은 요청은 건너뛴다. 사진 업로드의 사전 등록은 1시간 뒤로 넣고 사진 행을 저장하는 트랜잭션에서 지운다. 남아 있다면 업로드 뒤 행을 넣지 못한 객체이며, 기한이 지난 뒤 행이 없는 객체로 확인하고 지운다.
- 실제 삭제 성공을 확인한 경우만 대기열에서 지운다. 남아 있는 녹음 작업에는 `audio_deleted_at`을 기록한다.
- 원래 `requested_at`은 유지한다. 시도 횟수, 마지막 시각과 안전한 오류 코드만 추가 기록한다.
- 한 번에 기본 100건을 확인한다. 아직 시도하지 않은 요청과 오래전에 시도한 요청부터 처리해 실패한 첫 요청이 뒤의 요청을 계속 막지 않도록 한다.
- 동일 DB의 실행기끼리는 세션 잠금을 사용한다. S3 호출 중 DB 트랜잭션이나 행 잠금을 유지하지 않는다.

분석 자체를 재시도하거나 전사문, 리포트, 휴대폰 원본을 삭제하는 도구가 아니다.

## 실행 전 확인

1. 백업과 migration을 확인한다. 추가 revision은 `a49d71b28c36`이고 이전 revision은 `e5a1c7d93b42`다. `init.sql`을 운영 DB에 실행하지 않는다.
2. 녹음과 사진의 버킷, 리전, 접두사는 기존 `SAEROK_SPEECH_AUDIO_S3_*`, `SAEROK_IMAGE_S3_*` 설정을 사용한다. 큐에는 버킷 이름이 없으므로 과거 요청의 버킷이 현재 설정과 같음을 확인해야 한다.
3. 접두사가 비어 있거나 서로 겹치면 실행을 거절한다. 키가 접두사 아래의 UUID 형식 WAV 또는 JPG/PNG가 아니면 삭제하지 않는다. 과거 파일을 추측해 다른 버킷으로 보내지 않는다.
4. 운영 권한에는 해당 버킷의 `GetBucketVersioning`, 해당 접두사의 `DeleteObject`, `GetObject`, 없는 객체를 404로 확인하기 위한 제한된 `ListBucket` 권한이 필요하다. 여기서 IAM을 변경하지 않는다.
5. 버전 관리가 `Enabled` 또는 `Suspended`이면 삭제하지 않는다. 과거 버전까지 지우는 방식은 별도 검토한다. 삭제 표시만 생긴 상태를 실제 삭제로 처리하지 않기 위해서다.

## 기본 확인 명령

backend 디렉터리에서 실행한다. `.env`에는 실제 운영 설정을 적지 말고 실행 환경의 기존 설정을 사용한다.

```sh
uv run python -m app.workers.storage_deletion --limit 100
```

DB 확인만 하며 `mode=dry_run`, 검사 건수, 처리 가능한 건수와 보류 사유별 건수를 출력한다.
버킷 권한과 실제 S3 객체 존재 여부까지 확인한 결과는 아니다. 객체 키, URL과 원문은 출력하지 않는다.

승인된 환경에서 실제 삭제를 할 때만 다음 옵션을 붙인다. 이 문서 작성 중 운영에는 실행하지 않았다.

```sh
uv run python -m app.workers.storage_deletion --apply --limit 100
```

업데이트한 API 이미지와 migration을 사용하는 서버라면 같은 명령을 컨테이너 안에서 실행할 수 있다.

```sh
docker compose exec -T api python -m app.workers.storage_deletion --limit 100
```

## 삭제하지 않고 남기는 경우

| 코드 | 의미 | 대응 |
| --- | --- | --- |
| `UNKNOWN_OBJECT_ROUTE` | 현재 설정과 파일 형식으로 버킷을 식별할 수 없음 | 과거 설정과 원래 요청을 확인. 임의로 경로를 고치거나 삭제하지 않음 |
| `LIVE_REFERENCE` | 사진 행이 남아 있거나 녹음 업로드, 대기, 전사 처리 중 | 잘못 등록된 요청인지 확인. 이 도구가 살아 있는 사진 행을 대신 삭제하지 않음 |
| `VERSIONED_BUCKET_REQUIRES_REVIEW` | 버킷에 버전 관리 이력이 있음 | 모든 버전 삭제 정책과 권한을 별도 확인 |
| `STORAGE_UNAVAILABLE` | S3 요청 또는 삭제 후 확인이 실패 | 권한과 연결 확인 후 다음 실행에서 재시도 |
| `DELETE_NOT_CONFIRMED` | 삭제 요청 뒤에도 객체가 조회됨 | 요청을 유지하고 다음 실행에서 재확인 |

`HeadObject` 403은 삭제 성공이 아니다. 404를 확인한 경우만 완료 처리한다.
오류나 다른 실행기의 잠금이 있으면 종료 코드 1을 반환한다. DB에 기록할 수 없는 오류도
성공으로 넘기지 않는다. DB 연결이 끊기거나 프로세스가 종료되면 세션 잠금은 해제된다.

## 후속 운영 작업

- 자동 주기 실행은 설치하지 않았다. 운영자가 실행 간격과 감시를 정한 뒤 스케줄러에 연결해야 한다.
- 기한이 지난 녹음을 찾아 삭제 요청을 만드는 작업은 [점검 도구](storage-audit.md)의 `--enqueue-safe-expired`가 맡는다. 진행 중 원본은 넣지 않으므로 이 실행기만으로 모든 24시간 상한 준수를 보장하지 않는다.
- S3와 DB의 객체 수가 다르다는 이유만으로 남는 파일을 삭제하지 않는다. DB에 없는 과거 테스트 파일은 별도 조회와 승인 대상이다.
- Lifecycle은 보조 삭제 규칙이며 이 도구가 버킷 규칙을 만들거나 변경하지 않는다.

## 검증과 근거

합성 PostgreSQL에서 읽기 모드 무변경, 성공 기록, 실패 유지와 재시도 순서, 동시 실행,
살아 있는 사진 및 처리 중 녹음 보호, migration 이전 요청 보존을 검사한다. S3는 대역으로
검사하며 실제 운영 S3 삭제 시험은 아니다.

`uv run pytest tests/test_storage_deletion.py tests/test_migrations.py`

[AWS HeadObject 권한과 403/404](https://docs.aws.amazon.com/boto3/latest/reference/services/s3/client/head_object.html),
[AWS 버전별 만료 동작](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html).
