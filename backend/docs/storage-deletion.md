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
5. 버전 관리가 `Enabled` 또는 `Suspended`이면 기본 실행은 삭제하지 않는다. 2026-11-11 PM 승인에 따라 사진에 한해 `--allow-versioned-photos`를 명시하면 해당 키의 모든 버전과 삭제 표시를 영구 삭제한다. 음성 버킷에는 이 옵션을 적용하지 않는다. 사진 버킷과 접두사에 한정한 `s3:ListBucketVersions`, `s3:DeleteObjectVersion` 권한을 운영 역할에 추가해야 한다. 기존 권한을 바꾸거나 다른 버킷을 허용하지 않는다.

## 기본 확인 명령

backend 디렉터리에서 실행한다. `.env`에는 실제 운영 설정을 적지 말고 실행 환경의 기존 설정을 사용한다.

```sh
uv run python -m app.workers.storage_deletion --limit 100
```

DB 확인만 하며 `mode=dry_run`, 검사 건수, 처리 가능한 건수와 보류 사유별 건수를 출력한다.
버킷 권한과 실제 S3 객체 존재 여부까지 확인한 결과는 아니다. 객체 키, URL과 원문은 출력하지 않는다.

승인된 환경에서 실제 삭제를 할 때만 다음 옵션을 붙인다.

```sh
uv run python -m app.workers.storage_deletion --apply --limit 100
```

업데이트한 API 이미지와 migration을 사용하는 서버라면 같은 명령을 컨테이너 안에서 실행할 수 있다.

```sh
docker compose exec -T api python -m app.workers.storage_deletion --limit 100
```

사진 버전까지 삭제하는 승인된 실행:

```sh
docker compose exec -T api python -m app.workers.storage_deletion --apply --allow-versioned-photos --limit 100
```

사진 키 전체를 Prefix로 조회한 뒤 키가 정확히 같은 항목만 고른다. 버전 목록은 최대 10페이지,
대상 버전과 삭제 표시는 합쳐 1,000개까지만 허용한다. 목록이 불완전하면 삭제 전에 멈춘다.
파일 버전을 먼저 삭제하고 성공 응답을 확인한 뒤 삭제 표시를 제거한다. 다시 조회해 버전과
삭제 표시가 모두 없고 HeadObject도 404일 때만 대기열에서 지운다. 부분 실패나 실행 중단은
요청을 남기며 다음 실행은 남은 버전만 처리한다. Object Lock과 MFA Delete를 우회하지 않는다.
버킷의 버전 관리, Lifecycle과 다른 키는 바꾸지 않는다. 영구 삭제한 파일은 DB 백업으로 복원할 수 없다.

## 삭제하지 않고 남기는 경우

| 코드 | 의미 | 대응 |
| --- | --- | --- |
| `UNKNOWN_OBJECT_ROUTE` | 현재 설정과 파일 형식으로 버킷을 식별할 수 없음 | 과거 설정과 원래 요청을 확인. 임의로 경로를 고치거나 삭제하지 않음 |
| `LIVE_REFERENCE` | 사진 행이 남아 있거나 녹음 업로드, 대기, 전사 처리 중 | 잘못 등록된 요청인지 확인. 이 도구가 살아 있는 사진 행을 대신 삭제하지 않음 |
| `VERSIONED_BUCKET_REQUIRES_REVIEW` | 버킷에 버전 관리 이력이 있음 | 모든 버전 삭제 정책과 권한을 별도 확인 |
| `MFA_DELETE_REQUIRES_REVIEW` | MFA Delete가 켜진 사진 버킷 | 수동 검토. MFA 설정을 해제하지 않음 |
| `VERSION_LIST_INVALID`, `VERSION_LIST_LIMIT` | 버전 목록이 불완전하거나 조회 한도 초과 | 요청 유지 후 운영자 확인 |
| `VERSION_DELETE_NOT_CONFIRMED` | 버전 삭제가 일부 실패하거나 성공 응답이 누락됨 | 요청을 유지하고 남은 버전 재시도 |
| `STORAGE_UNAVAILABLE` | S3 요청 또는 삭제 후 확인이 실패 | 권한과 연결 확인 후 다음 실행에서 재시도 |
| `DELETE_NOT_CONFIRMED` | 삭제 요청 뒤에도 객체가 조회됨 | 요청을 유지하고 다음 실행에서 재확인 |

`HeadObject` 403은 삭제 성공이 아니다. 404를 확인한 경우만 완료 처리한다.
오류나 다른 실행기의 잠금이 있으면 종료 코드 1을 반환한다. DB에 기록할 수 없는 오류도
성공으로 넘기지 않는다. DB 연결이 끊기거나 프로세스가 종료되면 세션 잠금은 해제된다.

## 정기 실행 설치

