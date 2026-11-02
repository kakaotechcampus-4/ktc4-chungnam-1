"""PostgreSQL 17 백업을 새 격리 컨테이너에 복원한다. 기존 DB에는 쓰지 않는다.

백업에는 개인정보가 포함될 수 있다. 운영 실행은 별도 승인 후 보호된 경로에서 한다.
출력에는 비밀번호, 원문과 객체 키를 남기지 않는다.
"""

import argparse
import hashlib
import json
import os
import re
import secrets
import subprocess
import time
from datetime import UTC, datetime
from pathlib import Path


class BackupError(RuntimeError):
    pass


def command(args, *, stdin=None, stdout=subprocess.PIPE, timeout=120):
    try:
        completed = subprocess.run(
            args,
            stdin=stdin,
            stdout=stdout,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise BackupError("COMMAND_UNAVAILABLE_OR_TIMEOUT") from error
    if completed.returncode:
        # stderr에는 DB 주소와 인증 관련 정보가 있을 수 있다.
        raise BackupError("COMMAND_FAILED")
    return completed.stdout


def safe_name(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", value):
        raise argparse.ArgumentTypeError("컨테이너와 DB 이름 형식을 확인해주세요.")
    return value


def sql(container, user, database, statement):
    return (
        command(
            [
                "docker",
                "exec",
                container,
                "psql",
                "-X",
                "-A",
                "-t",
                "-v",
                "ON_ERROR_STOP=1",
                "-U",
                user,
                "-d",
                database,
                "-c",
                statement,
            ]
        )
        .decode("utf-8")
        .strip()
    )


def verify_backup(
    *, source_container, source_database, source_user, backup_dir, image="postgres:17"
):
    for value in (source_container, source_database, source_user):
        safe_name(value)
    # 다른 버전으로 복원하는 것을 자동 migration으로 간주하지 않는다.
    server_version = int(
        sql(source_container, source_user, source_database, "SHOW server_version_num")
    )
    if server_version // 10000 != 17:
        raise BackupError("POSTGRES_17_REQUIRED")
    backup_dir = Path(backup_dir).resolve()
    backup_dir.mkdir(parents=True, exist_ok=True)
    run_id = secrets.token_hex(8)
    archive = backup_dir / f"saelog-{run_id}.dump"
    manifest_path = backup_dir / f"saelog-{run_id}.json"
    restore_container = f"saelog-restore-check-{run_id}"
    started = False
    record = {
        "createdAtUtc": datetime.now(UTC).isoformat(),
        "sourceMajor": 17,
        "archive": archive.name,
        "restoreVerified": False,
        "sourceModified": False,
        "restoredContainerRemoved": False,
        "stage": "backup",
    }
    try:
        with os.fdopen(
            os.open(archive, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb"
        ) as output:
            command(
                [
                    "docker",
                    "exec",
                    source_container,
                    "pg_dump",
                    "-U",
                    source_user,
                    "-d",
                    source_database,
                    "--format=custom",
                    "--no-owner",
                    "--no-acl",
                ],
                stdout=output,
            )
        if archive.stat().st_size == 0:
            raise BackupError("EMPTY_ARCHIVE")
        with archive.open("rb") as data:
            record["sha256"] = hashlib.file_digest(data, "sha256").hexdigest()
        record["sizeBytes"] = archive.stat().st_size
        # run이 컨테이너 생성 뒤 실패한 경우도 이름과 라벨을 확인해 정리 대상으로 남긴다.
        started = True
        record["stage"] = "start_isolated_database"
        command(
            [
                "docker",
                "run",
                "--detach",
                "--name",
                restore_container,
                "--label",
                f"saelog.restore-check={run_id}",
                "--network",
                "none",
                "--tmpfs",
                "/var/lib/postgresql/data",
                "--env",
                "POSTGRES_USER=restore_check",
                "--env",
                "POSTGRES_DB=restore_check",
                "--env",
                f"POSTGRES_PASSWORD={secrets.token_urlsafe(32)}",
                image,
            ]
        )
        for _ in range(60):
            try:
                command(
                    [
                        "docker",
                        "exec",
                        restore_container,
                        "pg_isready",
                        # Initialization uses a socket-only temporary server, which
                        # restarts before the final server accepts TCP connections.
                        "-h",
                        "127.0.0.1",
                        "-U",
                        "restore_check",
                        "-d",
                        "restore_check",
                    ],
                    timeout=3,
                )
                break
            except BackupError:
                time.sleep(0.5)
        else:
            raise BackupError("RESTORE_DATABASE_NOT_READY")
        with archive.open("rb") as data:
            record["stage"] = "restore"
            command(
                [
                    "docker",
                    "exec",
                    "-i",
                    restore_container,
                    "pg_restore",
                    "--exit-on-error",
                    "--no-owner",
                    "--no-acl",
                    "-U",
                    "restore_check",
                    "-d",
                    "restore_check",
                ],
                stdin=data,
            )
        # 복원 대상은 이 실행에서 새로 만든 컨테이너뿐이다. 기존 DB에 --clean을 쓰지 않는다.
        record["stage"] = "verify_restored_schema"
        revision = sql(
            restore_container,
            "restore_check",
            "restore_check",
            "SELECT version_num FROM alembic_version ORDER BY version_num",
        )
        counts = {}
        for table in (
            "users",
            "profiles",
            "card_sets",
            "visit_sessions",
            "life_facts",
            "speech_analysis_jobs",
            "photos",
            "storage_deletion_request_queue",
        ):
            counts[table] = int(
                sql(
                    restore_container,
                    "restore_check",
                    "restore_check",
                    f"SELECT count(*) FROM {table}",
                )
            )
        record.update(
            restoreVerified=True,
            restoredRevisions=revision.splitlines(),
            restoredRowCounts=counts,
            stage="complete",
        )
    except BackupError as error:
        record["errorCode"] = str(error)
        raise
    finally:
        cleanup_error = None
        try:
            if started:
                label = (
                    command(
                        [
                            "docker",
                            "inspect",
                            "--format",
                            '{{index .Config.Labels "saelog.restore-check"}}',
                            restore_container,
                        ]
                    )
                    .decode()
                    .strip()
                )
                if label != run_id:
                    raise BackupError("RESTORE_CONTAINER_OWNERSHIP_MISMATCH")
                command(["docker", "rm", "--force", restore_container])
                record["restoredContainerRemoved"] = True
        except BackupError as error:
            cleanup_error = error
            record["cleanupError"] = str(error)
        # 실패해도 덤프를 지우지 않는다. 실패한 복원을 성공으로 기록하지 않는다.
        with os.fdopen(
            os.open(manifest_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600),
            "w",
            encoding="utf-8",
        ) as output:
            json.dump(record, output, ensure_ascii=False, indent=2)
        if cleanup_error:
            raise cleanup_error
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-container", required=True, type=safe_name)
    parser.add_argument("--source-database", required=True, type=safe_name)
    parser.add_argument("--source-user", required=True, type=safe_name)
    parser.add_argument("--backup-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = verify_backup(**vars(args))
    except (BackupError, ValueError, OSError) as error:
        print(
            json.dumps(
                {
                    "restoreVerified": False,
                    "error": str(error)
                    if isinstance(error, BackupError)
                    else "BACKUP_CHECK_FAILED",
                }
            )
        )
        raise SystemExit(1) from None
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
