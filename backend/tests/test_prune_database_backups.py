"""오래된 백업 정리(`scripts/prune_database_backups.py`). 합성 파일만 쓴다."""

import importlib.util
import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "prune_database_backups.py"
spec = importlib.util.spec_from_file_location("prune_database_backups", SCRIPT)
prune = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = prune  # dataclass가 모듈을 찾을 수 있게 등록
spec.loader.exec_module(prune)

NOW = datetime(2026, 11, 4, tzinfo=UTC)


def _backup(directory: Path, name: str, days_ago: int, verified: bool = True) -> None:
    (directory / f"saelog-{name}.dump").write_bytes(b"synthetic")
    (directory / f"saelog-{name}.json").write_text(json.dumps({
        "createdAtUtc": (NOW - timedelta(days=days_ago)).isoformat(),
        "restoreVerified": verified,
    }), encoding="utf-8")


def test_keeps_recent_verified_backups_and_drops_old_ones(tmp_path):
    for i, days in enumerate([1, 3, 10, 20, 30]):
        _backup(tmp_path, f"b{i}", days)
    doomed = prune.plan(prune.scan(tmp_path), keep=2, older_than=timedelta(days=7), now=NOW)
    assert sorted(b.stem for b in doomed) == ["saelog-b2", "saelog-b3", "saelog-b4"]


def test_never_removes_the_last_verified_backups_even_if_old(tmp_path):
    _backup(tmp_path, "old-ok", 40)
    _backup(tmp_path, "older-ok", 50)
    doomed = prune.plan(prune.scan(tmp_path), keep=2, older_than=timedelta(days=7), now=NOW)
    assert doomed == []


def test_unverified_backups_do_not_count_toward_keep(tmp_path):
    _backup(tmp_path, "new-bad", 1, verified=False)
    _backup(tmp_path, "old-ok", 30)
    _backup(tmp_path, "older-bad", 40, verified=False)
    doomed = prune.plan(prune.scan(tmp_path), keep=1, older_than=timedelta(days=7), now=NOW)
    assert [b.stem for b in doomed] == ["saelog-older-bad"]


def test_dry_run_lists_and_apply_removes_both_files(tmp_path, capsys):
    _backup(tmp_path, "keep", 1)
    old = NOW - timedelta(days=30)
    (tmp_path / "saelog-old.dump").write_bytes(b"synthetic")
    (tmp_path / "saelog-old.json").write_text(json.dumps({"createdAtUtc": old.isoformat(),
                                                          "restoreVerified": True}), encoding="utf-8")
    args = ["--backup-dir", str(tmp_path), "--keep", "1", "--older-than-days", "7"]
    assert prune.main(args) == 0
    listed = json.loads(capsys.readouterr().out)
    assert listed["applied"] is False and [b["name"] for b in listed["wouldRemove"]] == ["saelog-old"]
    assert (tmp_path / "saelog-old.dump").exists()

    assert prune.main(args + ["--apply"]) == 0
    assert not (tmp_path / "saelog-old.dump").exists() and not (tmp_path / "saelog-old.json").exists()
    assert (tmp_path / "saelog-keep.dump").exists()


def test_rejects_unsafe_retention(tmp_path, capsys):
    assert prune.main(["--backup-dir", str(tmp_path), "--keep", "0"]) == 2
    assert "INVALID_RETENTION" in capsys.readouterr().out
