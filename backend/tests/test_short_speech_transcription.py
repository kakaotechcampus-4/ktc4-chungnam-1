import asyncio
from dataclasses import replace
from io import BytesIO
import wave

from fastapi import UploadFile
import pytest

from alembic import command
from app.api.deps import get_current_account, get_speech_audio_storage
from app.core.config import Settings, get_settings
from app.core.database import connect
from app.core.errors import AppError
from app.main import create_app
from app.services.speech_transcription import transcribe_short_audio
from tests.support import request, run
from tests.test_speech_analyses import ACCOUNT, FakeAiServer, FakeAudioStorage, synthetic_wav
from tests.test_speech_job_repository import _Db
from tests.test_storage_deletion import FakeDelete, process


def harness(url, *, storage=None, ai=None, account=ACCOUNT, timeout=5):
    app = create_app()
    storage = storage or FakeAudioStorage()
    ai = ai or FakeAiServer()
    app.dependency_overrides[get_settings] = lambda: Settings(
        database_url=url, ai_server_timeout_seconds=timeout, session_secret="s" * 32,
    )
    app.dependency_overrides[get_current_account] = lambda: account
    app.dependency_overrides[get_speech_audio_storage] = lambda: storage
    app.state.ai_server_client = ai
    return app, storage, ai


def submit(app, audio=None):
    return request(app, "POST", "/api/v1/speech-transcriptions", files={
        "audio": ("synthetic.wav", synthetic_wav() if audio is None else audio, "audio/wav"),
    })


def test_profile_speech_returns_text_without_creating_visit_or_transcript(migrated_database_url):
    app, storage, ai = harness(migrated_database_url)
    response = submit(app)
    assert response.status_code == 200, response.text
    assert response.json() == {"schemaVersion": 1, "text": "합성 전사 결과"}
    assert len(ai.payloads) == 1 and ai.payloads[0].speaker_count == 1
    assert storage.objects == {} and len(storage.deleted) == 1
    db = _Db(migrated_database_url)
    for table in ("profiles", "visit_sessions", "speech_analysis_jobs"):
        assert db.execute(f"SELECT count(*) AS n FROM {table}")[0]["n"] == 0
    pending = db.execute("SELECT not_before <= now() AS ready FROM storage_deletion_request_queue")
    assert pending == [{"ready": True}]
    assert process(migrated_database_url, FakeDelete(), apply=True)["deleted"] == 1


@pytest.mark.parametrize("audio,status", [(b"", 422), (b"not-wave", 422), (b"x" * (10*1024*1024+1), 413)], ids=["empty", "damaged", "oversized"])
def test_bad_audio_does_not_upload(migrated_database_url, audio, status):
    app, storage, ai = harness(migrated_database_url)
    assert submit(app, audio).status_code == status
    assert storage.objects == {} and storage.deleted == [] and ai.payloads == []
    assert _Db(migrated_database_url).execute("SELECT * FROM storage_deletion_request_queue") == []


def test_more_than_five_minutes_is_rejected(migrated_database_url):
    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\0\0" * (300*16000+1))
    app, storage, _ = harness(migrated_database_url)
    response = submit(app, output.getvalue())
    assert response.status_code == 413
    assert response.json()["errorCode"] == "AUDIO_TOO_LARGE"
    assert storage.deleted == []


def test_missing_consent_does_not_store_audio(migrated_database_url):
    app, storage, ai = harness(migrated_database_url, account=replace(ACCOUNT, consents={}))
    response = submit(app)
    assert response.status_code == 403
    assert response.json()["errorCode"] == "SPEECH_PROCESSING_CONSENT_REQUIRED"
    assert storage.deleted == [] and ai.payloads == []


@pytest.mark.parametrize("code,status", [("AI_SERVER_UNAVAILABLE",503),("AI_SERVER_ERROR",502),("INVALID_AI_RESPONSE",502)])
def test_stt_error_is_preserved_and_audio_is_removed(migrated_database_url, code, status):
    class BrokenAi:
        async def analyze_speech(self, payload):
            raise AppError(status_code=status, error_code=code, message="합성 실패", retryable=True)

    app, storage, _ = harness(migrated_database_url, ai=BrokenAi())
    response = submit(app)
    assert response.status_code == status
    assert response.json()["errorCode"] == code
    assert response.json()["retryable"] is True
    assert storage.objects == {} and len(storage.deleted) == 1


def test_timeout_does_not_keep_audio_or_save_text(migrated_database_url):
    class SlowAi:
        async def analyze_speech(self, payload):
            await asyncio.sleep(1)
            pytest.fail("시간 초과 이후 결과를 사용하면 안 된다")

    app, storage, _ = harness(migrated_database_url, ai=SlowAi(), timeout=.01)
    response = submit(app)
    assert response.status_code == 504
    assert response.json()["errorCode"] == "AI_SERVER_TIMEOUT"
    assert storage.objects == {}


