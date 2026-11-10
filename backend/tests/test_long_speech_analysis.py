"""30분을 넘는 녹음의 조각 전사(2026-11-10 PM 결정) 검증.

조각 길이를 2초로 줄인 worker(`part_seconds=2`)와 합성 WAV로 실제 기본값(30분)과 같은 경로를
돈다. S3와 STT는 대역이다. 대역 STT는 받은 주소의 객체를 열어 크기, 해시와 WAV 길이를 확인한다.
"""

import asyncio
import hashlib
import logging
import struct
import wave
from datetime import UTC, datetime, timedelta
from io import BytesIO

import pytest

from app.api.deps import get_speech_submission_service
from app.core.errors import AppError
from app.schemas.speech_analysis import SpeechAnalysisResult
from app.services import speech_analysis_pipeline as pipeline
from app.services.audio_storage import AudioDownload
from app.services.speech_analysis_jobs import SpeechAnalysisStatus
from app.services.speech_analysis_pipeline import (
    WORK_DIR_PREFIX,
    SpeechAnalysisSubmissionService,
    create_speech_worker,
    remove_stale_work_dirs,
)
from tests.support import run
from tests.test_speech_analyses import (
    ACCOUNT,
    FakeAudioStorage,
    harness,
    no_connection,
    submit,
)

URL_PREFIX = "https://bucket.s3.ap-northeast-2.amazonaws.com/"
FRAME = 1600


@pytest.fixture(autouse=True)
def keep_real_temp_dirs(monkeypatch):
    # 조각을 나누기 전의 남은 작업 디렉터리 정리가 이 PC의 실제 임시 폴더를 건드리지 않게 한다.
    # 정리 함수 자체는 맨 아래 테스트가 tmp_path로 확인한다.
    monkeypatch.setattr(pipeline, "remove_stale_work_dirs", lambda **kwargs: 0)


