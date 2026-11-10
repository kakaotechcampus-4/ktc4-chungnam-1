"""실제 PostgreSQL, 합성 S3 대역만 사용한다. 운영 파일은 삭제하지 않는다."""

from uuid import uuid4

import pytest
from botocore.exceptions import ClientError

from alembic import command
from app.core.database import connect
from app.services.storage_deletion import (
    LOCK_KEY,
    LOCK_NAMESPACE,
    DeletionError,
    DeletionTarget,
    S3DeleteBackend,
    process_deletions,
    resolve_target,
    validate_targets,
)
from tests.support import run
from tests.test_speech_job_repository import TRANSCRIPT, _accept, _Db

TARGETS = (
    DeletionTarget("audio", "synthetic-audio", "ap-northeast-2", "temporary/speech"),
    DeletionTarget("photo", "synthetic-photos", "ap-northeast-2", "photos"),
)


class FakeDelete:
    def __init__(self, fail=False):
        self.calls = []
        self.fail = fail

    async def delete_and_confirm(self, target, object_key):
        self.calls.append((target, object_key))
        if self.fail:
            raise DeletionError("STORAGE_UNAVAILABLE")


def queued(db, key):
    db.execute(
        "INSERT INTO storage_deletion_request_queue (s3_object_key) VALUES (%s)", (key,)
    )


def process(url, backend, **kwargs):
    async def execute():
        async with connect(url) as conn:
            return await process_deletions(
                conn, targets=TARGETS, backend=backend, **kwargs
            )

    return run(execute())


@pytest.mark.parametrize(
    "key",
    [
        "test.wav",
        "temporary/speech/not-uuid.wav",
        f"photos/{uuid4()}.exe",
        f"photos/nested/{uuid4()}.png",
        "photos/../secret.jpg",
    ],
)
def test_unknown_key_is_not_routed(key):
    assert resolve_target(key, TARGETS) is None


def test_overlapping_prefixes_are_rejected_even_in_different_buckets():
    with pytest.raises(ValueError):
        validate_targets(
            (TARGETS[0], DeletionTarget("photo", "other", "r", "temporary"))
        )


def test_dry_run_has_no_s3_or_database_mutation(migrated_database_url):
    db = _Db(migrated_database_url)
    queued(db, f"photos/{uuid4()}.jpg")
    before = db.execute("SELECT * FROM storage_deletion_request_queue")
    backend = FakeDelete()
    result = process(migrated_database_url, backend)
    assert result["eligible"] == 1 and result["deleted"] == 0
    assert backend.calls == []
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == before


def test_delete_confirmed_audio_marks_success_and_removes_queue(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=900))
    run(
        db.repository.mark_stt_completed(
            analysis_id=job.analysis_id, transcript=TRANSCRIPT
        )
    )
    queued(db, job.object_key)
    backend = FakeDelete()
    result = process(migrated_database_url, backend, apply=True)
    assert result["deleted"] == 1
    assert db.job_row(job.analysis_id)["audio_deleted_at"] is not None
    assert db.job_row(job.analysis_id)["transcript"] == TRANSCRIPT
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []
    assert backend.calls == [(TARGETS[0], job.object_key)]


def test_a_held_speech_part_is_deleted_only_after_its_hold(migrated_database_url):
    # 30분 조각은 작업 행에 없어 쓰이는 중인지 실행기가 모른다. worker가 전체 전사가 끝날 때까지
    # 보류(not_before)를 임대와 함께 늘리므로 그동안은 건너뛰고, worker가 죽어 보류가 끝나면 지운다.
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.claim_next(lease_seconds=900))
    part = f"temporary/speech/{uuid4()}.wav"
    run(db.repository.queue_part_deletion(object_key=part, defer=True))
    backend = FakeDelete()
    result = process(migrated_database_url, backend, apply=True)
    assert (result["inspected"], backend.calls) == (0, [])

    db.execute(
        "UPDATE storage_deletion_request_queue "
        "SET not_before = now() - interval '1 second' WHERE s3_object_key = %s",
        (part,),
    )
    result = process(migrated_database_url, backend, apply=True)
    assert result["deleted"] == 1
    assert backend.calls == [(TARGETS[0], part)]
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []
    # 같은 작업의 원본(처리 중)은 대기열에 없고 건드리지 않았다.
    assert db.job_row(job.analysis_id)["audio_deleted_at"] is None


