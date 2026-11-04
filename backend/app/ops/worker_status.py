"""지정한 Docker worker의 상태 필드만 조회한다. 로그와 환경변수는 읽지 않는다."""
import asyncio
import json
import re
import subprocess

ROLES = {"speech", "card", "photo"}
STATES = {"created", "running", "paused", "restarting", "removing", "exited", "dead"}
TEMPLATE = (
    '{"status":{{json .State.Status}},"running":{{json .State.Running}},'
    '"paused":{{json .State.Paused}},"restarting":{{json .State.Restarting}},'
    '"restartCount":{{json .RestartCount}}}'
)


def parse_target(value):
    role, separator, name = value.partition("=")
    if (not separator or role not in ROLES
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", name)):
        raise ValueError("INVALID_WORKER_TARGET")
    return role, name


def inspect_worker(name):
    try:
        # shell을 쓰지 않고 Docker에 필요한 필드만 요청한다.
        result = subprocess.run(["docker", "inspect", "--type", "container", "--format", TEMPLATE, name],
                                capture_output=True, text=True, encoding="utf-8", errors="replace",
                                timeout=5, check=False)
        if result.returncode:
            raise ValueError("INSPECTION_FAILED")
        item = json.loads(result.stdout)
        if (item.get("status") not in STATES
                or type(item.get("restartCount")) is not int or item["restartCount"] < 0
                or any(type(item.get(key)) is not bool for key in ("running", "paused", "restarting"))):
            raise ValueError("INVALID_STATE")
        return {"state": item["status"], "restartCount": item["restartCount"],
                "running": item["status"] == "running" and item["running"]
                    and not item["paused"] and not item["restarting"],
                "processingVerified": False}
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, AttributeError):
        return {"state": "inspection_failed", "restartCount": None,
                "running": False, "processingVerified": False}


async def inspect_workers(targets):
    parsed = [parse_target(target) for target in targets]
    if len({role for role, _ in parsed}) != len(parsed):
        raise ValueError("DUPLICATE_WORKER_ROLE")
    results = await asyncio.gather(*(asyncio.to_thread(inspect_worker, name) for _, name in parsed))
    return {role: result for (role, _), result in zip(parsed, results)}
