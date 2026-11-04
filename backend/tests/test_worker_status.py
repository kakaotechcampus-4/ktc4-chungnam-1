import json
import subprocess
from types import SimpleNamespace

import pytest

from app.ops import worker_status
from tests.support import run


@pytest.mark.parametrize("status,running,paused,restarting,healthy", [
    ("running", True, False, False, True), ("paused", True, True, False, False),
    ("restarting", True, False, True, False), ("exited", False, False, False, False),
])
def test_only_selected_state_fields_are_requested(monkeypatch, status, running, paused, restarting, healthy):
    calls = []
    def fake(args, **kwargs):
        calls.append(args)
        assert kwargs.get("shell", False) is False
        return SimpleNamespace(returncode=0, stdout=json.dumps({
            "status": status, "running": running, "paused": paused, "restarting": restarting,
            "restartCount": 9492, "ignored_secret": "not-in-output",
        }))
    monkeypatch.setattr(worker_status.subprocess, "run", fake)
    result = run(worker_status.inspect_workers(["speech=synthetic-worker"]))
    assert result["speech"]["state"] == status
    assert result["speech"]["running"] is healthy
    assert result["speech"]["processingVerified"] is False
    assert "not-in-output" not in json.dumps(result)
    assert calls[0][-1] == "synthetic-worker"
    assert ".Config.Env" not in calls[0][-2] and ".State.Error" not in calls[0][-2]


@pytest.mark.parametrize("target", ["speech=--help", "speech=x;curl", "speech=abc def", "api=x", "speech=", "no-separator"])
def test_bad_names_never_execute(monkeypatch, target):
    monkeypatch.setattr(worker_status.subprocess, "run", lambda *a, **k: pytest.fail("must not execute"))
    with pytest.raises(ValueError, match="INVALID_WORKER_TARGET"):
        run(worker_status.inspect_workers([target]))


def test_duplicate_role_does_not_hide_one_worker(monkeypatch):
    monkeypatch.setattr(worker_status.subprocess, "run", lambda *a, **k: pytest.fail("must not execute"))
    with pytest.raises(ValueError, match="DUPLICATE_WORKER_ROLE"):
        run(worker_status.inspect_workers(["speech=one", "speech=two"]))


@pytest.mark.parametrize("mode", ["denied", "timeout", "invalid-json", "invalid-state", "no-docker"])
def test_failure_never_prints_exception_or_docker_output(monkeypatch, mode):
    def fake(*args, **kwargs):
        if mode == "timeout":
            raise subprocess.TimeoutExpired("secret-command", 5, stderr="secret-detail")
        if mode == "no-docker":
            raise OSError("secret-detail")
        return SimpleNamespace(returncode=1 if mode == "denied" else 0,
                               stdout='{"status":"secret-detail"}' if mode == "invalid-state" else "secret-detail")
    monkeypatch.setattr(worker_status.subprocess, "run", fake)
    result = run(worker_status.inspect_workers(["speech=one"]))
    assert result["speech"]["state"] == "inspection_failed"
    assert "secret" not in json.dumps(result)