def test_failures_remain_and_do_not_starve_later_requests(migrated_database_url):
    db = _Db(migrated_database_url)
    first, second = f"photos/{uuid4()}.jpg", f"photos/{uuid4()}.png"
    queued(db, first)
    queued(db, second)
    result = process(migrated_database_url, FakeDelete(fail=True), apply=True, limit=1)
    assert result["errors"] == {"STORAGE_UNAVAILABLE": 1}
    row = db.execute(
        "SELECT * FROM storage_deletion_request_queue WHERE s3_object_key = %s",
        (first,),
    )[0]
    assert row["attempt_count"] == 1 and row["last_error_code"] == "STORAGE_UNAVAILABLE"
    assert row["last_attempt_at"] >= row["requested_at"]
    backend = FakeDelete()
    assert process(migrated_database_url, backend, apply=True, limit=1)["deleted"] == 1
    assert backend.calls[0][1] == second
    assert db.execute("SELECT s3_object_key FROM storage_deletion_request_queue") == [
        {"s3_object_key": first}
    ]


def test_active_recording_and_unknown_key_are_not_deleted(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    queued(db, job.object_key)
    queued(db, "legacy/unknown.wav")
    backend = FakeDelete()
    result = process(migrated_database_url, backend, apply=True)
    assert result["errors"] == {"LIVE_REFERENCE": 1, "UNKNOWN_OBJECT_ROUTE": 1}
    assert backend.calls == []
    assert db.job_row(job.analysis_id)["audio_deleted_at"] is None


def test_second_executor_does_not_run_when_session_lock_is_held(migrated_database_url):
    db = _Db(migrated_database_url)
    queued(db, f"photos/{uuid4()}.jpg")
    backend = FakeDelete()

    async def execute():
        async with (
            connect(migrated_database_url) as owner,
            connect(migrated_database_url) as other,
        ):
            await owner.execute(
                "SELECT pg_advisory_lock(%s, %s)", (LOCK_NAMESPACE, LOCK_KEY)
            )
            result = await process_deletions(
                other, targets=TARGETS, backend=backend, apply=True
            )
            assert result["busy"] is True
            assert backend.calls == []
        async with connect(migrated_database_url) as after:
            return await process_deletions(
                after, targets=TARGETS, backend=backend, apply=True
            )

    assert run(execute())["deleted"] == 1


def test_photo_row_must_be_removed_before_its_object(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    profile = db.execute(
        "SELECT profile_id FROM visit_sessions WHERE session_id = %s", (session,)
    )[0]["profile_id"]
    key = f"photos/{uuid4()}.jpg"
    db.execute(
        "INSERT INTO photos (profile_id, s3_object_key) VALUES (%s, %s)", (profile, key)
    )
    queued(db, key)
    backend = FakeDelete()
    assert process(migrated_database_url, backend, apply=True)["errors"] == {
        "LIVE_REFERENCE": 1
    }
    assert backend.calls == []
    db.execute("DELETE FROM photos WHERE s3_object_key = %s", (key,))
    assert process(migrated_database_url, backend, apply=True)["deleted"] == 1


def test_storage_call_does_not_hold_database_transaction(migrated_database_url):
    from psycopg.pq import TransactionStatus

    db = _Db(migrated_database_url)
    queued(db, f"photos/{uuid4()}.jpg")

    async def execute():
        async with connect(migrated_database_url) as conn:

            class InspectTransaction(FakeDelete):
                async def delete_and_confirm(self, target, object_key):
                    assert conn.info.transaction_status == TransactionStatus.IDLE

            return await process_deletions(
                conn, targets=TARGETS, backend=InspectTransaction(), apply=True
            )

    assert run(execute())["deleted"] == 1


def test_unexpected_error_releases_lock_and_keeps_request(migrated_database_url):
    db = _Db(migrated_database_url)
    queued(db, f"photos/{uuid4()}.jpg")

    class BrokenBackend(FakeDelete):
        async def delete_and_confirm(self, target, object_key):
            raise RuntimeError("synthetic unexpected error")

    with pytest.raises(RuntimeError):
        process(migrated_database_url, BrokenBackend(), apply=True)
    assert (
        db.execute("SELECT count(*) AS n FROM storage_deletion_request_queue")[0]["n"]
        == 1
    )
    assert process(migrated_database_url, FakeDelete(), apply=True)["deleted"] == 1


def test_cli_never_prints_configuration_secrets(monkeypatch, capsys):
    from app.workers import storage_deletion

    def bad_settings():
        raise ValueError("synthetic-secret-in-url")

    monkeypatch.setattr(storage_deletion, "Settings", bad_settings)
    monkeypatch.setattr("sys.argv", ["storage_deletion"])
    with pytest.raises(SystemExit) as exit_info:
        storage_deletion.main()
    assert exit_info.value.code == 1
    output = capsys.readouterr()
    assert "DELETION_CHECK_FAILED" in output.out
    assert "synthetic-secret" not in output.out + output.err


class S3Client:
    def __init__(self, version=None, head_status=404):
        self.version = version
        self.head_status = head_status
        self.deletes = []

    def get_bucket_versioning(self, **kwargs):
        return {} if self.version is None else {"Status": self.version}

    def delete_object(self, **kwargs):
        self.deletes.append(kwargs)

    def head_object(self, **kwargs):
        if self.head_status != 200:
            raise ClientError(
                {
                    "Error": {"Code": str(self.head_status)},
                    "ResponseMetadata": {"HTTPStatusCode": self.head_status},
                },
                "HeadObject",
            )
        return {}


@pytest.mark.parametrize("version", ["Enabled", "Suspended"])
def test_versioned_bucket_is_not_deleted(version):
    client = S3Client(version=version)
    backend = S3DeleteBackend(client_factory=lambda region: client)
    with pytest.raises(DeletionError, match="VERSIONED_BUCKET_REQUIRES_REVIEW"):
        run(backend.delete_and_confirm(TARGETS[0], "synthetic-key"))
    assert client.deletes == []


@pytest.mark.parametrize(
    ("status", "code"), [(403, "STORAGE_UNAVAILABLE"), (200, "DELETE_NOT_CONFIRMED")]
)
def test_head_permission_error_or_remaining_object_is_not_success(status, code):
    backend = S3DeleteBackend(
        client_factory=lambda region: S3Client(head_status=status)
    )
    with pytest.raises(DeletionError, match=code):
        run(backend.delete_and_confirm(TARGETS[0], "synthetic-key"))


def test_head_404_confirms_delete():
    client = S3Client()
    run(
        S3DeleteBackend(client_factory=lambda region: client).delete_and_confirm(
            TARGETS[0], "synthetic-key"
        )
    )
    assert len(client.deletes) == 1


def test_migration_preserves_pending_requests(alembic_config, test_database_url):
    command.upgrade(alembic_config, "e5a1c7d93b42")
    db = _Db(test_database_url)
    queued(db, "synthetic-pending-key")
    command.upgrade(alembic_config, "head")
    row = db.execute("SELECT * FROM storage_deletion_request_queue")[0]
    assert row["s3_object_key"] == "synthetic-pending-key"
    assert row["attempt_count"] == 0
    assert row["last_attempt_at"] is None and row["last_error_code"] is None
    command.downgrade(alembic_config, "e5a1c7d93b42")
    assert db.execute("SELECT s3_object_key FROM storage_deletion_request_queue") == [
        {"s3_object_key": "synthetic-pending-key"}
    ]
