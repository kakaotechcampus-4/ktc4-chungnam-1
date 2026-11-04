import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "shutdown_budget", Path(__file__).parents[1] / "scripts/check_shutdown_budget.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def config(card="360s", speech="1860s"):
    return {
        "services": {
            "card-worker": {"init": True, "stop_grace_period": card, "environment": {}},
            "speech-worker": {
                "init": True,
                "stop_grace_period": speech,
                "environment": {},
            },
        }
    }


def test_default_budgets_cover_both_speech_phases():
    result = module.check(config())
    assert result["status"] == "ok"
    assert result["workers"][1]["requiredGraceSeconds"] == 1860


def test_empty_compose_environment_uses_application_defaults():
    data = config()
    data["services"]["speech-worker"]["environment"] = None
    assert module.check(data)["status"] == "ok"


def test_old_180_seconds_is_rejected_for_both_workers():
    result = module.check(config("180s", "180s"))
    assert result["status"] == "attention_required"
    assert all(not worker["passed"] for worker in result["workers"])


def test_custom_lease_and_override_require_new_budget():
    data = config()
    data["services"]["speech-worker"]["environment"][
        "SAEROK_SPEECH_ANALYSIS_LEASE_SECONDS"
    ] = "1200"
    assert module.check(data)["status"] == "attention_required"
    data["services"]["speech-worker"]["stop_grace_period"] = "41m"
    assert module.check(data)["status"] == "ok"


@pytest.mark.parametrize(
    ("text", "seconds"), [("31m0s", 1860), ("1h2m3.5s", 3723.5), ("500ms", 0.5)]
)
def test_compose_duration_formats(text, seconds):
    assert module.duration_seconds(text) == seconds


@pytest.mark.parametrize("text", ["-1s", "garbage", "3s trailing", "NaN", None])
def test_malformed_duration_is_rejected(text):
    with pytest.raises((ValueError, TypeError)):
        module.duration_seconds(text)


def test_missing_init_does_not_pass():
    data = config()
    del data["services"]["card-worker"]["init"]
    assert module.check(data)["status"] == "attention_required"


def test_config_errors_are_redacted(monkeypatch, capsys):
    import subprocess

    def broken(*args, **kwargs):
        raise subprocess.CalledProcessError(1, "docker", stderr="synthetic-password")

    monkeypatch.setattr(module.subprocess, "run", broken)
    monkeypatch.setattr("sys.argv", ["check", "--compose-file", "compose.yml"])
    with pytest.raises(SystemExit) as exc:
        module.main()
    assert exc.value.code == 1
    output = capsys.readouterr()
    assert "synthetic-password" not in output.out + output.err