2026-11-11 PM이 정기 운영을 승인했다. 설치 파일은 `backend/ops/storage-deletion/`에 있다.
이 코드의 배포가 끝나고 운영 역할의 위 권한과 대상 설정을 확인한 뒤 설치한다. 설치와 실제
실행 결과는 [이슈 #185](https://github.com/kakaotechcampus-4/ktc4-chungnam-1/issues/185)에 남긴다.

- 5분마다 기한이 지난 종료 녹음을 최대 100건 대기열에 넣고, 기존 대기열을 최대 100건 처리한다.
- 실행 중인 `api` 컨테이너의 코드와 설정을 쓰므로 새 키나 `.env` 사본을 만들지 않는다.
- 같은 systemd service는 겹쳐 실행되지 않으며, 수동 실행과의 중복은 기존 DB advisory lock으로 막는다.
- 등록 사진, 처리 중 녹음과 `not_before`가 남은 요청은 보호한다. 사진 업로드의 보류 기한과 음성 보관 기준은 유지한다.
- 오류는 service 실패와 대기열의 오류 코드로 남는다. 다음 5분 실행에서 다시 시도한다.
- 실행 중 API 컨테이너가 교체되면 실패할 수 있다. 완료 처리하지 못한 요청은 다음 실행에서 다시 확인한다.

운영 저장소 루트에서 다음을 실행한다. service의 WorkingDirectory는 현재 운영 경로
`/home/ubuntu/ktc4-chungnam-1/backend`이며 다른 환경은 설치 전에 맞춘다.

```sh
sudo install -m 0644 backend/ops/storage-deletion/saerok-storage-deletion.service /etc/systemd/system/
sudo install -m 0644 backend/ops/storage-deletion/saerok-storage-deletion.timer /etc/systemd/system/
sudo systemd-analyze verify /etc/systemd/system/saerok-storage-deletion.service /etc/systemd/system/saerok-storage-deletion.timer
sudo systemctl daemon-reload
sudo systemctl start saerok-storage-deletion.service
sudo systemctl enable --now saerok-storage-deletion.timer
systemctl list-timers saerok-storage-deletion.timer
systemctl show saerok-storage-deletion.service -p Result -p ExecMainStatus
journalctl -u saerok-storage-deletion.service --since '30 minutes ago' --no-pager
```

`Result=success`, `ExecMainStatus=0`, 삭제 결과의 `errors={}`와 `busy=false`를 확인한다.
다음 예약 실행도 같은 결과인지 확인한다. 실패가 반복되면 대기열의 `last_error_code`와
`app.ops.runtime_check`의 `DELETION_QUEUE`, `OVERDUE_AUDIO` 경고를 확인한다. 집계와 안전한
오류 코드만 기록하며 객체 키와 사용자 자료는 journal에 출력하지 않는다.

중지할 때는 `sudo systemctl disable --now saerok-storage-deletion.timer`를 쓴다. 진행 중인
service는 끝나도록 둔다. 30분 제한으로 Docker CLI가 종료돼도 컨테이너 안의 명령이 남을 수
있으므로 프로세스와 advisory lock을 확인하기 전 다시 실행하지 않는다. 중지와 코드 되돌리기는
이미 영구 삭제한 파일을 복구하지 않는다.

## 운영 범위와 제한

- 기한이 지난 녹음을 찾아 삭제 요청을 만드는 작업은 [점검 도구](storage-audit.md)의 `--enqueue-safe-expired`가 맡는다. 진행 중 원본은 넣지 않으므로 이 실행기만으로 모든 24시간 상한 준수를 보장하지 않는다.
- 정상 주기에서도 다음 실행까지 최대 약 5분과 처리 시간이 더 걸릴 수 있다. 서버 중단, 권한 오류와 요청 적체는 별도 감시한다.
- S3와 DB의 객체 수가 다르다는 이유만으로 남는 파일을 삭제하지 않는다. DB에 없는 과거 테스트 파일은 별도 조회와 승인 대상이다.
- Lifecycle은 보조 삭제 규칙이며 이 도구가 버킷 규칙을 만들거나 변경하지 않는다.

## 검증과 근거

합성 PostgreSQL에서 읽기 모드 무변경, 성공 기록, 실패 유지와 재시도 순서, 동시 실행,
살아 있는 사진 및 처리 중 녹음 보호, migration 이전 요청 보존을 검사한다. S3는 대역으로
검사하며 실제 운영 S3 삭제 시험은 아니다.

`uv run pytest tests/test_storage_deletion.py tests/test_storage_deletion_versions.py tests/test_storage_audit.py tests/test_migrations.py`

[AWS HeadObject 권한과 403/404](https://docs.aws.amazon.com/boto3/latest/reference/services/s3/client/head_object.html),
[AWS 버전별 만료 동작](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html).
