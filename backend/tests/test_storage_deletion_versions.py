"""버전 삭제도 대기열, 실제 DB 참조와 삭제 확인을 거친다. S3는 합성 대역이다."""

from copy import deepcopy
from pathlib import Path
from uuid import uuid4

import pytest

from app.services.storage_deletion import DeletionError, S3DeleteBackend
from tests.support import run
from tests.test_speech_job_repository import _Db
from tests.test_storage_deletion import TARGETS, S3Client, process, queued


class VersionClient(S3Client):
    def __init__(self, key, *, version="Enabled", head_status=404):
        super().__init__(version=version, head_status=head_status)
        self.rows = {
            "Versions": [
                {"Key": key, "VersionId": "old"},
                {"Key": key, "VersionId": "new"},
            ],
            "DeleteMarkers": [{"Key": key, "VersionId": "marker"}],
        }
        self.version_deletes = []
        self.fail = False
        self.omit_confirmation = False
        self.reappear = False
        self.pages = None
        self.list_calls = []
        self.mfa = False

    def get_bucket_versioning(self, **kw):
        return {
            **super().get_bucket_versioning(**kw),
            "MFADelete": "Enabled" if self.mfa else "Disabled",
        }

    def list_object_versions(self, **kw):
        self.list_calls.append(kw)
        if self.pages:
            return self.pages.pop(0)
        rows = deepcopy(self.rows)
        if self.reappear and self.version_deletes:
            rows["Versions"].append({"Key": kw["Prefix"], "VersionId": "concurrent"})
        return rows

    def delete_objects(self, **kw):
        self.version_deletes.append(kw)
        requested = kw["Delete"]["Objects"]
        if self.fail:
            # 응답 일부만 성공해도 다음 실행에서 남은 버전을 다시 지울 수 있다.
            first = requested[0]
            for field in self.rows:
                self.rows[field] = [r for r in self.rows[field] if r != first]
            return {"Deleted": [first], "Errors": [{"Code": "AccessDenied"}]}
        for field in self.rows:
            self.rows[field] = [r for r in self.rows[field] if r not in requested]
        return {"Deleted": [] if self.omit_confirmation else requested}


def adapter(client, allow=True):
    return S3DeleteBackend(
        client_factory=lambda _: client, allow_versioned_photos=allow
    )


@pytest.mark.parametrize("state", ["Enabled", "Suspended"])
def test_explicit_photo_opt_in_deletes_exact_versions_then_markers(state):
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key, version=state)
    other = {"Key": key + ".other", "VersionId": "untouched"}
    client.rows["Versions"].append(other)
    run(adapter(client).delete_and_confirm(TARGETS[1], key))
    assert client.deletes == []  # 버전 ID 없는 DELETE는 호출하지 않는다.
    assert client.rows["Versions"] == [other]
    assert [r["VersionId"] for r in client.version_deletes[0]["Delete"]["Objects"]] == [
        "old",
        "new",
    ]
    assert client.version_deletes[1]["Delete"]["Objects"] == [
        {"Key": key, "VersionId": "marker"}
    ]
    assert all("BypassGovernanceRetention" not in c for c in client.version_deletes)


def test_photo_opt_in_does_not_allow_versioned_audio_or_default_photo():
    key = f"photos/{uuid4()}.png"
    for target, allow in [(TARGETS[0], True), (TARGETS[1], False)]:
        client = VersionClient(key)
        with pytest.raises(DeletionError, match="VERSIONED_BUCKET_REQUIRES_REVIEW"):
            run(adapter(client, allow).delete_and_confirm(target, key))
        assert client.version_deletes == []


@pytest.mark.parametrize(
    "invalid", ["photos/not-uuid.jpg", "photos/../secret.jpg", "other/file.jpg"]
)
def test_versioned_adapter_also_rejects_invalid_keys(invalid):
    client = VersionClient(invalid)
    with pytest.raises(DeletionError, match="UNKNOWN_OBJECT_ROUTE"):
        run(adapter(client).delete_and_confirm(TARGETS[1], invalid))
    assert not client.version_deletes


def test_mfa_delete_is_not_bypassed():
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key)
    client.mfa = True
    with pytest.raises(DeletionError, match="MFA_DELETE_REQUIRES_REVIEW"):
        run(adapter(client).delete_and_confirm(TARGETS[1], key))
    assert not client.version_deletes


