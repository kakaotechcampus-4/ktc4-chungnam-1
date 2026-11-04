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
