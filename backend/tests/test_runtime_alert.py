"""운영 점검 알림(`app.ops.runtime_alert`). 실제 웹훅을 부르지 않고 httpx 대역으로 확인한다."""

import json
from datetime import UTC, datetime

import httpx

from app.ops.runtime_alert import issues_from, message, run

NOW = datetime(2026, 11, 4, 1, 30, tzinfo=UTC)
URL = "https://discord.example/api/webhooks/synthetic/token"


def _transport(sent: list, status: int = 204) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content))
        return httpx.Response(status)

    return httpx.MockTransport(handler)


def _result(*issues: str) -> str:
    return json.dumps({"status": "attention" if issues else "ok", "issues": list(issues),
                       "database": {"counts": {"profiles": 3}}})


def test_first_run_without_issues_stays_quiet_and_remembers(tmp_path):
    state, sent = tmp_path / "alert.json", []
    assert run(_result(), state, set(), url=URL, host="ec2", now=NOW, transport=_transport(sent)) == 0
    assert sent == [] and json.loads(state.read_text(encoding="utf-8")) == {"issues": []}


def test_new_issue_is_sent_once_and_repeats_are_quiet(tmp_path):
    state, sent = tmp_path / "alert.json", []
    for _ in range(3):
        assert run(_result("PRIMARY_STT_UNREACHABLE"), state, set(), url=URL, host="ec2",
                   now=NOW, transport=_transport(sent)) == 0
    assert len(sent) == 1
    assert "PRIMARY_STT_UNREACHABLE" in sent[0]["content"] and "ec2" in sent[0]["content"]


def test_recovery_is_sent(tmp_path):
    state, sent = tmp_path / "alert.json", []
    run(_result("SPEECH_WORKER_NOT_RUNNING_OR_UNINSPECTED"), state, set(), url=URL, host="ec2",
        now=NOW, transport=_transport(sent))
    run(_result(), state, set(), url=URL, host="ec2", now=NOW, transport=_transport(sent))
    assert len(sent) == 2 and "해소" in sent[1]["content"]


def test_only_issue_codes_are_sent(tmp_path):
    state, sent = tmp_path / "alert.json", []
    run(_result("MIGRATION_MISMATCH"), state, set(), url=URL, host="ec2", now=NOW, transport=_transport(sent))
    content = sent[0]["content"]
    assert "profiles" not in content and URL not in content and "token" not in content


def test_ignored_codes_do_not_alert(tmp_path):
    state, sent = tmp_path / "alert.json", []
    code = run(_result("DELETION_QUEUE"), state, {"DELETION_QUEUE"}, url=URL, host="ec2",
               now=NOW, transport=_transport(sent))
    assert code == 0 and sent == []


def test_failed_send_keeps_state_so_the_next_run_retries(tmp_path):
    state, sent = tmp_path / "alert.json", []
    assert run(_result("BACKUP_STT_UNREACHABLE"), state, set(), url=URL, host="ec2", now=NOW,
               transport=_transport(sent, status=500)) == 1
    assert not state.exists()
    assert run(_result("BACKUP_STT_UNREACHABLE"), state, set(), url=URL, host="ec2", now=NOW,
               transport=_transport(sent)) == 0
    assert len(sent) == 2


def test_missing_or_unsafe_webhook_is_a_configuration_error(tmp_path, capsys):
    state = tmp_path / "alert.json"
    assert run(_result("MIGRATION_MISMATCH"), state, set(), url=None, host="ec2", now=NOW) == 2
    assert run(_result("MIGRATION_MISMATCH"), state, set(), url="http://insecure.example/hook",
               host="ec2", now=NOW) == 2
    assert "insecure.example" not in capsys.readouterr().out


def test_unreadable_check_output_is_reported():
    assert issues_from({}, set()) == ["RUNTIME_CHECK_OUTPUT_UNREADABLE"]
    assert issues_from({"issues": "not-a-list"}, set()) == ["RUNTIME_CHECK_OUTPUT_UNREADABLE"]


def test_message_names_new_issues_only_when_some_were_known():
    text = message(["A"], ["A", "B"], "ec2", NOW)
    assert "현재 문제: A, B" in text and "새로 생긴 문제: B" in text
    assert message(None, [], "ec2", NOW) is None
