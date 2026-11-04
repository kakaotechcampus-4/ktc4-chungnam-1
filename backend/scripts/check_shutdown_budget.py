"""선택한 Compose 설정의 worker 종료 유예 검사. 컨테이너는 변경하지 않는다."""

import argparse
import json
import math
import re
import subprocess


def duration_seconds(value):
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        raise TypeError("종료 유예 시간 형식을 확인할 수 없습니다.")
    units = {"h": 3600, "m": 60, "s": 1, "ms": 0.001, "us": 0.000001, "ns": 0.000000001}
    parts = list(re.finditer(r"(\d+(?:\.\d+)?)(ms|us|ns|h|m|s)", value))
    if not parts or "".join(p.group() for p in parts) != value:
        raise ValueError("종료 유예 시간 형식을 확인할 수 없습니다.")
    return sum(float(p[1]) * units[p[2]] for p in parts)


def check(config):
    result = {"status": "ok", "workers": []}
    for service, variable, default, phases in (
        ("card-worker", "SAEROK_CARD_GENERATION_LEASE_SECONDS", 300, 1),
        ("speech-worker", "SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS", 900, 2),
    ):
        worker = config["services"][service]
        value = (worker.get("environment") or {}).get(variable, default)
        lease = int(value)
        if lease < 60:
            raise ValueError("작업 임대 시간 설정이 올바르지 않습니다.")
        # STT 완료 후 리포트 단계에서 임대를 다시 부여하므로 두 단계 합으로 계산.
        required = phases * lease + 60
        actual = duration_seconds(worker.get("stop_grace_period", "10s"))
        okay = (
            math.isfinite(actual) and actual >= required and worker.get("init") is True
        )
        result["workers"].append(
            {
                "service": service,
                "leaseSeconds": lease,
                "phases": phases,
                "requiredGraceSeconds": required,
                "actualGraceSeconds": actual,
                "init": worker.get("init") is True,
                "passed": okay,
            }
        )
        if not okay:
            result["status"] = "attention_required"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--compose-file",
        action="append",
        required=True,
        help="적용할 파일을 순서대로 반복 지정. override도 빠짐없이 포함",
    )
    args = parser.parse_args()
    # workers 프로필이 기본 실행에서 빠져 있어도 배포 설정 검사는 포함해야 한다.
    command = ["docker", "compose", "--profile", "*"]
    for path in args.compose_file:
        command.extend(["-f", path])
    command.extend(["config", "--format", "json"])
    try:
        # config 출력에는 비밀 값이 포함될 수 있어 원문과 stderr를 출력하지 않는다.
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=30,
            check=True,
        )
        result = check(json.loads(completed.stdout))
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        print(json.dumps({"status": "error", "code": "SHUTDOWN_CONFIG_CHECK_FAILED"}))
        raise SystemExit(1) from None
    print(json.dumps(result))
    raise SystemExit(0 if result["status"] == "ok" else 1)


if __name__ == "__main__":
    main()
