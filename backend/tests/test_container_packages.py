"""Packaging checks do not start workers or access a database/model."""
import os
from pathlib import Path
import subprocess
import tomllib

import pytest

# 운영 컨테이너에서 실행하는 모듈을 확인한다. API와 worker, 서버에서 `python -m`으로 돌리는 점검과
# 삭제 도구, 리포트 완료 푸시. 새 worker나 운영 도구를 추가하는 PR이 여기에 import를 함께 늘린다.
RUNTIME_IMPORTS = (
    "import card_generation, report_generation, proposal_generation; "
    "import app.main, app.workers.card_generation, app.workers.speech_analysis; "
    "import app.workers.storage_deletion, app.workers.photo_analysis, photo_analysis; "
    "import app.ops.runtime_check, app.ops.runtime_alert, app.ops.storage_audit, app.ops.worker_status; "
    "import app.clients.fcm, app.services.report_notifications; "
    "print('runtime_imports_ok')"
)


def test_dockerfile_copies_each_ai_runtime_package():
    backend = Path(__file__).resolve().parents[1]
    config = tomllib.loads((backend.parent / "ai/pyproject.toml").read_text(encoding="utf-8"))
    dockerfile = (backend / "Dockerfile").read_text(encoding="utf-8")
    for package in config["tool"]["hatch"]["build"]["targets"]["wheel"]["packages"]:
        assert f"COPY --from=ai {package} /ai/{package}" in dockerfile


def test_built_image_imports_all_workers_without_network():
    image = os.environ.get("SAELOG_PACKAGE_TEST_IMAGE")
    if not image:
        pytest.skip("Set SAELOG_PACKAGE_TEST_IMAGE to an explicitly built local image")
    completed = subprocess.run(
        ["docker", "run", "--rm", "--network", "none", "--read-only",
         "--cap-drop", "ALL", "--security-opt", "no-new-privileges", image,
         "python", "-B", "-c", RUNTIME_IMPORTS],
        capture_output=True, text=True, encoding="utf-8", timeout=60,
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.strip() == "runtime_imports_ok"
