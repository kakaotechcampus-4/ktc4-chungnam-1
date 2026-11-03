"""배포 중 분석 접수와 새 작업 임대 제어. 기본 실행은 읽기 전용 상태 조회다."""

import argparse
import asyncio
import json

import psycopg
from pydantic import ValidationError

from app.core.config import Settings
from app.core.database import connect
from app.services.deployment_control import set_control, snapshot

ACTIONS = ("status", "pause-admissions", "pause-workers", "pause-all",
           "resume-workers", "resume-all")


async def run(database_url, action="status", *, confirm=False):
    if action not in ACTIONS:
        raise ValueError("UNKNOWN_CONTROL_ACTION")
    if action != "status" and not confirm:
        raise ValueError("EXPLICIT_CONFIRMATION_REQUIRED")
    async with asyncio.timeout(10), connect(database_url) as connection:
        if action != "status":
            await set_control(connection, action)
        async with connection.transaction():
            await connection.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
            await connection.execute("SET LOCAL statement_timeout = '3000ms'")
            result = await snapshot(connection)
        return {"action": action, "readOnly": action == "status", **result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=ACTIONS, default="status")
    parser.add_argument("--confirm-change", action="store_true",
                        help="운영 승인 후에만 지정. 접수 및 임대 상태를 실제 변경합니다.")
    args = parser.parse_args()
    try:
        settings = Settings()
        if not settings.database_url:
            raise ValueError("DATABASE_NOT_CONFIGURED")
        result = asyncio.run(run(settings.database_url, args.action, confirm=args.confirm_change),
                             loop_factory=asyncio.SelectorEventLoop)
    except (ValidationError, ValueError, RuntimeError, psycopg.Error, OSError, TimeoutError) as error:
        # DB 주소와 인증값이 섞일 수 있는 예외 원문은 출력하지 않는다.
        code = str(error) if type(error) is ValueError and str(error) in {
            "EXPLICIT_CONFIRMATION_REQUIRED", "PAUSE_ADMISSIONS_FIRST",
            "UNKNOWN_CONTROL_ACTION", "DATABASE_NOT_CONFIGURED",
        } else "CONTROL_FAILED_CHECK_CONFIGURATION_OR_LOCKS"
        print(json.dumps({"error": code}))
        raise SystemExit(1) from None
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