def synthetic_wav(*pieces: tuple[str, int]) -> bytes:
    """('loud' | 'quiet', 표본 수) 조각을 이어 붙인 16kHz mono WAV."""
    frames = b"".join(
        struct.pack("<hh", 3000, -3000) * (count // 2) if kind == "loud" else b"\x00\x00" * count
        for kind, count in pieces
    )
    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(frames)
    return output.getvalue()


# 2초 조각이면 1.65초와 3.3초에서 잘려 세 조각이 된다(test_audio_split과 같은 신호).
THREE_PARTS = synthetic_wav(
    ("loud", 25_600), ("quiet", FRAME), ("loud", 24_800), ("quiet", FRAME), ("loud", 22_400)
)
THREE_PART_STARTS_MS = [0, 1650, 3300]


class PartStorage(FakeAudioStorage):
    """받은 키를 주소에 담는다. 내려받기와 삭제 실패를 흉내 낼 수 있다."""

    def __init__(self) -> None:
        super().__init__()
        self.downloads: list[str] = []
        self.uploads: list[str] = []
        self.fail_deletes: set[str] = set()

    async def upload(self, *, object_key: str, file) -> None:
        self.uploads.append(object_key)
        await super().upload(object_key=object_key, file=file)

    async def download(self, *, object_key: str, file) -> None:
        self.downloads.append(object_key)
        file.write(self.objects[object_key])

    async def create_download(self, *, object_key: str, expires_at: datetime) -> AudioDownload:
        assert object_key in self.objects
        return AudioDownload(
            url=URL_PREFIX + object_key,
            expires_at=min(expires_at, datetime.now(UTC) + timedelta(minutes=10)),
        )

    async def delete(self, *, object_key: str) -> None:
        if object_key in self.fail_deletes:
            raise RuntimeError("synthetic delete failure")
        await super().delete(object_key=object_key)


class PartAi:
    """조각마다 `SPEAKER_00` 구간 하나를 돌려준다. `fail_on`번째 호출은 실패한다."""

    def __init__(self, storage: PartStorage, *, fail_on: int | None = None,
                 texts: list[str] | None = None, during=None) -> None:
        self.storage = storage
        self.fail_on = fail_on
        self.texts = texts
        self.during = during
        self.calls: list[dict] = []

    async def analyze_speech(self, payload):
        key = payload.audio_source.download_url.removeprefix(URL_PREFIX)
        content = self.storage.objects[key]
        with wave.open(BytesIO(content), "rb") as wav:
            duration_ms = wav.getnframes() * 1000 // wav.getframerate()
        number = len(self.calls) + 1
        self.calls.append({
            "key": key,
            "size_ok": payload.audio_source.size_bytes == len(content),
            "sha_ok": payload.audio_source.sha256 == hashlib.sha256(content).hexdigest(),
            "speaker_count": payload.speaker_count,
            "analysis_id": payload.analysis_id,
            "duration_ms": duration_ms,
        })
        if self.during is not None:
            outcome = self.during(number)
            if asyncio.iscoroutine(outcome):
                await outcome
        if number == self.fail_on:
            raise AppError(status_code=504, error_code="AI_SERVER_TIMEOUT",
                           message="합성 시간 초과", retryable=True)
        text = self.texts[number - 1] if self.texts else f"합성 조각 {number}"
        return SpeechAnalysisResult(
            schemaVersion=1, analysisId=payload.analysis_id, language="ko",
            durationMs=duration_ms, text=text,
            segments=[
                {"startMs": 100, "endMs": 900, "speakerLabel": "SPEAKER_00", "text": text,
                 "words": [{"startMs": 100, "endMs": 400, "text": "합성", "probability": 0.9}]},
                {"startMs": 1000, "endMs": 1200, "speakerLabel": None, "text": text,
                 "words": []},
            ],
        ).served_by("backup" if number == 2 else "primary")


class CapturingReports:
    def __init__(self) -> None:
        self.speech: SpeechAnalysisResult | None = None

    async def generate(self, connection, *, session_id: str, speech, stats) -> None:
        del connection, session_id, stats
        self.speech = speech


class FakeNotifier:
    def __init__(self) -> None:
        self.ready: list[str] = []
        self.failed: list[str] = []

    async def report_ready(self, connection, *, analysis_id: str) -> None:
        self.ready.append(analysis_id)

    async def report_failed(self, connection, *, analysis_id: str) -> None:
        self.failed.append(analysis_id)


def worker_for(jobs, storage, ai, reports=None, notifier=None):
    return create_speech_worker(
        jobs_for=lambda connection: jobs, audio_storage=storage, ai_server=ai,
        open_connection=no_connection, lease_seconds=900,
        report_generator=reports, report_notifier=notifier, part_seconds=2,
    )


def setup(audio: bytes):
    application, jobs, _, _ = harness()
    storage = PartStorage()
    # 접수 서비스가 쓰는 저장소를 조각 저장소로 바꾼다.
    service = SpeechAnalysisSubmissionService(
        jobs=jobs, audio_storage=storage, max_audio_bytes=1024 * 1024,
        retention_seconds=86400, object_prefix="temporary/speech",
    )
    application.dependency_overrides[get_speech_submission_service] = lambda: service
    response = submit(application, audio=audio)
    assert response.status_code == 202
    analysis_id = response.json()["analysisId"]
    original_key = f"temporary/speech/{analysis_id}.wav"
    assert original_key in storage.objects
    return jobs, storage, analysis_id, original_key


def job_of(jobs, analysis_id):
    return run(jobs.get_for_account(analysis_id=analysis_id, account_id=ACCOUNT.account_id))


def finished_records(caplog):
    return [r for r in caplog.records if r.getMessage() == "speech_analysis_finished"]


def capture(caplog):
    logging.getLogger().addHandler(caplog.handler)
    caplog.set_level(logging.INFO, logger="saerok.speech_analysis")


def count_calls(jobs, name):
    calls = []
    original = getattr(jobs, name)

    async def wrapper(**kwargs):
        calls.append(kwargs)
        return await original(**kwargs)

    setattr(jobs, name, wrapper)
    return calls


def test_a_recording_within_one_part_keeps_the_single_call_without_download():
    jobs, storage, analysis_id, original_key = setup(synthetic_wav(("loud", 24_000)))
    ai = PartAi(storage)
    reports = CapturingReports()

    assert run(worker_for(jobs, storage, ai, reports).run_once()) is True

    assert storage.downloads == []
    assert [call["key"] for call in ai.calls] == [original_key]
    # 한 번 부르면 화자 라벨과 시각은 STT가 준 그대로다.
    assert [s.speaker_label for s in reports.speech.segments] == ["SPEAKER_00", None]
    assert reports.speech.segments[0].start_ms == 100
    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.COMPLETED
    assert storage.objects == {}


def test_a_large_file_that_is_short_after_reading_the_header_is_sent_whole():
    # data 뒤 메타데이터 청크로 크기만 큰 파일은 내려받아 헤더를 본 뒤 원본 하나로 보낸다.
    # 조각 길이 1초(32,000바이트)에 음성은 정확히 1초이고 뒤에 1,000바이트 청크가 붙는다.
    audio = bytearray(synthetic_wav(("loud", 16_000)))
    trailer = b"LIST" + struct.pack("<I", 992) + b"INFO" + b"\x00" * 988
    audio[4:8] = struct.pack("<I", len(audio) + len(trailer) - 8)
    jobs, storage, analysis_id, original_key = setup(bytes(audio + trailer))
    ai = PartAi(storage)
    worker = create_speech_worker(
        jobs_for=lambda connection: jobs, audio_storage=storage, ai_server=ai,
        open_connection=no_connection, lease_seconds=900, part_seconds=1,
    )

    run(worker.run_once())

    assert storage.downloads == [original_key]
    assert [call["key"] for call in ai.calls] == [original_key]
    assert storage.uploads == [original_key]
    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.STT_COMPLETED


def test_three_parts_are_transcribed_in_order_and_merged_with_offsets(caplog):
    jobs, storage, analysis_id, original_key = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    reports = CapturingReports()
    extended = count_calls(jobs, "extend_lease")
    notifier = FakeNotifier()

    run(worker_for(jobs, storage, ai, reports, notifier).run_once())

    # 조각마다 그 조각의 크기와 해시, 같은 작업 ID와 참여자 수로 부른다.
    assert len(ai.calls) == 3
    assert all(call["size_ok"] and call["sha_ok"] for call in ai.calls)
    assert {call["analysis_id"] for call in ai.calls} == {analysis_id}
    assert {call["speaker_count"] for call in ai.calls} == {2}
    assert [call["duration_ms"] for call in ai.calls] == [1650, 1650, 1450]
    part_keys = [call["key"] for call in ai.calls]
    assert original_key not in part_keys and len(set(part_keys)) == 3
    assert all(key.startswith("temporary/speech/") and key.endswith(".wav") for key in part_keys)
    # 조각마다 임대를 늘린다.
    assert len(extended) == 3

    speech = reports.speech
    assert [s.start_ms for s in speech.segments] == [
        start + offset for start in THREE_PART_STARTS_MS for offset in (100, 1000)
    ]
    assert [s.end_ms for s in speech.segments][:2] == [900, 1200]
    assert speech.segments[2].words[0].start_ms == 1650 + 100
    assert [s.speaker_label for s in speech.segments] == [
        "PART1_SPEAKER_00", None, "PART2_SPEAKER_00", None, "PART3_SPEAKER_00", None,
    ]
    assert [s.text for s in speech.segments][::2] == ["합성 조각 1", "합성 조각 2", "합성 조각 3"]
    assert speech.duration_ms == 4750
    assert speech.text == "합성 조각 1 합성 조각 2 합성 조각 3"

    job = job_of(jobs, analysis_id)
    assert job.status == SpeechAnalysisStatus.COMPLETED
    # 원본과 조각이 모두 지워졌고 남은 삭제 요청이 없다.
    assert storage.objects == {}
    assert set(part_keys) <= set(storage.deleted)
    assert jobs.pending_audio_deletions == set()
    assert notifier.ready == [analysis_id] and notifier.failed == []

    [record] = finished_records(caplog)
    assert record.outcome == "completed"
    assert record.stt_parts == 3
    assert record.stt_part_audio_seconds == [1.6, 1.6, 1.4]
    assert len(record.stt_part_elapsed_seconds) == 3
    assert record.stt_server == "backup"
    assert record.speaker_labels == 3
    assert record.audio_seconds == 4.8
    # 로그에는 객체 키와 전사문을 남기지 않는다.
    assert "합성 조각" not in caplog.text
    for key in part_keys + [original_key]:
        assert key not in caplog.text


def test_a_failed_part_fails_the_job_and_deletes_every_uploaded_part(caplog):
    jobs, storage, analysis_id, original_key = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage, fail_on=2)
    notifier = FakeNotifier()

    run(worker_for(jobs, storage, ai, CapturingReports(), notifier).run_once())

    job = job_of(jobs, analysis_id)
    assert (job.status, job.error_code) == (SpeechAnalysisStatus.FAILED, "AI_SERVER_TIMEOUT")
    assert job.transcript is None
    # 두 번째 조각에서 멈췄다. 올린 두 조각과 원본을 지웠고 세 번째 조각은 올리지 않았다.
    part_keys = [call["key"] for call in ai.calls]
    assert len(part_keys) == 2
    assert storage.uploads == [original_key, *part_keys]
    assert storage.objects == {}
    assert jobs.pending_audio_deletions == set()
    # 실패도 알린다(실제 발송 조건은 알림 쪽이 DB에서 다시 확인한다).
    assert notifier.failed == [analysis_id] and notifier.ready == []

    [record] = finished_records(caplog)
    assert (record.outcome, record.error_code) == ("failed", "AI_SERVER_TIMEOUT")
    assert record.stt_parts == 2


