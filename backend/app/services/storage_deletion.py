"""기존 삭제 대기열 처리. 기본은 조회이며 실제 삭제는 호출자가 명시해야 한다."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Literal, Protocol
from uuid import UUID

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from app.core.database import DbConnection

# 같은 DB를 대상으로 이 실행기 두 개가 중복 삭제하지 않도록 세션 잠금을 잡는다.
# S3 호출 중 DB 트랜잭션이나 행 잠금을 유지하지 않는다.
LOCK_NAMESPACE = 1398891884
LOCK_KEY = 1147497553


@dataclass(frozen=True)
class DeletionTarget:
    kind: Literal["audio", "photo"]
    bucket: str
    region: str
    prefix: str


class DeleteBackend(Protocol):
    async def delete_and_confirm(
        self, target: DeletionTarget, object_key: str
    ) -> None: ...


class DeletionError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def validate_targets(targets: tuple[DeletionTarget, ...]) -> None:
    if not targets:
        raise ValueError("삭제할 버킷과 접두사를 먼저 설정해야 합니다.")
    for target in targets:
        if (
            not target.bucket
            or not target.region
            or not target.prefix
            or target.prefix != target.prefix.strip("/")
            or any(part in {"", ".", ".."} for part in target.prefix.split("/"))
        ):
            raise ValueError("삭제 대상 설정이 올바르지 않습니다.")
    for i, left in enumerate(targets):
        for right in targets[i + 1 :]:
            # 큐에는 bucket이 없어 버킷이 달라도 접두사가 겹치면 판단할 수 없다.
            if (
                left.prefix == right.prefix
                or left.prefix.startswith(right.prefix + "/")
                or right.prefix.startswith(left.prefix + "/")
            ):
                raise ValueError("삭제 대기열의 버킷을 구분할 수 없는 접두사입니다.")


def resolve_target(
    object_key: str, targets: tuple[DeletionTarget, ...]
) -> DeletionTarget | None:
    for target in targets:
        prefix = target.prefix + "/"
        if not object_key.startswith(prefix):
            continue
        filename = object_key[len(prefix) :]
        stem, dot, extension = filename.rpartition(".")
        extensions = {"wav"} if target.kind == "audio" else {"jpg", "png"}
        if not dot or "/" in filename or extension not in extensions:
            return None
        try:
            if str(UUID(stem)) != stem:
                return None
        except ValueError:
            return None
        return target
    return None


class S3DeleteBackend:
    """사진 버전 영구 삭제는 명시적으로 켠 실행에서만 허용한다."""

    def __init__(self, *, client_factory=None, allow_versioned_photos=False):
        self._client_factory = client_factory or self._client
        self._allow_versioned_photos = allow_versioned_photos

    @staticmethod
    def _client(region):
        return boto3.client(
            "s3",
            region_name=region,
            endpoint_url=f"https://s3.{region}.amazonaws.com",
            config=Config(
                connect_timeout=5, read_timeout=10, retries={"total_max_attempts": 1}
            ),
        )

    async def delete_and_confirm(self, target: DeletionTarget, object_key: str) -> None:
        await asyncio.to_thread(self._delete, target, object_key)

    def _delete(self, target, object_key):
        client = self._client_factory(target.region)
        try:
            state = client.get_bucket_versioning(Bucket=target.bucket)
            if state.get("Status") is not None:
                if not self._allow_versioned_photos or target.kind != "photo":
                    raise DeletionError("VERSIONED_BUCKET_REQUIRES_REVIEW")
                if state.get("MFADelete") == "Enabled":
                    raise DeletionError("MFA_DELETE_REQUIRES_REVIEW")
                # 대기열의 검증과 별개로 이 경로에서도 정확한 사진 키인지 확인한다.
                validate_targets((target,))
                if resolve_target(object_key, (target,)) != target:
                    raise DeletionError("UNKNOWN_OBJECT_ROUTE")
                self._delete_photo_versions(client, target.bucket, object_key)
            else:
                client.delete_object(Bucket=target.bucket, Key=object_key)
            try:
                client.head_object(Bucket=target.bucket, Key=object_key)
            except ClientError as error:
                if (
                    error.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
                    == 404
                ):
                    return
                raise
            raise DeletionError("DELETE_NOT_CONFIRMED")
        except DeletionError:
            raise
        except Exception as error:
            # 예외 본문에 키나 버킷이 있을 수 있으므로 외부에는 코드만 전한다.
            raise DeletionError("STORAGE_UNAVAILABLE") from error

    @staticmethod
    def _versions(client, bucket, key):
        items = {"Versions": [], "DeleteMarkers": []}
        markers = {}
        seen = set()
        for _ in range(10):
            page = client.list_object_versions(
                Bucket=bucket, Prefix=key, MaxKeys=1000, **markers
            )
            for field in items:
                for item in page.get(field, []):
                    # Prefix는 파일 이름 전체와 같은지 보장하지 않는다.
                    if item["Key"] == key:
                        if not item.get("VersionId"):
                            raise DeletionError("VERSION_LIST_INVALID")
                        items[field].append(
                            {"Key": key, "VersionId": item["VersionId"]}
                        )
            if sum(map(len, items.values())) > 1000:
                raise DeletionError("VERSION_LIST_LIMIT")
            if not page.get("IsTruncated", False):
                return items
            marker = (page.get("NextKeyMarker"), page.get("NextVersionIdMarker"))
            if not all(marker) or marker in seen:
                raise DeletionError("VERSION_LIST_INVALID")
            seen.add(marker)
            markers = {"KeyMarker": marker[0], "VersionIdMarker": marker[1]}
        raise DeletionError("VERSION_LIST_LIMIT")

    def _delete_photo_versions(self, client, bucket, key):
        items = self._versions(client, bucket, key)
        # 데이터 삭제 실패 때 삭제 표시를 먼저 지워 옛 사진이 다시 보이지 않게 한다.
        for field in ("Versions", "DeleteMarkers"):
            if not items[field]:
                continue
            result = client.delete_objects(
                Bucket=bucket, Delete={"Objects": items[field], "Quiet": False}
            )
            expected = {(item["Key"], item["VersionId"]) for item in items[field]}
            actual = {
                (item["Key"], item.get("VersionId"))
                for item in result.get("Deleted", [])
            }
            if result.get("Errors") or actual != expected:
                raise DeletionError("VERSION_DELETE_NOT_CONFIRMED")
        if any(self._versions(client, bucket, key).values()):
            raise DeletionError("DELETE_NOT_CONFIRMED")


async def _has_live_reference(connection, object_key):
    row = await (
        await connection.execute(
            """
        SELECT EXISTS(SELECT 1 FROM photos WHERE s3_object_key = %s)
            OR EXISTS(SELECT 1 FROM speech_analysis_jobs
                       WHERE s3_object_key = %s
                         AND status IN ('uploading', 'queued', 'transcribing')) AS active
    """,
            (object_key, object_key),
        )
    ).fetchone()
    return row["active"]


async def process_deletions(
    connection: DbConnection,
    *,
    targets: tuple[DeletionTarget, ...],
    backend: DeleteBackend,
    apply: bool = False,
    limit: int = 100,
) -> dict:
    validate_targets(targets)
    if not 1 <= limit <= 1000:
        raise ValueError("한 번에 확인할 건수는 1~1000이어야 합니다.")
    result = {
        "mode": "apply" if apply else "dry_run",
        "inspected": 0,
        "eligible": 0,
        "deleted": 0,
        "errors": {},
        "busy": False,
    }
    locked = False
    if apply:
        row = await (
            await connection.execute(
                "SELECT pg_try_advisory_lock(%s, %s) AS acquired",
                (LOCK_NAMESPACE, LOCK_KEY),
            )
        ).fetchone()
        locked = row["acquired"]
        if not locked:
            result["busy"] = True
            return result
    try:
        rows = await (
            await connection.execute(
                """
            SELECT s3_object_key FROM storage_deletion_request_queue
             WHERE not_before <= clock_timestamp()
             ORDER BY last_attempt_at NULLS FIRST, requested_at, s3_object_key
             LIMIT %s
        """,
                (limit,),
            )
        ).fetchall()
        for row in rows:
            key = row["s3_object_key"]
            result["inspected"] += 1
            code = None
            target = resolve_target(key, targets)
            if target is None:
                code = "UNKNOWN_OBJECT_ROUTE"
            elif await _has_live_reference(connection, key):
                code = "LIVE_REFERENCE"
            else:
                result["eligible"] += 1
            if apply:
                await connection.execute(
                    """
                    UPDATE storage_deletion_request_queue
                       SET attempt_count = attempt_count + 1, last_attempt_at = now(),
                           last_error_code = NULL
                     WHERE s3_object_key = %s
                """,
                    (key,),
                )
                if code is None:
                    try:
                        await backend.delete_and_confirm(target, key)
                    except DeletionError as error:
                        code = error.code
                    else:
                        async with connection.transaction():
                            await connection.execute(
                                """
                                UPDATE speech_analysis_jobs
                                   SET audio_deleted_at = COALESCE(audio_deleted_at, now()),
                                       updated_at = now()
                                 WHERE s3_object_key = %s
                            """,
                                (key,),
                            )
                            await connection.execute(
                                "DELETE FROM storage_deletion_request_queue WHERE s3_object_key = %s",
                                (key,),
                            )
                        result["deleted"] += 1
                if code is not None:
                    await connection.execute(
                        """
                        UPDATE storage_deletion_request_queue SET last_error_code = %s
                         WHERE s3_object_key = %s
                    """,
                        (code, key),
                    )
            if code is not None:
                result["errors"][code] = result["errors"].get(code, 0) + 1
        return result
    finally:
        if locked:
            await connection.execute(
                "SELECT pg_advisory_unlock(%s, %s)", (LOCK_NAMESPACE, LOCK_KEY)
            )
