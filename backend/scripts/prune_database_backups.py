"""`verify_database_backup.py`가 만든 백업 중 오래된 것을 정리한다.

백업 파일(`saelog-*.dump`)과 같은 이름의 기록(`saelog-*.json`)을 한 쌍으로 본다. 기록에
`restoreVerified: true`가 있는 백업만 "복원 확인된 백업"으로 센다.

- 최근 복원 확인된 백업 `--keep`개(기본 1)는 날짜와 상관없이 남긴다.
- 그 밖의 백업 중 `--older-than-days`일(기본 14)보다 오래된 것만 지운다.
- 기본은 지울 목록만 보여 준다(`--apply`를 줘야 실제로 지운다).
- 백업 폴더가 없거나, 폴더나 기록을 읽을 권한이 없으면 "지울 것 없음"으로 끝내지 않고 실패한다.
- 출력에는 파일 이름과 만든 시각만 남긴다. DB 내용과 경로 밖 정보는 읽지 않는다.

기본값은 2026-11-09 PM 결정(14일 보관)을 따른다. 운영 서버에서는 `ops/backup-prune/`의 systemd
timer가 하루 한 번 `--apply`로 실행한다. 설치와 확인은 `backend/docs/release-safety.md`에 있다.

백업에는 개인정보가 있을 수 있다. 보관 기한은 `docs/legal/README.md`의 "배포 DB 백업 보관"을 따른다.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

DEFAULT_KEEP = 1
DEFAULT_OLDER_THAN_DAYS = 14


@dataclass(frozen=True)
class Backup:
    stem: str
    created: datetime
    verified: bool
    files: tuple[Path, ...]


def scan(directory: Path) -> list[Backup]:
    """폴더나 기록을 읽을 권한이 없으면 PermissionError를 그대로 올린다."""
    backups = []
    # Path.glob은 읽을 수 없는 폴더를 빈 폴더처럼 넘긴다. 직접 열어서 권한 오류를 드러낸다.
    with os.scandir(directory) as entries:
        names = sorted(e.name for e in entries if e.name.startswith("saelog-") and e.name.endswith(".dump"))
    for dump in (directory / name for name in names):
        record = dump.with_suffix(".json")
        created, verified = None, False
        try:
            data = json.loads(record.read_text(encoding="utf-8"))
            created = datetime.fromisoformat(data["createdAtUtc"])
            verified = data.get("restoreVerified") is True
        except PermissionError:
            # 기록을 못 읽은 백업을 "복원 확인 안 됨"으로 추측하면 지킬 백업을 지울 수 있다.
            raise
        except (OSError, ValueError, KeyError, TypeError):
            # 기록이 아직 없거나(백업 진행 중) 깨진 경우. 파일 시각으로 판단하고 복원 확인으로 세지 않는다.
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
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP,
                        help="날짜와 상관없이 남길 최근 복원 확인 백업 수")
    parser.add_argument("--older-than-days", type=int, default=DEFAULT_OLDER_THAN_DAYS,
                        help="이 일수보다 오래된 백업을 지운다")
    parser.add_argument("--apply", action="store_true", help="실제로 지운다. 없으면 목록만 보여 준다")
    args = parser.parse_args(argv)
    if args.keep < 1 or args.older_than_days < 1:
        print(json.dumps({"error": "INVALID_RETENTION"}))
        return 2
    try:
        if not args.backup_dir.is_dir():
            print(json.dumps({"error": "BACKUP_DIR_NOT_FOUND"}))
            return 2
        backups = scan(args.backup_dir)
    except PermissionError:
        print(json.dumps({"error": "BACKUP_UNREADABLE"}))
        return 2
    doomed = plan(backups, keep=args.keep, older_than=timedelta(days=args.older_than_days),
                  now=datetime.now(UTC))
    if args.apply:
        for backup in doomed:
            for path in backup.files:
                path.unlink(missing_ok=True)
    print(json.dumps({
        "applied": args.apply,
        "keep": args.keep,
        "olderThanDays": args.older_than_days,
        "found": len(backups),
        "verifiedFound": sum(b.verified for b in backups),
        "removed" if args.apply else "wouldRemove": [
            {"name": b.stem, "createdAtUtc": b.created.isoformat(), "verified": b.verified} for b in doomed
        ],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
