"""`verify_database_backup.py`가 만든 백업 중 오래된 것을 정리한다.

백업 파일(`saelog-*.dump`)과 같은 이름의 기록(`saelog-*.json`)을 한 쌍으로 본다. 기록에
`restoreVerified: true`가 있는 백업만 "복원 확인된 백업"으로 센다.

- 최근 복원 확인된 백업 `--keep`개는 날짜와 상관없이 남긴다.
- 그 밖의 백업 중 `--older-than-days`일보다 오래된 것만 지운다.
- 기본은 지울 목록만 보여 준다(`--apply`를 줘야 실제로 지운다).
- 출력에는 파일 이름과 만든 시각만 남긴다. DB 내용과 경로 밖 정보는 읽지 않는다.

백업에는 개인정보가 있을 수 있다. 보관 기한과 삭제 시점은 `docs/legal/README.md`의 백업 항목을 따른다.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path


@dataclass(frozen=True)
class Backup:
    stem: str
    created: datetime
    verified: bool
    files: tuple[Path, ...]


def scan(directory: Path) -> list[Backup]:
    backups = []
    for dump in sorted(directory.glob("saelog-*.dump")):
        record = dump.with_suffix(".json")
        created, verified = None, False
        try:
            data = json.loads(record.read_text(encoding="utf-8"))
            created = datetime.fromisoformat(data["createdAtUtc"])
            verified = data.get("restoreVerified") is True
        except (OSError, ValueError, KeyError, TypeError):
            pass
        if created is None:
            created = datetime.fromtimestamp(dump.stat().st_mtime, tz=UTC)
        files = (dump, record) if record.exists() else (dump,)
        backups.append(Backup(dump.stem, created, verified, files))
    return sorted(backups, key=lambda b: b.created, reverse=True)


def plan(backups: list[Backup], *, keep: int, older_than: timedelta, now: datetime) -> list[Backup]:
    """지울 백업 목록. 최근 복원 확인된 keep개와 기한 안의 백업은 남긴다."""
    protected = {b.stem for b in [b for b in backups if b.verified][:keep]}
    return [b for b in backups if b.stem not in protected and now - b.created > older_than]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--backup-dir", required=True, type=Path)
    parser.add_argument("--keep", type=int, default=7, help="날짜와 상관없이 남길 최근 복원 확인 백업 수")
    parser.add_argument("--older-than-days", type=int, default=7)
    parser.add_argument("--apply", action="store_true", help="실제로 지운다. 없으면 목록만 보여 준다")
    args = parser.parse_args(argv)
    if args.keep < 1 or args.older_than_days < 1:
        print(json.dumps({"error": "INVALID_RETENTION"}))
        return 2
    backups = scan(args.backup_dir)
    doomed = plan(backups, keep=args.keep, older_than=timedelta(days=args.older_than_days),
                  now=datetime.now(UTC))
    if args.apply:
        for backup in doomed:
            for path in backup.files:
                path.unlink(missing_ok=True)
    print(json.dumps({
        "applied": args.apply,
        "found": len(backups),
        "verifiedFound": sum(b.verified for b in backups),
        "removed" if args.apply else "wouldRemove": [
            {"name": b.stem, "createdAtUtc": b.created.isoformat(), "verified": b.verified} for b in doomed
        ],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
