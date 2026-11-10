"""실제 DB·API 없이 재전송 직전 업무 검사와 스레드 경계를 검증한다."""
import asyncio
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

import httpx2 as httpx
import openai
import pytest

from common.retry import RetryBlocked, invoke_with_retry, retry_scope
from app.core.config import Settings
from app.core.errors import AppError
from app.services.llm_retry_guard import retry_guard
from app.services import card_sets, photo_analysis_pipeline as photos
from app.services.card_generation_jobs import CardGenerationJob
from app.schemas.card_generation import CardContext


def unavailable():
    return openai.APIConnectionError(request=httpx.Request("POST", "https://synthetic.invalid"))


def test_retry_is_disabled_by_default_and_can_be_configured():
    assert Settings(_env_file=None).llm_retry_enabled is False
    assert Settings(_env_file=None, llm_retry_enabled=True).llm_retry_enabled is True


def test_thread_guard_rechecks_on_worker_loop_and_preserves_business_error():
    async def scenario():
        loop = asyncio.get_running_loop()
        calls = []
        stopped = AppError(status_code=409, error_code="TRANSCRIPT_EXPIRED", message="합성 만료")

        async def check():
            assert asyncio.get_running_loop() is loop
            raise stopped

        def work():
            def send(timeout):
                calls.append(timeout)
                raise unavailable()
            with retry_scope(enabled=True, delay_seconds=0):
                invoke_with_retry(send, timeout=10)

        with retry_scope(before_retry=retry_guard(check)):
            with pytest.raises(RetryBlocked) as caught:
                await asyncio.to_thread(work)
        assert caught.value.original is stopped
        assert len(calls) == 1
    asyncio.run(scenario())


class Cursor:
    def __init__(self, value):
        self.value = value

    async def fetchone(self):
        return self.value


def test_deleted_card_job_is_not_sent_again(monkeypatch):
    async def scenario():
        sent, failed = [], []

        class Connection:
            async def execute(self, sql, params):
                if "SELECT model" in sql:
                    return Cursor({"model": "gpt-6-luna", "prompt_version": "2"})
                assert "attempt_count=%s" in sql and "clock_timestamp()" in sql
                return Cursor(None)  # deleted while the first model call failed

        class Queue:
            async def fail(self, connection, job, **kwargs):
                failed.append(kwargs["error_code"])

        async def context(*args):
            return CardContext.model_validate({
                "ageRange": "80s", "profileFacts": {
                    "occupation": None, "hometown": None, "hobby": None, "family": None,
                }, "lifeFacts": [], "photos": [], "topics": [], "visits": [], "pastCards": [],
            })

        def generate(request):
            def send(timeout):
                sent.append(timeout)
                raise unavailable()
            try:
                with retry_scope(enabled=True, delay_seconds=0):
                    invoke_with_retry(send, timeout=10)
            except RetryBlocked as blocked:
                raise blocked.original

        monkeypatch.setattr(card_sets, "build_context", context)
        processor = card_sets.CardGenerationProcessor(queue=Queue(), generate=generate)
        await processor(Connection(), CardGenerationJob(uuid4(), uuid4(), 1))
        assert len(sent) == 1
        assert failed == ["WORKER_LEASE_EXPIRED"]
    asyncio.run(scenario())


def test_withdrawn_photo_consent_blocks_retry(monkeypatch):
    async def scenario():
        sent = []

        class Connection:
            async def execute(self, sql, params):
                if "current_consents" in sql:
                    return Cursor(None)  # consent withdrawn after initial send
                return Cursor({"active": True})

            @asynccontextmanager
            async def transaction(self):
                yield

        async def noop(*args):
            return False

        class Storage:
            async def create_download(self, **kwargs):
                return SimpleNamespace(url="https://synthetic.invalid/image",
                                       expires_at=datetime.now(UTC) + timedelta(minutes=5))

        def analyze(url):
            def send(timeout):
                sent.append(timeout)
                raise unavailable()
            try:
                with retry_scope(enabled=True, delay_seconds=0):
                    invoke_with_retry(send, timeout=10)
            except RetryBlocked as blocked:
                raise blocked.original

        monkeypatch.setattr(photos, "lock_profile", noop)
        monkeypatch.setattr(photos, "_release_without_consent", noop)
        processor = photos.PhotoAnalysisProcessor(storage=Storage(), analyze=analyze,
                                                 model="gpt-6-luna", timeout_seconds=10)
        job = SimpleNamespace(photo_id=uuid4(), profile_id=uuid4(), attempt_count=1,
                              s3_object_key="synthetic")
        with pytest.raises(AppError) as caught:
            await processor(Connection(), job)
        assert caught.value.error_code == "IMAGE_ANALYSIS_CANCELLED"
        assert len(sent) == 1
    asyncio.run(scenario())
