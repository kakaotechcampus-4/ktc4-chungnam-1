import json

import httpx
import pytest

from app.core.config import Settings
from app.ops import runtime_check
from tests.card_fixtures import query
from tests.support import run


def test_snapshot_reads_counts_without_changing_queue(migrated_database_url):
    query(
        migrated_database_url,
        "INSERT INTO storage_deletion_request_queue (s3_object_key) VALUES ('synthetic-private-object') RETURNING requested_at",
    )
    before = query(
        migrated_database_url, "SELECT * FROM storage_deletion_request_queue"
    )
    revision = query(migrated_database_url, "SELECT version_num FROM alembic_version")[
        0
    ]["version_num"]
    result = run(
        runtime_check.collect(
            Settings(_env_file=None, database_url=migrated_database_url),
            expected_revision=revision,
        )
    )
    assert result["readOnly"] is True
    assert result["database"]["revisionMatches"] is True
    assert result["database"]["attention"]["deletion_queue"] == 1
    assert result["database"]["deploymentControl"]["counts"]["worker_executions"] == 0
    assert result["issues"] == ["DELETION_QUEUE"]
    assert result["workerProcessState"] == "not_inspected"
    assert result["sttLiveness"] is None
    assert "synthetic-private-object" not in json.dumps(result)
    assert (
        query(migrated_database_url, "SELECT * FROM storage_deletion_request_queue")
        == before
    )


def test_snapshot_detects_migration_mismatch(migrated_database_url):
    result = run(
        runtime_check.collect(
            Settings(_env_file=None, database_url=migrated_database_url),
            expected_revision="missing-revision",
        )
    )
    assert "MIGRATION_MISMATCH" in result["issues"]


def test_unconfigured_does_not_guess_available():
    result = run(runtime_check.collect(Settings(_env_file=None, database_url=None)))
    assert result["issues"] == ["DATABASE_NOT_CONFIGURED"]
    assert result["status"] == "attention"


def test_database_failure_does_not_expose_connection(monkeypatch):
    async def fail(*args):
        raise OSError("postgresql://secret-password@private-host/db")

    monkeypatch.setattr(runtime_check, "database_snapshot", fail)
    result = run(
        runtime_check.collect(
            Settings(
                _env_file=None,
                database_url="postgresql://secret-password@private-host/db",
            )
        )
    )
    assert result["issues"] == ["DATABASE_INSPECTION_FAILED"]
    assert "secret-password" not in json.dumps(result)
    assert "private-host" not in json.dumps(result)


@pytest.mark.parametrize("status", [200, 302, 503])
def test_stt_probe_does_not_submit_audio_or_follow_redirects(status):
    calls = []

    def reply(request):
        calls.append((request.method, request.url.path))
        return httpx.Response(
            status, json={"status": "ok"}, headers={"Location": "https://other.invalid"}
        )

    result = run(
        runtime_check.probe_stt(
            "http://synthetic-stt", transport=httpx.MockTransport(reply)
        )
    )
    assert result == {"reachable": status == 200, "httpStatus": status}
    assert calls == [("GET", "/health/live")]


def test_stt_timeout_is_reported_without_url():
    def fail(request):
        raise httpx.ReadTimeout("sensitive endpoint", request=request)

    result = run(
        runtime_check.probe_stt(
            "http://synthetic-stt", transport=httpx.MockTransport(fail)
        )
    )
    assert result == {"reachable": False, "httpStatus": None}


@pytest.mark.parametrize("url", ["http://user:secret@stt", "http://stt?key=secret", "http://stt#secret", "file:///secret"])
def test_stt_probe_rejects_embedded_credentials(url):
    def fail(request):
        pytest.fail("must not send credentials")
    assert run(runtime_check.probe_stt(url, transport=httpx.MockTransport(fail))) == {
        "reachable": False, "httpStatus": None,
    }


def test_worker_and_primary_backup_stt_status_are_independent(monkeypatch):
    async def workers(targets):
        assert targets == ["speech=synthetic-worker"]
        return {"speech": {"state": "exited", "running": False, "restartCount": 12,
                           "processingVerified": False}}
    async def stt(url):
        return {"reachable": url == "http://backup", "httpStatus": 200 if url == "http://backup" else None}
    monkeypatch.setattr(runtime_check, "inspect_workers", workers)
    monkeypatch.setattr(runtime_check, "probe_stt", stt)
    result = run(runtime_check.collect(Settings(_env_file=None), check_stt=True,
                                       backup_stt_url="http://backup", worker_targets=["speech=synthetic-worker"]))
    assert result["workerProcessState"] == "attention"
    assert result["backupSttLiveness"]["reachable"]
    assert not result["sttLiveness"]["reachable"] and not result["sttAnalysisVerified"]
    assert "PRIMARY_STT_UNREACHABLE" in result["issues"]
    assert "SPEECH_WORKER_NOT_RUNNING_OR_UNINSPECTED" in result["issues"]


@pytest.mark.parametrize("key,configured", [("", False), ("  ", False), ("synthetic-secret", True)])
def test_ml_check_never_calls_provider_or_reports_unverified_quota(monkeypatch, key, configured):
    monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **k: pytest.fail("no provider call"))
    result = run(runtime_check.collect(Settings(_env_file=None, ml_api_key=key), check_ml=True))
    assert result["mlApi"]["keyConfigured"] is configured
    assert result["mlApi"]["authentication"] == "not_checked"
    assert result["mlApi"]["remainingQuota"] == "not_checked"
    assert result["mlApi"]["generationVerified"] is False
    assert "synthetic-secret" not in json.dumps(result)


def test_invalid_stt_port_is_safe_error():
    assert run(runtime_check.probe_stt("http://synthetic-stt:not-a-port")) == {
        "reachable": False, "httpStatus": None,
    }


def test_missing_control_row_is_not_reported_as_ready(migrated_database_url):
    query(migrated_database_url, "DELETE FROM deployment_control RETURNING singleton")
    result = run(runtime_check.collect(Settings(_env_file=None, database_url=migrated_database_url)))
    assert result["status"] == "attention"
    assert result["issues"] == ["DATABASE_INSPECTION_FAILED"]
