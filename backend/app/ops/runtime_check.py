"""읽기 전용 DB 집계와 선택적인 STT 생존 확인. 본문과 인증값은 출력하지 않는다."""

import argparse
import asyncio
import json
from datetime import UTC, datetime

import httpx
import psycopg
from pydantic import ValidationError

from app.core.config import Settings
from app.core.database import connect


async def database_snapshot(database_url: str, expected_revision: str | None) -> dict:
    async with (
        asyncio.timeout(8),
        connect(database_url) as connection,
        connection.transaction(),
    ):
        await connection.execute("SET TRANSACTION READ ONLY")
        await connection.execute("SET LOCAL statement_timeout = '3000ms'")
        cursor = await connection.execute(
            "SELECT version_num FROM alembic_version ORDER BY version_num"
        )
        revisions = [row["version_num"] for row in await cursor.fetchall()]
        counts = {}
        for name, table, column in (
            ("speech", "speech_analysis_jobs", "status"),
            ("cards", "card_sets", "status"),
            ("photos", "photos", "analysis_status"),
        ):
            # 테이블과 열 이름은 위 상수만 쓰며 외부 입력을 SQL에 붙이지 않는다.
            cursor = await connection.execute(
                f"SELECT {column} AS state, count(*) AS n FROM {table} GROUP BY {column}"
            )
            counts[name] = {row["state"]: row["n"] for row in await cursor.fetchall()}
        cursor = await connection.execute("""
                    SELECT
                      (SELECT count(*) FROM speech_analysis_jobs
                       WHERE status IN ('uploading', 'transcribing', 'generatingReport')
                         AND lease_expires_at <= now()) AS expired_speech_leases,
                      (SELECT count(*) FROM card_sets WHERE status = 'running'
                         AND lease_expires_at <= now()) AS expired_card_leases,
                      (SELECT count(*) FROM speech_analysis_jobs
                       WHERE audio_deleted_at IS NULL AND data_expires_at <= now()) AS overdue_audio,
                      (SELECT count(*) FROM storage_deletion_request_queue) AS deletion_queue,
                      (SELECT count(*) FROM life_fact_proposals) AS story_candidates_present
        """)
        attention = await cursor.fetchone()
        return {
            "revisions": revisions,
            "revisionMatches": None
            if expected_revision is None
            else revisions == [expected_revision],
            "counts": counts,
            "attention": attention,
        }


async def probe_stt(url: str, *, transport=None) -> dict:
    try:
        # 자동 redirect는 다른 호스트로 검사 요청이 넘어가는 것을 막기 위해 끈다.
        async with (
            asyncio.timeout(5),
            httpx.AsyncClient(
                timeout=5, follow_redirects=False, transport=transport
            ) as client,
        ):
            response = await client.get(url.rstrip("/") + "/health/live")
        return {
            "reachable": response.status_code == 200
            and isinstance(response.json(), dict)
            and response.json().get("status") == "ok",
            "httpStatus": response.status_code,
        }
    except (httpx.HTTPError, ValueError, TimeoutError):
        return {"reachable": False, "httpStatus": None}


async def collect(
    settings: Settings, *, expected_revision=None, check_stt=False
) -> dict:
    result = {
        "checkedAtUtc": datetime.now(UTC).isoformat(),
        "readOnly": True,
        "database": None,
        "sttLiveness": None,
        "issues": [],
        "workerProcessState": "not_inspected",
    }
    if not settings.database_url:
        result["issues"].append("DATABASE_NOT_CONFIGURED")
    else:
        try:
            snapshot = await database_snapshot(settings.database_url, expected_revision)
            result["database"] = snapshot
            if snapshot["revisionMatches"] is False:
                result["issues"].append("MIGRATION_MISMATCH")
            for field in (
                "expired_speech_leases",
                "expired_card_leases",
                "overdue_audio",
                "deletion_queue",
            ):
                if snapshot["attention"][field]:
                    result["issues"].append(field.upper())
        except (psycopg.Error, OSError, TimeoutError):
            result["issues"].append("DATABASE_INSPECTION_FAILED")
    if check_stt:
        result["sttLiveness"] = await probe_stt(settings.ai_server_url)
        if not result["sttLiveness"]["reachable"]:
            result["issues"].append("PRIMARY_STT_UNREACHABLE")
    result["status"] = "attention" if result["issues"] else "ok"
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-revision", help="배포 대상에 포함된 Alembic head")
    parser.add_argument(
        "--probe-stt", action="store_true", help="설정된 기본 STT의 /health/live만 조회"
    )
    args = parser.parse_args()
    try:
        settings = Settings()
    except ValidationError:
        print(json.dumps({"status": "attention", "issues": ["INVALID_CONFIGURATION"]}))
        raise SystemExit(1) from None
    result = asyncio.run(
        collect(
            settings,
            expected_revision=args.expected_revision,
            check_stt=args.probe_stt,
        ),
        loop_factory=asyncio.SelectorEventLoop,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result["issues"] else 0)


if __name__ == "__main__":
    main()