def test_a_part_whose_s3_delete_fails_stays_in_the_deletion_queue():
    jobs, storage, analysis_id, _ = setup(THREE_PARTS)
    ai = PartAi(storage)
    stuck = []

    def fail_first_part_delete(number):
        if number == 1:
            key = ai.calls[0]["key"]
            storage.fail_deletes.add(key)
            stuck.append(key)

    ai.during = fail_first_part_delete

    run(worker_for(jobs, storage, ai, CapturingReports()).run_once())

    # 전사와 리포트는 계속한다. 지우지 못한 조각만 대기열에 남아 삭제 실행기가 처리한다.
    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.COMPLETED
    assert jobs.pending_audio_deletions == set(stuck)
    assert set(storage.objects) == set(stuck)


def test_parts_are_registered_for_deletion_before_upload():
    jobs, storage, _, _ = setup(THREE_PARTS)
    ai = PartAi(storage)
    seen = []

    def check(number):
        # STT를 부르는 동안 조각은 이미 삭제 대기열에 있다(worker가 멈춰도 남지 않는다).
        seen.append(ai.calls[number - 1]["key"] in jobs.pending_audio_deletions)

    ai.during = check
    queued = count_calls(jobs, "queue_part_deletion")

    run(worker_for(jobs, storage, ai, CapturingReports()).run_once())

    assert seen == [True, True, True]
    assert [call["defer"] for call in queued] == [True, False] * 3


