import asyncio
from dataclasses import replace
from io import BytesIO
import wave

from fastapi import Request, UploadFile
from httpx import ASGITransport, AsyncClient
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


def _silent_wav(frames):
    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\0\0" * frames)
    return output.getvalue()


def test_more_than_five_minutes_is_rejected(migrated_database_url):
    app, storage, _ = harness(migrated_database_url)
    response = submit(app, _silent_wav(302*16000+1))
    assert response.status_code == 413
    assert response.json()["errorCode"] == "AUDIO_TOO_LARGE"
    assert storage.deleted == []


def test_a_full_five_minute_recording_that_stopped_a_little_late_is_accepted(migrated_database_url):
    # 앱은 녹음을 시작한 뒤 5분 타이머를 켜서, 5분을 채운 파일은 300초를 조금 넘는다.
    # 11/8 운영 시험에서 300.004초 파일이 413으로 거절됐다.
    app, _, ai = harness(migrated_database_url)
    response = submit(app, _silent_wav(300*16000 + 16000 // 2))
    assert response.status_code == 200, response.text
    assert len(ai.payloads) == 1


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


# ── 계정당 동시 요청 수(2026-11-09 PM 결정, 기본 2건) ───────────────────────────


OTHER_ACCOUNT = replace(ACCOUNT, account_id="00000000-0000-0000-0000-0000000000a2")


def _send_as(client, who):
    return client.post(
        "/api/v1/speech-transcriptions", headers={"X-Synthetic-Account": who},
        files={"audio": ("synthetic.wav", synthetic_wav(), "audio/wav")},
    )


def _accounts_by_header(app):
    accounts = {"first": ACCOUNT, "other": OTHER_ACCOUNT}

    def current(request: Request):
        return accounts[request.headers["X-Synthetic-Account"]]

    app.dependency_overrides[get_current_account] = current


def test_third_concurrent_request_of_the_same_account_is_rejected(migrated_database_url):
    """기본 2건. 앱은 앞 전사가 끝나기 전에 `건너뛰기`로 다음 항목을 녹음해 보낼 수 있다."""
    async def scenario():
        both_running, finish = asyncio.Event(), asyncio.Event()
        waiting = []

        class WaitingAi(FakeAiServer):
            async def analyze_speech(self, payload):
                if len(waiting) < 2:
                    waiting.append(payload)
                    if len(waiting) == 2:
                        both_running.set()
                    await finish.wait()
                return await super().analyze_speech(payload)

        app, storage, ai = harness(migrated_database_url, ai=WaitingAi())
        _accounts_by_header(app)
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            running = [asyncio.create_task(_send_as(client, "first")) for _ in range(2)]
            await both_running.wait()
            busy = await _send_as(client, "first")
            uploads_while_busy = len(storage.objects)
            elsewhere = await _send_as(client, "other")
            finish.set()
            done = await asyncio.gather(*running)
            after = await _send_as(client, "first")
        return storage, ai, uploads_while_busy, busy, elsewhere, done, after

    storage, ai, uploads_while_busy, busy, elsewhere, done, after = run(scenario())
    assert busy.status_code == 429, busy.text
    assert busy.json()["errorCode"] == "SPEECH_TRANSCRIPTION_IN_PROGRESS"
    assert busy.json()["retryable"] is True
    # 거절한 요청은 S3에 올리지 않고 STT도 부르지 않는다. 처리 중인 두 요청의 원본만 있다.
    assert uploads_while_busy == 2
    assert [r.status_code for r in (elsewhere, *done, after)] == [200, 200, 200, 200]
    assert len(ai.payloads) == 4 and len(storage.deleted) == 4
    rows = _Db(migrated_database_url).execute("SELECT count(*) AS n FROM storage_deletion_request_queue")
    assert rows[0]["n"] == 4


def test_failed_request_does_not_block_the_next_one(migrated_database_url):
    class FailOnce(FakeAiServer):
        failed = False

        async def analyze_speech(self, payload):
            if not self.failed:
                self.failed = True
                raise AppError(status_code=503, error_code="AI_SERVER_UNAVAILABLE",
                               message="합성 실패", retryable=True)
            return await super().analyze_speech(payload)

    app, _, ai = harness(migrated_database_url, ai=FailOnce())
    assert submit(app).status_code == 503
    assert submit(app).status_code == 200
    assert len(ai.payloads) == 1


def test_concurrency_follows_the_setting(migrated_database_url):
    async def scenario():
        started, finish = asyncio.Event(), asyncio.Event()

        class WaitingAi(FakeAiServer):
            async def analyze_speech(self, payload):
                if not started.is_set():
                    started.set()
                    await finish.wait()
                return await super().analyze_speech(payload)

        app, _, _ = harness(migrated_database_url, ai=WaitingAi())
        app.dependency_overrides[get_settings] = lambda: Settings(
            database_url=migrated_database_url, ai_server_timeout_seconds=5,
            session_secret="s" * 32, short_transcription_concurrency_per_account=1,
        )
        _accounts_by_header(app)
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            first = asyncio.create_task(_send_as(client, "first"))
            await started.wait()
            second = await _send_as(client, "first")
            finish.set()
            return second, await first

    second, first = run(scenario())
    assert second.status_code == 429
    assert second.json()["errorCode"] == "SPEECH_TRANSCRIPTION_IN_PROGRESS"
    assert first.status_code == 200


# ── 6-6 전용 대기 시간과 서버 전체 동시 요청 수 ─────────────────────────────────


def test_short_timeout_applies_even_when_the_general_ai_timeout_is_longer(migrated_database_url):
    """앱은 2분에 포기하므로 6-6은 면회 분석용 `ai_server_timeout_seconds`(기본 600초)를 쓰지 않는다."""
    class SlowAi:
        async def analyze_speech(self, payload):
            await asyncio.sleep(1)
            pytest.fail("6-6 대기 시간이 지난 뒤 결과를 사용하면 안 된다")

    app, storage, _ = harness(migrated_database_url, ai=SlowAi())
    app.dependency_overrides[get_settings] = lambda: Settings(
        database_url=migrated_database_url, ai_server_timeout_seconds=5,
        short_transcription_timeout_seconds=.01, session_secret="s" * 32,
    )
    response = submit(app)
    assert response.status_code == 504
    assert response.json()["errorCode"] == "AI_SERVER_TIMEOUT"
    assert response.json()["retryable"] is True
    assert storage.objects == {} and len(storage.deleted) == 1


def test_short_timeout_defaults_below_the_app_limit():
    # 앱의 speechTranscriptionTimeout(2분)은 업로드 시간을 포함한다. 로컬 .env 와 관계없이
    # 코드의 기본값을 본다.
    fields = Settings.model_fields
    assert fields["short_transcription_timeout_seconds"].default < 120
    assert fields["short_transcription_concurrency_total"].default is None


def test_empty_server_limit_setting_means_unlimited():
    assert Settings(short_transcription_concurrency_total="").short_transcription_concurrency_total is None
    assert Settings(short_transcription_concurrency_total="3").short_transcription_concurrency_total == 3


def test_server_wide_limit_rejects_other_accounts_without_uploading(migrated_database_url):
    async def scenario():
        started, finish = asyncio.Event(), asyncio.Event()

        class WaitingAi(FakeAiServer):
            async def analyze_speech(self, payload):
                if not started.is_set():
                    started.set()
                    await finish.wait()
                return await super().analyze_speech(payload)

        app, storage, ai = harness(migrated_database_url, ai=WaitingAi())
        app.dependency_overrides[get_settings] = lambda: Settings(
            database_url=migrated_database_url, ai_server_timeout_seconds=5,
            session_secret="s" * 32, short_transcription_concurrency_total=1,
        )
        _accounts_by_header(app)
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            first = asyncio.create_task(_send_as(client, "first"))
            await started.wait()
            busy = await _send_as(client, "other")
            uploads_while_busy = len(storage.objects)
            finish.set()
            done = await first
            after = await _send_as(client, "other")
        return storage, ai, busy, uploads_while_busy, done, after

    storage, ai, busy, uploads_while_busy, done, after = run(scenario())
    assert busy.status_code == 503, busy.text
    assert busy.json()["errorCode"] == "SPEECH_TRANSCRIPTION_BUSY"
    assert busy.json()["retryable"] is True
    # 거절한 요청은 S3에 올리지 않고 STT도 부르지 않는다.
    assert uploads_while_busy == 1
    assert done.status_code == 200 and after.status_code == 200
    assert len(ai.payloads) == 2 and len(storage.deleted) == 2
    rows = _Db(migrated_database_url).execute("SELECT count(*) AS n FROM storage_deletion_request_queue")
    assert rows[0]["n"] == 2


def test_account_limit_is_checked_before_the_server_limit(migrated_database_url):
    """계정 한도에 걸린 요청은 서버 칸을 차지하지 않는다."""
    async def scenario():
        started, finish = asyncio.Event(), asyncio.Event()

        class WaitingAi(FakeAiServer):
            async def analyze_speech(self, payload):
                if not started.is_set():
                    started.set()
                    await finish.wait()
                return await super().analyze_speech(payload)

        app, _, _ = harness(migrated_database_url, ai=WaitingAi())
        app.dependency_overrides[get_settings] = lambda: Settings(
            database_url=migrated_database_url, ai_server_timeout_seconds=5,
            session_secret="s" * 32, short_transcription_concurrency_per_account=1,
            short_transcription_concurrency_total=2,
        )
        _accounts_by_header(app)
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            first = asyncio.create_task(_send_as(client, "first"))
            await started.wait()
            same = await _send_as(client, "first")
            other = await _send_as(client, "other")
            finish.set()
            return same, other, await first

    same, other, first = run(scenario())
    assert same.status_code == 429
    assert same.json()["errorCode"] == "SPEECH_TRANSCRIPTION_IN_PROGRESS"
    assert other.status_code == 200 and first.status_code == 200
