"""삭제 대기열을 한 묶음씩 처리한다. 기본 실행은 조회만 한다."""

import argparse
import asyncio
import json
import sys

from app.core.config import Settings
from app.core.database import connect
from app.services.storage_deletion import (
    DeletionTarget,
    S3DeleteBackend,
    process_deletions,
)


async def run_once(
    settings: Settings, *, apply: bool, limit: int, allow_versioned_photos: bool = False
):
    if not settings.database_url:
        raise ValueError("SAEROK_DATABASE_URL이 필요합니다.")
    targets = []
    if settings.speech_audio_s3_bucket:
        targets.append(
            DeletionTarget(
                "audio",
                settings.speech_audio_s3_bucket,
                settings.speech_audio_s3_region,
                settings.speech_audio_s3_prefix,
            )
        )
    if settings.image_s3_bucket:
        targets.append(
            DeletionTarget(
                "photo",
                settings.image_s3_bucket,
                settings.image_s3_region,
                settings.image_s3_prefix,
            )
        )
    async with connect(settings.database_url) as conn:
        # 연결과 SQL 자체가 장시간 멈추지 않도록 운영 도구에만 제한을 둔다.
        await conn.execute("SET statement_timeout = '10s'")
        return await process_deletions(
            conn,
            targets=tuple(targets),
            backend=S3DeleteBackend(allow_versioned_photos=allow_versioned_photos),
            apply=apply,
            limit=limit,
        )


def main():
    parser = argparse.ArgumentParser(
        description="새록 S3 삭제 대기열 확인과 한 묶음 처리"
    )
    parser.add_argument(
        "--apply", action="store_true", help="DB 기록과 실제 S3 삭제 실행"
    )
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument(
        "--allow-versioned-photos",
        action="store_true",
        help="삭제 대기 사진의 모든 버전을 영구 삭제. 운영 승인 후에만 사용",
    )
    args = parser.parse_args()
    try:
        factory = asyncio.SelectorEventLoop if sys.platform == "win32" else None
        with asyncio.Runner(loop_factory=factory) as runner:
            result = runner.run(
                run_once(
                    Settings(),
                    apply=args.apply,
                    limit=args.limit,
                    allow_versioned_photos=args.allow_versioned_photos,
                )
            )
    except Exception:  # noqa: BLE001 - DSN과 S3 예외 본문을 CLI에 노출하지 않는다.
        print(json.dumps({"status": "error", "code": "DELETION_CHECK_FAILED"}))
        raise SystemExit(1) from None
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1 if result["errors"] or result["busy"] else 0)


if __name__ == "__main__":
    main()
