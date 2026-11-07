"""실제 모델 점검 도구의 기록 검사. 외부 호출은 하지 않는다."""

import importlib.util
import json
from pathlib import Path
import time


def load_runner():
    path = (Path(__file__).resolve().parents[4] / "evals/results"
            / "2026-11-03-real-model-spot-check/run.py")
    spec = importlib.util.spec_from_file_location("spot_runner_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_record_masks_key_and_urls_in_nested_errors(monkeypatch, tmp_path):
    runner = load_runner()
    monkeypatch.setenv("ML_API_KEY", "synthetic-private-key")
    monkeypatch.setattr(runner, "OUT", tmp_path)
    monkeypatch.setattr(runner, "LEDGER", tmp_path / "calls.json")
    monkeypatch.setattr(runner, "MODEL", "gpt-6-luna")
    counter = runner.Counter(1)
    unsafe = "synthetic-private-key https://example.invalid/private-endpoint"
    counter.calls.append({"ok": False, "error": unsafe})
    runner.record("test", counter, time.monotonic(), 0,
                  result={"synthetic": unsafe}, error=unsafe)
    for file in tmp_path.glob("*.json"):
        text = file.read_text(encoding="utf-8")
        assert "synthetic-private-key" not in text
        assert "example.invalid" not in text
        json.loads(text)
    run = json.loads(runner.LEDGER.read_text(encoding="utf-8"))["runs"][0]
    assert run["requested_model"] == "gpt-6-luna"
    assert run["max_output_tokens"] == 16000
    assert run["effort"] == "low"


def test_call_limit_still_prevents_new_request():
    import pytest

    runner = load_runner()
    counter = runner.Counter(runner.CAP)
    with pytest.raises(runner.BudgetExceeded):
        counter.on_chat_model_start({}, [], run_id="synthetic")
    assert counter.used == runner.CAP