def test_a_lost_lease_between_parts_stops_without_saving_a_transcript(caplog):
    jobs, storage, analysis_id, _ = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    reports = CapturingReports()
    original_extend = jobs.extend_lease
    calls = []

    async def expire_before_second_part(**kwargs):
        # 첫 조각 STT가 길어 그사이 다른 worker의 임대 정리가 작업을 실패로 끝냈다.
        calls.append(kwargs)
        if len(calls) == 2:
            await jobs.mark_failed(analysis_id=analysis_id, error_code="WORKER_LEASE_EXPIRED")
        return await original_extend(**kwargs)

    jobs.extend_lease = expire_before_second_part

    run(worker_for(jobs, storage, ai, reports).run_once())

    job = job_of(jobs, analysis_id)
    assert (job.status, job.error_code) == (SpeechAnalysisStatus.FAILED, "WORKER_LEASE_EXPIRED")
    assert job.transcript is None and reports.speech is None
    assert len(ai.calls) == 1
    assert storage.objects == {}
    assert jobs.pending_audio_deletions == set()
    assert [r.outcome for r in finished_records(caplog)] == ["stopped"]
    assert (
        f"speech_analysis_stopped analysis_id={analysis_id} stage=transcribing" in caplog.text
    )


def test_a_stop_request_requeues_between_parts_and_keeps_the_original(caplog):
    jobs, storage, analysis_id, original_key = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    reports = CapturingReports()
    notifier = FakeNotifier()
    worker = worker_for(jobs, storage, ai, reports, notifier)
    ai.during = lambda number: worker.request_stop()

    run(worker.run_once())

    # 진행 중이던 첫 조각만 마치고 대기열에 되돌렸다. 원본은 남고 조각은 지웠다.
    job = job_of(jobs, analysis_id)
    assert job.status == SpeechAnalysisStatus.QUEUED
    assert job.audio_deleted_at is None and job.error_code is None
    assert len(ai.calls) == 1
    assert set(storage.objects) == {original_key}
    assert jobs.pending_audio_deletions == set()
    assert notifier.failed == [] and notifier.ready == []
    assert [r.outcome for r in finished_records(caplog)] == ["requeued"]

    # 다음 worker가 처음 조각부터 다시 전사해 끝낸다.
    fresh = PartAi(storage)
    run(worker_for(jobs, storage, fresh, reports, notifier).run_once())
    assert len(fresh.calls) == 3
    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.COMPLETED
    assert storage.objects == {}
    assert notifier.ready == [analysis_id]
    # 다시 시도한 조각은 새 키다. 앞 시도의 남은 삭제 요청이 새 조각을 지우지 못한다.
    assert not {call["key"] for call in fresh.calls} & {call["key"] for call in ai.calls}


