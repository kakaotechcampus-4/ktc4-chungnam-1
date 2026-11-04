import json

import pytest

from scripts import capture_release


def test_release_capture_does_not_read_environment_or_logs(tmp_path, monkeypatch):
    compose = tmp_path / "compose.yml"
    compose.write_text("services: {}\n", encoding="utf-8")
    commands = []

    def fake_run(args):
        commands.append(args)
        if "rev-parse" in args:
            return "a" * 40
        if "status" in args:
            return " M changed"
        return json.dumps(
            {
                "imageId": "sha256:synthetic",
                "imageTag": "synthetic:v1",
                "status": "running",
                "restartCount": 2,
                "service": "api",
                "sourceRevision": "b" * 40,
            }
        )

    monkeypatch.setattr(capture_release, "run", fake_run)
    result = capture_release.capture(
        repo=tmp_path, containers=["synthetic-api"], compose_files=[compose]
    )
    assert result["worktreeDirty"] is True
    assert result["gitCommit"] != result["containers"][0]["sourceRevision"]
    assert result["composeFiles"][0]["isSymlink"] is False
    docker = next(command for command in commands if command[0] == "docker")
    assert docker[1:3] == ["inspect", "--format"]
    assert ".Env" not in docker[3] and "logs" not in docker


def test_release_capture_rejects_option_as_container(tmp_path, monkeypatch):
    monkeypatch.setattr(capture_release, "run", lambda args: "a" * 40)
    with pytest.raises(ValueError, match="INVALID_CONTAINER_NAME"):
        capture_release.capture(repo=tmp_path, containers=["--help"], compose_files=[])