@pytest.mark.parametrize(
    "case", ["partial", "missing", "reappeared", "head403", "head200"]
)
def test_incomplete_delete_never_succeeds(case):
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(
        key, head_status={"head403": 403, "head200": 200}.get(case, 404)
    )
    client.fail = case == "partial"
    client.omit_confirmation = case == "missing"
    client.reappear = case == "reappeared"
    with pytest.raises(DeletionError):
        run(adapter(client).delete_and_confirm(TARGETS[1], key))
    if case in ("partial", "missing"):
        assert client.rows["DeleteMarkers"]  # 실패하면 삭제 표시는 그대로 남긴다.


def test_empty_version_list_and_head_404_is_idempotent():
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key)
    client.rows = {"Versions": [], "DeleteMarkers": []}
    run(adapter(client).delete_and_confirm(TARGETS[1], key))
    assert not client.version_deletes


def test_pagination_and_null_version_id():
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key)
    client.rows = {"Versions": [{"Key": key, "VersionId": "null"}], "DeleteMarkers": []}
    client.pages = [
        {
            "Versions": [],
            "IsTruncated": True,
            "NextKeyMarker": key,
            "NextVersionIdMarker": "null",
        }
    ]
    run(adapter(client).delete_and_confirm(TARGETS[1], key))
    assert client.list_calls[1]["VersionIdMarker"] == "null"
    assert client.version_deletes[0]["Delete"]["Objects"] == [
        {"Key": key, "VersionId": "null"}
    ]


@pytest.mark.parametrize(
    "bad_page",
    [
        {"IsTruncated": True},
        {"Versions": [{"Key": "KEY"}]},
        {"Versions": [{"Key": "KEY", "VersionId": str(n)} for n in range(1001)]},
    ],
)
def test_incomplete_or_oversized_inventory_aborts_before_delete(bad_page):
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key)
    page = deepcopy(bad_page)
    for row in page.get("Versions", []):
        row["Key"] = key
    client.pages = [page]
    with pytest.raises(DeletionError):
        run(adapter(client).delete_and_confirm(TARGETS[1], key))
    assert not client.version_deletes


def test_live_photo_survives_then_profile_delete_cleans_all_versions(
    migrated_database_url,
):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    profile = db.execute(
        "SELECT profile_id FROM visit_sessions WHERE session_id=%s", (session,)
    )[0]["profile_id"]
    key = f"photos/{uuid4()}.jpg"
    client = VersionClient(key)
    db.execute(
        "INSERT INTO photos (profile_id,s3_object_key) VALUES (%s,%s)", (profile, key)
    )
    queued(db, key)
    assert process(migrated_database_url, adapter(client), apply=True)["errors"] == {
        "LIVE_REFERENCE": 1
    }
    assert not client.version_deletes
    db.execute("DELETE FROM profiles WHERE profile_id=%s", (profile,))
    assert process(migrated_database_url, adapter(client), apply=True)["deleted"] == 1
    assert not any(client.rows.values())
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []


def test_partial_version_failure_keeps_queue_and_rerun_completes(migrated_database_url):
    db = _Db(migrated_database_url)
    key = f"photos/{uuid4()}.jpg"
    queued(db, key)
    client = VersionClient(key)
    client.fail = True
    assert process(migrated_database_url, adapter(client), apply=True)["errors"] == {
        "VERSION_DELETE_NOT_CONFIRMED": 1
    }
    assert len(db.execute("SELECT * FROM storage_deletion_request_queue")) == 1
    client.fail = False
    assert process(migrated_database_url, adapter(client), apply=True)["deleted"] == 1
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []


def test_timer_enqueues_expired_before_delete_and_uses_deployed_container():
    root = Path(__file__).resolve().parents[1] / "ops" / "storage-deletion"
    service = (root / "saerok-storage-deletion.service").read_text(encoding="utf-8")
    timer = (root / "saerok-storage-deletion.timer").read_text(encoding="utf-8")
    commands = [line for line in service.splitlines() if line.startswith("ExecStart=")]
    assert len(commands) == 2
    assert "--enqueue-safe-expired" in commands[0]
    assert "--apply --allow-versioned-photos --limit 100" in commands[1]
    assert all("exec -T api python -m app." in c for c in commands)
    assert "OnCalendar=*-*-* *:0/5:00" in timer and "Persistent=true" in timer
