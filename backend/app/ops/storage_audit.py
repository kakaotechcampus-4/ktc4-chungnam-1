"""S3 목록과 DB 참조를 대조한다. 파일 본문을 읽거나 S3를 수정하지 않는다."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import UTC, datetime

from botocore.exceptions import ClientError

from app.core.config import Settings
from app.core.database import connect
from app.services.storage_deletion import S3DeleteBackend


async def expired_audio(connection, *, enqueue: bool = False, limit: int = 100):
    """기한이 지난 원본 중 STT가 끝났거나 실패로 끝난 건만 삭제 대기열에 넣는다.

    실행 중 원본을 지우거나 작업 실패 여부를 새로 결정하지 않는다. 진행 중인 건은
    별도로 세어 운영자가 작업 상태를 확인하도록 한다. DB 행이 있다고 실제 S3에
    원본이 남았다고 단정하지 않는다.
    """
    if not 1 <= limit <= 1000:
        raise ValueError("limit must be between 1 and 1000")
    rows = await (await connection.execute("""
        SELECT status, count(*) AS count FROM speech_analysis_jobs
         WHERE data_expires_at <= now() AND audio_deleted_at IS NULL
         GROUP BY status ORDER BY status
    """)).fetchall()
    inserted = 0
    if enqueue:
        cursor = await connection.execute("""
            INSERT INTO storage_deletion_request_queue (s3_object_key)
            SELECT j.s3_object_key FROM speech_analysis_jobs j
             WHERE j.data_expires_at <= now() AND j.audio_deleted_at IS NULL
               AND j.status IN ('sttCompleted', 'generatingReport', 'completed', 'failed')
               AND NOT EXISTS (SELECT 1 FROM storage_deletion_request_queue q
                                WHERE q.s3_object_key = j.s3_object_key)
               AND NOT EXISTS (SELECT 1 FROM speech_analysis_jobs live
                                WHERE live.s3_object_key = j.s3_object_key
                                  AND live.status IN ('uploading', 'queued', 'transcribing'))
             ORDER BY j.data_expires_at, j.analysis_id
             LIMIT %s
            ON CONFLICT (s3_object_key) DO NOTHING
        """, (limit,))
        inserted = cursor.rowcount
    return {"expired_by_status": {r["status"]: r["count"] for r in rows},
            "enqueued": inserted, "s3_modified": False}


def inspect_bucket(client, bucket: str, *, references: set[str], deadlines: dict,
                   now: datetime, limit: int = 10000):
    """한 버킷의 현재 객체 목록만 읽는다. 조회 한도를 넘기면 incomplete로 알린다."""
    if not 1 <= limit <= 100000:
        raise ValueError("invalid object limit")
    try:
        rules = client.get_bucket_lifecycle_configuration(Bucket=bucket).get("Rules", [])
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") != "NoSuchLifecycleConfiguration":
            raise
        rules = []
    versioning = client.get_bucket_versioning(Bucket=bucket).get("Status", "unversioned")
    result = {"listed": 0, "bytes": 0, "referenced": 0, "unreferenced": 0,
              "bucket_root_objects": 0, "past_audio_deadline": 0,
              "lifecycle_rule_count": len(rules), "versioning": versioning,
              "complete": False, "oldest_object_at": None}
    token = None
    seen_tokens = set()
    pages = 0
    oldest = None
    while result["listed"] < limit and pages < 100:
        pages += 1
        args = {"Bucket": bucket, "MaxKeys": min(1000, limit - result["listed"])}
        if token:
            args["ContinuationToken"] = token
        page = client.list_objects_v2(**args)
        for obj in page.get("Contents", []):
            key = obj["Key"]
            result["listed"] += 1
            result["bytes"] += obj["Size"]
            result["referenced" if key in references else "unreferenced"] += 1
            result["bucket_root_objects"] += int("/" not in key)
            deadline = deadlines.get(key)
            result["past_audio_deadline"] += int(deadline is not None and deadline <= now)
            modified = obj["LastModified"]
            oldest = modified if oldest is None else min(oldest, modified)
        if not page.get("IsTruncated", False):
            result["complete"] = True
            break
        next_token = page.get("NextContinuationToken")
        if not next_token or next_token in seen_tokens:
            break
        seen_tokens.add(next_token)
        token = next_token
    result["oldest_object_at"] = oldest.isoformat() if oldest else None
    # 목록과 참조의 시점이 다를 수 있다. unreferenced를 삭제 대상으로 확정하지 않는다.
    result["unreferenced_requires_review"] = result["unreferenced"] > 0
    return result


async def run_once(settings, *, enqueue=False, limit=100, object_limit=10000,
                   include_s3=False, client_factory=None):
    if not settings.database_url:
        raise ValueError("database is required")
    async with connect(settings.database_url) as conn:
        await conn.execute("SET statement_timeout = '10s'")
        result = await expired_audio(conn, enqueue=enqueue, limit=limit)
        if not include_s3:
            return result
        photos = await (await conn.execute("SELECT s3_object_key FROM photos")).fetchall()
        audio = await (await conn.execute(
            "SELECT s3_object_key, data_expires_at FROM speech_analysis_jobs"
        )).fetchall()
    # S3를 기다리는 동안 DB 트랜잭션을 유지하지 않는다.
    buckets = {}
    for name, region, rows, is_audio in (
        (settings.speech_audio_s3_bucket, settings.speech_audio_s3_region, audio, True),
        (settings.image_s3_bucket, settings.image_s3_region, photos, False),
    ):
        if not name:
            continue
        entry = buckets.setdefault(name, {"region": region, "references": set(), "deadlines": {}})
        entry["references"].update(row["s3_object_key"] for row in rows)
        if is_audio:
            entry["deadlines"].update({row["s3_object_key"]: row["data_expires_at"] for row in rows})
    factory = client_factory or S3DeleteBackend._client
    result["buckets"] = []
    for bucket, entry in buckets.items():
        result["buckets"].append(await asyncio.to_thread(
            inspect_bucket, factory(entry["region"]), bucket,
            references=entry["references"], deadlines=entry["deadlines"],
            now=datetime.now(UTC), limit=object_limit,
        ))
    return result


def main():
    parser = argparse.ArgumentParser(description="S3 원본 보관 기한과 DB 참조 점검")
    parser.add_argument("--s3", action="store_true", help="설정된 버킷 목록과 Lifecycle 읽기")
    parser.add_argument("--enqueue-safe-expired", action="store_true",
                        help="STT 이후 또는 실패 완료 원본만 DB 삭제 대기열에 추가. S3 삭제는 하지 않음")
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--object-limit", type=int, default=10000)
    args = parser.parse_args()
    try:
        factory = asyncio.SelectorEventLoop if sys.platform == "win32" else None
        with asyncio.Runner(loop_factory=factory) as runner:
            result = runner.run(run_once(Settings(), enqueue=args.enqueue_safe_expired,
                                        include_s3=args.s3, limit=args.limit,
                                        object_limit=args.object_limit))
    except Exception:
        print(json.dumps({"status": "error", "code": "STORAGE_AUDIT_FAILED"}))
        raise SystemExit(1) from None
    print(json.dumps(result))


if __name__ == "__main__":
    main()
