import argparse
import hashlib
import json
import os
from urllib.parse import unquote, urlsplit

import pytest

from scripts import verify_database_backup as backup
from scripts.verify_database_backup import safe_name, verify_backup
from tests.card_fixtures import query


@pytest.mark.parametrize("name", ["--help", "db;drop", "../db", "", "a\nb"])
def test_backup_tool_rejects_option_and_shell_like_names(name):
    with pytest.raises(argparse.ArgumentTypeError):
        safe_name(name)


@pytest.mark.parametrize("cleanup_fails", [False, True])
def test_restore_failure_keeps_archive_and_failure_manifest(
    tmp_path, monkeypatch, cleanup_fails
):
    label = ""

    def fake_command(args, **kwargs):
        nonlocal label
        if "pg_dump" in args:
            kwargs["stdout"].write(b"synthetic-dump")
        elif "run" in args:
            label = args[args.index("--label") + 1].split("=", 1)[1]
        elif "pg_restore" in args:
            raise backup.BackupError("COMMAND_FAILED")
        elif "inspect" in args:
            return label.encode()
        elif "rm" in args and cleanup_fails:
            raise backup.BackupError("COMMAND_FAILED")
        return b""

    monkeypatch.setattr(backup, "sql", lambda *args: "170000")
    monkeypatch.setattr(backup, "command", fake_command)
    with pytest.raises(backup.BackupError):
        verify_backup(
            source_container="synthetic-db",
            source_database="synthetic",
            source_user="synthetic",
            backup_dir=tmp_path,
        )
    manifest = json.loads(next(tmp_path.glob("*.json")).read_text(encoding="utf-8"))
    assert manifest["restoreVerified"] is False
    assert manifest["restoredContainerRemoved"] is not cleanup_fails
    assert (tmp_path / manifest["archive"]).read_bytes() == b"synthetic-dump"


@pytest.mark.skipif(
    not os.environ.get("SAELOG_BACKUP_TEST_CONTAINER"),
    reason="전용 로컬 Docker DB 지정 필요",
)
def test_backup_can_be_restored_into_an_isolated_container(
    migrated_database_url, tmp_path
):
    """실행자가 지정한 전용 Docker DB와 fixture의 일회성 DB만 사용한다."""
    parts = urlsplit(
        migrated_database_url.replace("postgresql+psycopg://", "postgresql://", 1)
    )
    query(
        migrated_database_url,
        "INSERT INTO users (google_sub) VALUES ('synthetic-backup-user') RETURNING user_id",
    )
    before = query(migrated_database_url, "SELECT * FROM users")
    result = verify_backup(
        source_container=os.environ["SAELOG_BACKUP_TEST_CONTAINER"],
        source_database=parts.path.lstrip("/"),
        source_user=unquote(parts.username),
        backup_dir=tmp_path,
    )
    assert result["restoreVerified"] is True
    assert result["restoredRowCounts"]["users"] == 1
    assert result["restoredContainerRemoved"] is True
    assert result["restoredRevisions"] == [
        query(migrated_database_url, "SELECT version_num FROM alembic_version")[0][
            "version_num"
        ]
    ]
    assert query(migrated_database_url, "SELECT * FROM users") == before
    with (tmp_path / result["archive"]).open("rb") as data:
        assert hashlib.file_digest(data, "sha256").hexdigest() == result["sha256"]
    assert len(list(tmp_path.glob("*.json"))) == 1
    assert "synthetic-backup-user" not in json.dumps(result)
