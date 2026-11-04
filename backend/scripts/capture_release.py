"""지정한 컨테이너와 저장소의 배포 근거만 읽는다. 환경 변수와 로그는 읽지 않는다."""

import argparse
import hashlib
import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path


def run(args):
    result = subprocess.run(
        args, capture_output=True, text=True, timeout=15, check=False
    )
    if result.returncode:
        raise RuntimeError("INSPECTION_FAILED")
    return result.stdout.strip()


def capture(*, repo: Path, containers: list[str], compose_files: list[Path]) -> dict:
    root = repo.resolve(strict=True)
    result = {
        "capturedAtUtc": datetime.now(UTC).isoformat(),
        "readOnly": True,
        "gitCommit": run(["git", "-C", str(root), "rev-parse", "HEAD"]),
        "worktreeDirty": bool(run(["git", "-C", str(root), "status", "--porcelain"])),
        "containers": [],
        "composeFiles": [],
    }
    # 전체 inspect에는 환경 변수 값이 있다. 필요한 필드만 Docker에 요청한다.
    template = (
        '{"imageId":{{json .Image}},"imageTag":{{json .Config.Image}},'
        '"status":{{json .State.Status}},"restartCount":{{json .RestartCount}},'
        '"service":{{json (index .Config.Labels "com.docker.compose.service")}},'
        '"sourceRevision":{{json (index .Config.Labels "org.opencontainers.image.revision")}}}'
    )
    for container in containers:
        if not container or container.startswith("-"):
            raise ValueError("INVALID_CONTAINER_NAME")
        item = json.loads(run(["docker", "inspect", "--format", template, container]))
        result["containers"].append(item)
    for path in compose_files:
        actual = path.resolve(strict=True)
        with actual.open("rb") as content:
            digest = hashlib.file_digest(content, "sha256").hexdigest()
        result["composeFiles"].append(
            {
                "name": path.name,
                "isSymlink": path.is_symlink(),
                "resolvedName": actual.name,
                "sha256": digest,
            }
        )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--container", action="append", required=True)
    parser.add_argument("--compose-file", action="append", type=Path, default=[])
    args = parser.parse_args()
    try:
        result = capture(
            repo=args.repo, containers=args.container, compose_files=args.compose_file
        )
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        print(json.dumps({"readOnly": True, "error": "RELEASE_INSPECTION_FAILED"}))
        raise SystemExit(1) from None
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