def test_a_stop_request_during_the_last_part_still_completes(caplog):
    jobs, storage, analysis_id, _ = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    reports = CapturingReports()
    notifier = FakeNotifier()
    worker = worker_for(jobs, storage, ai, reports, notifier)
    requeued = count_calls(jobs, "requeue")
    ai.during = lambda number: worker.request_stop() if number == 3 else None

    run(worker.run_once())

    # 마지막 조각 뒤에는 시작할 조각이 없으므로 되돌리지 않고 리포트까지 끝낸다.
    assert len(ai.calls) == 3 and requeued == []
    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.COMPLETED
    assert reports.speech is not None and len(reports.speech.segments) == 6
    assert storage.objects == {}
    assert jobs.pending_audio_deletions == set()
    assert notifier.ready == [analysis_id] and notifier.failed == []
    assert [r.outcome for r in finished_records(caplog)] == ["completed"]


def test_a_stop_request_after_the_lease_was_lost_stops_and_deletes_the_original(caplog):
    jobs, storage, analysis_id, original_key = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    reports = CapturingReports()
    notifier = FakeNotifier()
    worker = worker_for(jobs, storage, ai, reports, notifier)
    requeued = count_calls(jobs, "requeue")

    async def lose_lease_then_stop(number):
        # 첫 조각 STT 동안 다른 worker의 임대 정리가 작업을 끝냈고, 그 뒤 종료 요청이 왔다.
        await jobs.mark_failed(analysis_id=analysis_id, error_code="WORKER_LEASE_EXPIRED")
        worker.request_stop()

    ai.during = lose_lease_then_stop

    run(worker.run_once())

    # 되돌리지 못했으므로(requeue가 False) 전사를 저장하지 않고 멈추며 원본을 지운다.
    assert len(requeued) == 1 and len(ai.calls) == 1
    job = job_of(jobs, analysis_id)
    assert (job.status, job.error_code) == (SpeechAnalysisStatus.FAILED, "WORKER_LEASE_EXPIRED")
    assert job.transcript is None and reports.speech is None
    assert original_key in storage.deleted
    assert storage.objects == {}
    assert jobs.pending_audio_deletions == set()
    # 임대 정리로 끝난 작업은 알리지 않는다.
    assert notifier.failed == [] and notifier.ready == []
    assert [r.outcome for r in finished_records(caplog)] == ["stopped"]


