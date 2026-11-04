"""명시한 로컬 이미지에서만 실행하는 Linux SIGTERM 검사."""

import json
import os
import subprocess
import time
from pathlib import Path
from uuid import uuid4

import pytest


def test_docker_sigterm_finishes_current_job():
    image = os.environ.get("SAELOG_WORKER_TEST_IMAGE")
    if not image:
        pytest.skip("SAELOG_WORKER_TEST_IMAGE을 지정한 별도 Docker 검증")
    token = uuid4().hex
    name = f"saelog-shutdown-test-{token}"
    fixture = Path(__file__).with_name("fixtures") / "graceful_worker.py"

    def docker(*args):
        return subprocess.run(
            ["docker", *args],
            check=True,
            capture_output=True,
            encoding="utf-8",
            timeout=20,
        ).stdout.strip()

    try:
        docker(
            "run",
            "-d",
            "--name",
            name,
            "--label",
            f"saelog.shutdown-test={token}",
            "--init",
            "--network",
            "none",
            "-e",
            "PYTHONPATH=/app",
            "--mount",
            f"type=bind,source={fixture.resolve()},target=/tmp/graceful_worker.py,readonly",
            image,
            "python",
            "/tmp/graceful_worker.py",
        )
        deadline = time.monotonic() + 10
        while "SYNTHETIC_JOB_STARTED" not in docker("logs", name):
            if time.monotonic() >= deadline:
                pytest.fail("합성 worker가 시작되지 않았습니다.")
            time.sleep(0.1)
        docker("stop", "--timeout", "10", name)
        logs = docker("logs", name)
        state = json.loads(docker("inspect", "--format", "{{json .State}}", name))
        assert state["ExitCode"] == 0
        assert logs.count("SYNTHETIC_JOB_STARTED") == 1
        assert "SYNTHETIC_JOB_FINISHED" in logs
        assert "SYNTHETIC_WORKER_STOPPED" in logs
    finally:
        # 이 테스트가 만든 이름과 라벨을 모두 확인한 컨테이너만 정리한다.
        probe = subprocess.run(
            ["docker", "inspect", "--format", "{{json .Config.Labels}}", name],
            check=False,
            capture_output=True,
            encoding="utf-8",
            timeout=10,
        )
        if (
            probe.returncode == 0
            and json.loads(probe.stdout).get("saelog.shutdown-test") == token
        ):
            docker("rm", "--force", name)
