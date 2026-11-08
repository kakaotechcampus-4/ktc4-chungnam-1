"""오래된 백업 정리(`scripts/prune_database_backups.py`). 합성 파일만 쓴다."""

import importlib.util
import json
import shlex
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "prune_database_backups.py"
spec = importlib.util.spec_from_file_location("prune_database_backups", SCRIPT)
prune = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = prune  # dataclass가 모듈을 찾을 수 있게 등록
spec.loader.exec_module(prune)

NOW = datetime(2026, 11, 4, tzinfo=UTC)


UNIT = Path(__file__).resolve().parents[1] / "ops" / "backup-prune" / "saerok-backup-prune.service"


def _backup(directory: Path, name: str, days_ago: int, verified: bool = True, now: datetime = NOW) -> None:
    (directory / f"saelog-{name}.dump").write_bytes(b"synthetic")
    (directory / f"saelog-{name}.json").write_text(json.dumps({
        "createdAtUtc": (now - timedelta(days=days_ago)).isoformat(),
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


def test_default_rule_drops_backups_older_than_fourteen_days(tmp_path, capsys):
    # 2026-11-09 PM 결정: 14일 보관. main은 실제 시계를 쓰므로 지금 기준으로 만든다.
    now = datetime.now(UTC)
    for name, days in [("d1", 1), ("d13", 13), ("d15", 15), ("d30", 30)]:
        _backup(tmp_path, name, days, now=now)
    assert prune.main(["--backup-dir", str(tmp_path)]) == 0
    listed = json.loads(capsys.readouterr().out)
    assert listed["applied"] is False
    assert (listed["keep"], listed["olderThanDays"]) == (1, 14)
    assert sorted(b["name"] for b in listed["wouldRemove"]) == ["saelog-d15", "saelog-d30"]


def test_newest_verified_backup_survives_past_fourteen_days(tmp_path):
    # 배포가 14일 넘게 없어도 복원 확인된 가장 최근 백업 1개는 남는다. 실패한 새 백업은 세지 않는다.
    _backup(tmp_path, "new-bad", 2, verified=False)
    _backup(tmp_path, "old-ok", 20)
    _backup(tmp_path, "older-ok", 25)
    _backup(tmp_path, "old-bad", 16, verified=False)
    doomed = prune.plan(prune.scan(tmp_path), keep=1, older_than=timedelta(days=14), now=NOW)
    assert sorted(b.stem for b in doomed) == ["saelog-old-bad", "saelog-older-ok"]


def test_missing_backup_dir_fails_instead_of_reporting_nothing(tmp_path, capsys):
    # 경로를 잘못 넣은 timer가 "지울 것 없음"으로 계속 성공하지 않게 한다.
    assert prune.main(["--backup-dir", str(tmp_path / "missing")]) == 2
    assert "BACKUP_DIR_NOT_FOUND" in capsys.readouterr().out
    (tmp_path / "file").write_text("x", encoding="utf-8")
    assert prune.main(["--backup-dir", str(tmp_path / "file")]) == 2
    assert "BACKUP_DIR_NOT_FOUND" in capsys.readouterr().out


def _unit_exec_args() -> list[str]:
    lines = [line for line in UNIT.read_text(encoding="utf-8").splitlines() if line.startswith("ExecStart=")]
    assert len(lines) == 1
    return shlex.split(lines[0].removeprefix("ExecStart="))


def test_systemd_unit_applies_the_fourteen_day_rule(tmp_path):
    args = _unit_exec_args()
    assert args[:3] == ["/usr/bin/python3", "-I", "/opt/saerok-backup-prune/prune_database_backups.py"]
    options = args[3:]
    assert options[options.index("--keep") + 1] == "1"
    assert options[options.index("--older-than-days") + 1] == "14"
    assert "--apply" in options
    # 쓰기는 정리 대상 폴더에만 허용한다.
    backup_dir = options[options.index("--backup-dir") + 1]
    assert f"ReadWritePaths={backup_dir}" in UNIT.read_text(encoding="utf-8").splitlines()

    # 같은 인수를 합성 폴더에 그대로 실행한다.
    now = datetime.now(UTC)
    _backup(tmp_path, "d13", 13, now=now)
    _backup(tmp_path, "d15", 15, now=now)
    _backup(tmp_path, "d40", 40, now=now)
    options[options.index("--backup-dir") + 1] = str(tmp_path)
    assert prune.main(options) == 0
    assert sorted(p.name for p in tmp_path.iterdir()) == ["saelog-d13.dump", "saelog-d13.json"]