def test_a_failed_part_upload_fails_the_job_and_deletes_the_part_and_original(caplog):
    jobs, storage, analysis_id, original_key = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    notifier = FakeNotifier()
    stored = storage.upload

    async def fail_second_part(*, object_key, file):
        await stored(object_key=object_key, file=file)
        if len(storage.uploads) == 3:
            # S3에는 올라갔지만 응답을 받지 못한 경우도 흉내 낸다.
            raise RuntimeError("synthetic upload failure")

    storage.upload = fail_second_part

    run(worker_for(jobs, storage, ai, CapturingReports(), notifier).run_once())

    job = job_of(jobs, analysis_id)
    assert (job.status, job.error_code) == (SpeechAnalysisStatus.FAILED, "SPEECH_ANALYSIS_FAILED")
    assert job.transcript is None
    failed_part = storage.uploads[2]
    assert len(ai.calls) == 1 and failed_part not in {call["key"] for call in ai.calls}
    assert {failed_part, original_key} <= set(storage.deleted)
    assert storage.objects == {}
    assert jobs.pending_audio_deletions == set()
    assert notifier.failed == [analysis_id] and notifier.ready == []
    # 조각별 기록은 STT에 보낸 조각만 센다.
    [record] = finished_records(caplog)
    assert (record.outcome, record.error_code) == ("failed", "SPEECH_ANALYSIS_FAILED")
    assert record.stt_parts == 1


def test_part_timing_counts_only_the_stt_call(caplog):
    jobs, storage, _, _ = setup(THREE_PARTS)
    capture(caplog)
    ai = PartAi(storage)
    stored = storage.upload

    async def slow_upload(*, object_key, file):
        await asyncio.sleep(0.5)
        await stored(object_key=object_key, file=file)

    storage.upload = slow_upload

    run(worker_for(jobs, storage, ai, CapturingReports()).run_once())

    [record] = finished_records(caplog)
    assert record.stt_parts == 3
    assert all(seconds < 0.5 for seconds in record.stt_part_elapsed_seconds)


class BlockingPartUpload:
    """조각 업로드를 시작한 채 붙잡아 둔다. 객체는 먼저 생겨 올리는 중인 스레드를 흉내 낸다."""

    def __init__(self, storage: PartStorage, original_key: str) -> None:
        self.storage = storage
        self.original_key = original_key
        self.stored = storage.upload
        self.started = asyncio.Event()
        self.release = asyncio.Event()
        self.task: asyncio.Task | None = None
        self.key: str | None = None
        storage.upload = self.upload

    async def upload(self, *, object_key, file) -> None:
        await self.stored(object_key=object_key, file=file)
        if object_key == self.original_key:
            return
        self.key = object_key
        self.task = asyncio.current_task()
        self.started.set()
        await self.release.wait()


