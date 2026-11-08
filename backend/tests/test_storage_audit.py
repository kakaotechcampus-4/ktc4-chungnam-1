from datetime import UTC, datetime, timedelta

from botocore.exceptions import ClientError
import pytest

from app.core.database import connect
from app.ops.storage_audit import expired_audio, inspect_bucket
from tests.support import run
from tests.test_speech_job_repository import TRANSCRIPT, _accept, _Db


def expired(url, **kwargs):
    async def check():
        async with connect(url) as conn:
            return await expired_audio(conn, **kwargs)
    return run(check())


def test_default_only_counts_expired_rows(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    db.execute("UPDATE speech_analysis_jobs SET data_expires_at = now() - interval '1 hour'")
    before = db.job_row(job.analysis_id)
    assert expired(migrated_database_url)["expired_by_status"] == {"queued": 1}
    assert db.job_row(job.analysis_id) == before
    assert db.execute("SELECT * FROM storage_deletion_request_queue") == []


def test_enqueue_preserves_transcript_and_excludes_active_audio(migrated_database_url):
    db = _Db(migrated_database_url)
    _, first = db.seed_session()
    ready = _accept(db, first)
    run(db.repository.claim_next(lease_seconds=900))
    run(db.repository.mark_stt_completed(analysis_id=ready.analysis_id, transcript=TRANSCRIPT))
    _, second = db.seed_session()
    queued = _accept(db, second)
    db.execute("UPDATE speech_analysis_jobs SET data_expires_at = now() - interval '1 hour'")
    result = expired(migrated_database_url, enqueue=True)
    assert result["enqueued"] == 1 and result["s3_modified"] is False
    assert db.execute("SELECT s3_object_key FROM storage_deletion_request_queue") == [
        {"s3_object_key": ready.object_key}]
    assert db.job_row(ready.analysis_id)["transcript"] == TRANSCRIPT
    assert db.job_row(queued.analysis_id)["status"] == "queued"
    assert expired(migrated_database_url, enqueue=True)["enqueued"] == 0


def test_future_and_already_deleted_audio_not_enqueued(migrated_database_url):
    db = _Db(migrated_database_url)
    _, session = db.seed_session()
    job = _accept(db, session)
    run(db.repository.mark_failed(analysis_id=job.analysis_id, error_code="SYNTHETIC"))
    assert expired(migrated_database_url, enqueue=True)["enqueued"] == 0
    db.execute("UPDATE speech_analysis_jobs SET data_expires_at = now() - interval '1 hour', audio_deleted_at = now()")
    assert expired(migrated_database_url, enqueue=True)["expired_by_status"] == {}


class FakeS3:
    def __init__(self, pages, lifecycle=None):
        self.pages = pages
        self.calls = []
        self.lifecycle = lifecycle

    def get_bucket_lifecycle_configuration(self, **kwargs):
        if self.lifecycle is None:
            raise ClientError({"Error": {"Code": "NoSuchLifecycleConfiguration"}}, "GetBucketLifecycleConfiguration")
        return {"Rules": self.lifecycle}

    def get_bucket_versioning(self, **kwargs):
        return {}

    def list_objects_v2(self, **kwargs):
        self.calls.append(kwargs)
        return self.pages.pop(0)


def test_inventory_pages_unknown_root_and_known_expired_without_body_or_delete():
    now = datetime.now(UTC)
    def obj(key):
        return {"Key": key, "Size": 5, "LastModified": now - timedelta(days=2)}
    client = FakeS3([
        {"Contents": [obj("temporary/speech/known.wav")], "IsTruncated": True, "NextContinuationToken": "next"},
        {"Contents": [obj("legacy.wav"), obj("photos/unknown.png")]},
    ])
    result = inspect_bucket(client, "synthetic-bucket", references={"temporary/speech/known.wav"},
                            deadlines={"temporary/speech/known.wav": now-timedelta(days=1)}, now=now)
    assert result["complete"] is True
    assert result["listed"] == 3 and result["unreferenced"] == 2
    assert result["bucket_root_objects"] == 1 and result["past_audio_deadline"] == 1
    assert result["lifecycle_rule_count"] == 0
    assert client.calls[1]["ContinuationToken"] == "next"
    assert "known.wav" not in str(result) and "synthetic-bucket" not in str(result)


def test_inventory_separates_unreferenced_objects_already_queued():
    now = datetime.now(UTC)
    def obj(key):
        return {"Key": key, "Size": 5, "LastModified": now}
    client = FakeS3([{"Contents": [obj("photos/a.jpg"), obj("photos/b.jpg"),
                                   obj("photos/c.jpg"), obj("photos/kept.jpg")]}])
    # a는 업로드 중 사전 등록(기한 전), b는 기한이 지난 요청, c는 대기열 밖이다.
    result = inspect_bucket(client, "synthetic", references={"photos/kept.jpg"}, deadlines={},
                            now=now, queued={"photos/a.jpg": True, "photos/b.jpg": False,
                                             "photos/kept.jpg": False})
    assert result["unreferenced"] == 3
    assert result["unreferenced_queued"] == 2 and result["unreferenced_queued_not_due"] == 1
    assert "photos/" not in str(result)


def test_inventory_limit_reports_incomplete():
    client = FakeS3([{"Contents": [], "IsTruncated": True}])
    result = inspect_bucket(client, "synthetic", references=set(), deadlines={}, now=datetime.now(UTC), limit=1)
    assert result["complete"] is False


def test_empty_bucket_complete_is_not_an_error():
    client = FakeS3([{}], lifecycle=[{"Status": "Enabled"}])
    result = inspect_bucket(client, "synthetic", references=set(), deadlines={}, now=datetime.now(UTC))
    assert result["complete"] is True and result["listed"] == 0
    assert result["lifecycle_rule_count"] == 1 and result["oldest_object_at"] is None


def test_lifecycle_access_denied_is_not_reported_as_no_rules():
    class Denied(FakeS3):
        def get_bucket_lifecycle_configuration(self, **kwargs):
            raise ClientError({"Error": {"Code": "AccessDenied"}}, "GetBucketLifecycleConfiguration")
    with pytest.raises(ClientError):
        inspect_bucket(Denied([]), "synthetic", references=set(), deadlines={}, now=datetime.now(UTC))


def test_repeated_pagination_token_does_not_loop():
    client = FakeS3([
        {"IsTruncated": True, "NextContinuationToken": "a"},
        {"IsTruncated": True, "NextContinuationToken": "b"},
        {"IsTruncated": True, "NextContinuationToken": "a"},
    ])
    result = inspect_bucket(client, "synthetic", references=set(), deadlines={}, now=datetime.now(UTC))
    assert result["complete"] is False and len(client.calls) == 3