def test_empty_text_is_returned_for_existing_fe_direct_input_path(migrated_database_url):
    class EmptyAi(FakeAiServer):
        async def analyze_speech(self, payload):
            return (await super().analyze_speech(payload)).model_copy(update={"text": "  "})

    app, _, _ = harness(migrated_database_url, ai=EmptyAi())
    assert submit(app).json() == {"schemaVersion": 1, "text": ""}


def test_cleanup_failure_keeps_queue_but_not_exception_or_transcript_in_log(migrated_database_url, capfd):
    class BrokenDelete(FakeAudioStorage):
        async def delete(self, **kwargs):
            raise RuntimeError("synthetic-secret-object-url")

    app, storage, _ = harness(migrated_database_url, storage=BrokenDelete())
    assert submit(app).status_code == 200
    captured = capfd.readouterr()
    logs = captured.out + captured.err
    assert "short_speech_deletion_pending" in logs
    assert "synthetic-secret-object-url" not in logs
    assert "합성 전사 결과" not in logs
    assert len(storage.objects) == 1
    assert _Db(migrated_database_url).execute("SELECT not_before <= now() AS ready FROM storage_deletion_request_queue") == [{"ready": True}]


def test_active_upload_is_not_deleted_by_queue_executor(migrated_database_url):
    db = _Db(migrated_database_url)
    class CheckingAi(FakeAiServer):
        async def analyze_speech(self, payload):
            from app.services.storage_deletion import process_deletions
            from tests.test_storage_deletion import TARGETS
            async with connect(migrated_database_url) as c:
                result = await process_deletions(c, targets=TARGETS, backend=FakeDelete(), apply=True)
            assert result["inspected"] == 0
            return await super().analyze_speech(payload)

    app, _, _ = harness(migrated_database_url, ai=CheckingAi())
    assert submit(app).status_code == 200
    assert len(db.execute("SELECT * FROM storage_deletion_request_queue")) == 1


def test_partial_upload_failure_keeps_cleanup_record(migrated_database_url):
    class PartialStorage(FakeAudioStorage):
        async def upload(self, **kwargs):
            await super().upload(**kwargs)
            raise RuntimeError("synthetic-secret-upload-error")

    app, storage, ai = harness(migrated_database_url, storage=PartialStorage())
    response = submit(app)
    assert response.status_code == 503
    assert response.json()["errorCode"] == "AUDIO_STORAGE_UNAVAILABLE"
    assert "synthetic-secret" not in response.text
    assert storage.objects == {} and ai.payloads == []
    assert len(_Db(migrated_database_url).execute("SELECT * FROM storage_deletion_request_queue")) == 1


def test_authentication_is_required_before_transcription(migrated_database_url):
    app, storage, ai = harness(migrated_database_url)
    del app.dependency_overrides[get_current_account]
    assert submit(app).status_code == 401
    assert storage.deleted == [] and ai.payloads == []


def test_cancellation_waits_for_upload_before_deleting(migrated_database_url):
    async def scenario():
        started, finish = asyncio.Event(), asyncio.Event()
        class SlowStorage(FakeAudioStorage):
            async def upload(self, **kwargs):
                started.set()
                await finish.wait()
                await super().upload(**kwargs)
        storage = SlowStorage()
        ai = FakeAiServer()
        async with connect(migrated_database_url) as c:
            task = asyncio.create_task(transcribe_short_audio(
                c, account=ACCOUNT, audio=UploadFile(BytesIO(synthetic_wav())),
                storage=storage, ai_server=ai, object_prefix="temporary/speech",
                retention_seconds=86400, timeout_seconds=5, max_audio_bytes=1024*1024,
            ))
            await started.wait()
            task.cancel()
            await asyncio.sleep(0)
            assert storage.deleted == []
            finish.set()
            with pytest.raises(asyncio.CancelledError):
                await task
        assert storage.objects == {} and len(storage.deleted) == 1
        assert ai.payloads == []
    run(scenario())


def test_downgrade_refuses_to_remove_active_upload_guard(alembic_config, test_database_url):
    command.upgrade(alembic_config, "head")
    db = _Db(test_database_url)
    db.execute("INSERT INTO storage_deletion_request_queue (s3_object_key,not_before) VALUES ('synthetic',now()+interval '1 hour')")
    with pytest.raises(Exception, match="Pending short speech uploads"):
        command.downgrade(alembic_config, "a49d71b28c36")
    assert db.execute("SELECT not_before IS NOT NULL AS kept FROM storage_deletion_request_queue") == [{"kept": True}]