def test_a_cancel_during_a_part_upload_deletes_the_part_after_the_upload_ends():
    jobs, storage, _, original_key = setup(THREE_PARTS)
    ai = PartAi(storage)
    blocking = BlockingPartUpload(storage, original_key)
    worker = worker_for(jobs, storage, ai, CapturingReports())

    async def scenario():
        task = asyncio.create_task(worker.run_once())
        await blocking.started.wait()
        task.cancel()
        for _ in range(5):
            await asyncio.sleep(0)
        # 업로드가 끝나기 전에는 지우지 않는다(먼저 지우면 끝난 업로드가 조각을 다시 만든다).
        assert not task.done()
        assert blocking.key not in storage.deleted
        blocking.release.set()
        with pytest.raises(asyncio.CancelledError):
            await task

    run(scenario())

    assert ai.calls == []
    assert blocking.key in storage.deleted
    assert set(storage.objects) == {original_key}
    assert jobs.pending_audio_deletions == set()


def test_a_cancelled_part_upload_leaves_the_deferred_deletion_request():
    # 두 번째 종료 신호면 asyncio.run이 업로드 작업까지 취소한다. 스레드는 계속 올릴 수 있다.
    jobs, storage, _, original_key = setup(THREE_PARTS)
    ai = PartAi(storage)
    blocking = BlockingPartUpload(storage, original_key)
    worker = worker_for(jobs, storage, ai, CapturingReports())
    queued = count_calls(jobs, "queue_part_deletion")

    async def scenario():
        task = asyncio.create_task(worker.run_once())
        await blocking.started.wait()
        task.cancel()
        blocking.task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    run(scenario())

    # 끝났는지 모르는 조각은 지금 지우지 않고, 올리기 전에 넣은 요청(임대 시간 뒤)을 남긴다.
    assert blocking.key not in storage.deleted
    assert blocking.key in jobs.pending_audio_deletions
    assert [call["defer"] for call in queued] == [True]


def test_hallucination_filter_and_empty_check_run_on_the_merged_result():
    # 무음 조각에서 나온 알려진 문장만 빠지고 나머지 조각의 대화는 남는다.
    jobs, storage, analysis_id, _ = setup(THREE_PARTS)
    reports = CapturingReports()
    ai = PartAi(storage, texts=["다음 영상에서 만나요.", "합성 대화", "시청해 주셔서 감사합니다."])

    run(worker_for(jobs, storage, ai, reports).run_once())

    assert job_of(jobs, analysis_id).status == SpeechAnalysisStatus.COMPLETED
    assert [s.text for s in reports.speech.segments] == ["합성 대화", "합성 대화"]
    assert [s.speaker_label for s in reports.speech.segments] == ["PART2_SPEAKER_00", None]

    # 모든 조각이 알려진 문장뿐이면 합친 결과가 비어 EMPTY_TRANSCRIPT로 끝난다.
    jobs, storage, analysis_id, _ = setup(THREE_PARTS)
    notifier = FakeNotifier()
    ai = PartAi(storage, texts=["다음 영상에서 만나요."] * 3)
    run(worker_for(jobs, storage, ai, CapturingReports(), notifier).run_once())
    job = job_of(jobs, analysis_id)
    assert (job.status, job.error_code) == (SpeechAnalysisStatus.FAILED, "EMPTY_TRANSCRIPT")
    assert storage.objects == {}
    assert notifier.failed == [analysis_id]


def test_stale_work_dirs_left_by_a_killed_worker_are_removed(tmp_path):
    import os
    import time

    # 맨 위에서 가져온 실제 함수다(자동 fixture는 파이프라인 모듈의 이름만 바꾼다).
    stale = tmp_path / f"{WORK_DIR_PREFIX}stale"
    stale.mkdir()
    (stale / "original.wav").write_bytes(synthetic_wav(("loud", 1600)))
    old = time.time() - 3 * 900 - 60
    os.utime(stale, (old, old))
    # 다른 worker가 지금 쓰는 디렉터리와 이름이 다른 디렉터리는 건드리지 않는다.
    active = tmp_path / f"{WORK_DIR_PREFIX}active"
    active.mkdir()
    other = tmp_path / "other-stale"
    other.mkdir()
    os.utime(other, (old, old))

    assert remove_stale_work_dirs(older_than_seconds=3 * 900, root=tmp_path) == 1

    assert not stale.exists()
    assert active.exists() and other.exists()
